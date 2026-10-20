# ADR 0001: The hub orchestrates inputs asynchronously

Status: proposed
Date: 2026-10-19

## Context

Prism Hub is meant to be the conductor of the orchestra. Something arrives, the hub does not understand it itself, it asks whoever is responsible what it is, and only if the answer is relevant and the hub can work with it does it have it styled, by another Prism tool or an external one, and delivered.

Today the hub does this for exactly one case, and the case is welded into the core. `docs/signal-alerts.md` describes the loop: a configured Telegram channel is polled with `prism-signal-collect`, a window of evidence is sent to `prism-signal-runtime`, the resulting assessments are fanned out by grid cell, and a `signal.alert` artifact is rendered by Porter. The ear (the collector), the question (`SignalGateway#assess`), the relevance rule (the window, `issued`/`retracted`/`expired`, cool-down), and the voice (`signal.alert` in Porter) all name air threats. A second source, a second kind of question, or a second stylist would be a copy of the loop, not a configuration of it.

Input is also not always a person. A person writing to a bot, a channel the hub listens to, a webhook from another system, and a scheduled tick are the same thing to the conductor: something happened, here is what was seen.

Two facts shape the answer. Responsible parties differ in speed: `prism-signal` answers in milliseconds as a subprocess, while `prism-ai`, `prism-mail`, and external services answer in seconds or minutes, can be down, and can answer twice. And the hub already has the machinery for this kind of work, a durable outbox with idempotency keys and a delivery worker that retries, so the answer should reuse it rather than add a broker.

## Decision

### Vocabulary

| Term | Meaning |
| --- | --- |
| Input | One thing that was seen, with its source and provenance, before anyone has said what it is |
| Listener | Whatever brings an Input in: a poller, a webhook, a client request, a timer |
| Interpreter | The responsible party that says what an Input is |
| Interpretation | An Interpreter's typed answer, or its statement that it does not understand |
| Route | The hub's rule that maps an Interpretation `kind` to a handler |
| Handler | A hub use case that decides what to do with an Interpretation: whom it concerns, whether to act |
| Stylist | The tool that turns a handler's artifact into words and format for a surface |

### An Input is a durable fact

Every Input is stored before anything is asked, as the envelope `prism-hub.input.v1`:

- `input_id`: deterministic from the source and the source's own item identifier, so a listener that sees the same thing twice produces one Input;
- `source`: `id` and `kind` (`telegram.channel`, `bot.message`, `webhook`, …);
- `origin`: who brought it, `listener`, `user`, `webhook` or `hub`;
- `observed_at` and `received_at`: when it happened and when the hub learned of it;
- `content`: a media type and an opaque payload;
- `provenance`: where a person can read the original (a URL), if there is one;
- `workspace`: only if the Input belongs to one.

The hub never stores a precise position. A position that arrives as an Input becomes a grid cell at the edge, through `prism-geo`, before it is stored.

### Interpretation is asynchronous

The hub asks by writing an interpretation request, keyed by `(input_id, interpreter_id, contract_version)`, and sending it through the Interpreter's transport. It does not wait for the answer.

```text
listener ─▶ Input ─▶ inbox ─▶ interpretation request ─▶ Interpreter
                                                           │ (any time later, any number of times)
                     route ◀── Interpretation ◀────────────┘
                       │
                     handler ─▶ artifact ─▶ outbox ─▶ Stylist ─▶ delivery
```

A request is `pending`, `answered`, `not_understood`, `failed`, or `expired`. It carries a deadline and an attempt count.

- **Transports are adapters.** The current subprocess call is one transport, and it answers inline. An HTTP transport posts the request and receives the answer on an authenticated hub endpoint, using the existing machine credentials and capability grants (`interpretations:answer`). A transport that polls is possible. The hub core sees none of them.
- **Answers are idempotent.** The first valid answer for a request wins; a repeat is acknowledged and ignored. An answer for an unknown or expired request is rejected without effect.
- **Unreachable is not an answer.** A request that cannot be delivered is retried with backoff until its deadline, then `expired`. That is logged and never announced to anyone as a statement about the world.
- **Interpreters are asked in a configured order and independently.** Every `understood` answer is routed. The hub does not arbitrate between interpreters that disagree; a handler that cares owns that rule.
- **Context is hub-supplied.** Some Interpreters need more than one Input to answer (the signal runtime assesses a window). The request may carry a bounded `context` the hub assembles by a per-interpreter policy. The Interpreter itself stays stateless.

### Relevance is the hub's decision, not the Interpreter's

An Interpretation is `{kind, result}`, where only `kind` is the hub's concern and `result` is opaque to the core. The Interpreter says what the Input is. The hub decides whether it can work with it:

1. no route for the `kind`: recorded as `unrouted`, nothing happens;
2. a route exists: the handler applies hub policy (whom it concerns, freshness, once-only, cool-down, the person's own switches) and may decide to do nothing;
3. an answer is judged by `observed_at`, not by the time it arrived, so a late answer cannot make old news fresh.

`not_understood` is a normal outcome and ends the matter. The hub does not guess.

### Styling goes through a registry, and happens at dispatch

A handler produces an artifact (`artifact_kind`, `payload`), queued in the existing outbox as `prism-hub.delivery-request.v1`. A Stylist is registered per `artifact_kind`. Porter is the first one. Another Prism tool or an external HTTP service is another registration, not a change to the dispatch code.

Styling stays at dispatch because the size bound depends on the surface that receives it. A Stylist that fails keeps the entry in the outbox for retry. The hub never sends an artifact's raw payload as if it were finished text.

### The existing signal loop becomes the first set of adapters

| Part of today's loop | Becomes |
| --- | --- |
| `prism-signal-collect … poll` and its cursor | A Listener |
| `SignalGateway#assess` over the window | An Interpreter transport (subprocess), with the window as `context` |
| Fan-out by cell, cool-down, retraction rules | A handler for the `signal.assessment` kind |
| `signal.alert` rendered by Porter | A Stylist registration |

Behaviour does not change. Today's tests are the acceptance tests for the move.

## Consequences

- A new source, a new responsible party, or a new stylist is a registration and, at most, an adapter. The core keeps no domain words.
- Slow, remote and unreliable Interpreters fit without blocking a loop. The price is a state machine for requests and more tables: the inbox, interpretation requests, and answers.
- Delivery is at-least-once everywhere, so every step has an idempotency key and every handler must tolerate repeats. The signal ledger already does.
- The hub becomes the only place that decides what is relevant to whom. Interpreters cannot reach a client or a transport, in line with `prism/docs/ecosystem.md`: the hub invokes them, they never call out.
- Latency of a signal alert goes up by one queue hop if the subprocess transport is not answered inline. The inline answer is kept for it, so the first migration adds none.
- More machine principals appear (Interpreters answering over HTTP). Each is a service principal with an explicit grant, which is more to manage and nothing new to design.

## Alternatives considered

- **Synchronous only, as now.** Simple and already built. Rejected because a remote Interpreter that is slow or down would stall the loop or force a timeout that drops real answers.
- **A message broker.** The hub already has a Postgres outbox with idempotency and a worker. A broker is another system to run for the volume of one conductor. Revisit if volume demands it.
- **Interpreters push straight to handlers or clients.** Fewer hops. Rejected because it removes the one place where relevance, freshness and the person's choices are applied.
- **The Interpreter decides relevance.** Rejected: relevance depends on subscriptions, workspaces and policy that only the hub holds.

## Not decided here

- The kind registry: where `signal.assessment` and future kinds are named and versioned.
- How `context` is assembled for an Interpreter that needs history.
- What the hub does when interpreters disagree, if a handler ever needs it solved centrally.
- Whether answers to user-originated Inputs go back to the same surface directly or through the same handler path as everything else.
- The authentication of a callback transport beyond the existing client credentials.

## Migration

Each step is its own pull request and keeps the signal loop's behaviour and tests intact.

1. This ADR.
2. The ports (`Listener`, `Interpreter`, `Stylist`), the inbox and request tables, and the signal loop re-expressed as adapters on them, with the subprocess transport answering inline.
3. The HTTP callback transport and its endpoint, proved with a fake Interpreter.
4. New Listeners and Interpreters, one at a time.

## Engineering review gate

1. **Owner**: input intake, routing, relevance and delivery belong to the hub. What an Input *is* belongs to the Interpreter. How it reads belongs to the Stylist.
2. **Boundary**: Listener, Interpreter and Stylist are ports. Transports and storage are adapters.
3. **Substitution**: any Interpreter that honours the request and answer contract is interchangeable. Contract tests fix the idempotency, expiry and unknown-request behaviour.
4. **Extension**: new sources, interpreters and stylists register through the composition root, never through a switch on a name in core.
5. **Dependencies**: the core depends on its ports only. No Interpreter or Stylist depends on the hub.
6. **Tests**: the signal loop's existing tests stay green across the move. Required CI makes no live calls.

<!-- © 2026 aiaiaiai · aiaiaiai.org -->
