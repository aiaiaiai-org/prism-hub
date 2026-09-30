# Signal alerts

The signal loop turns what public sources say into messages for the people whose subscription covers the place. It is `bin/prism-hub-signal-scheduler`. Reading and judging text belongs to [Prism Signal](https://github.com/aiaiaiai-org/prism-signal); the hub decides only whom to tell.

```text
sources ──▶ collector (poll) ──▶ window ──▶ prism-signal-runtime ──▶ assessments + events
                                                                        │
subscriptions (cell, categories, nearby) ◀── fan-out by cell ◀──────────┘
                                                  │
                                         outbox: signal.alert ──▶ Porter ──▶ bot ──▶ Telegram
```

## One pass

Every interval (default 60 s):

1. Each source is read with `prism-signal-collect telegram <channel> poll --after <cursor>`. The evidence is stored, and the cursor moves to the newest post seen. It never moves back. A source that cannot be read is logged and skipped; the pass continues.
2. Evidence older than the window (default 4 h) is dropped.
3. The window, at most 500 items, is sent to `prism-signal-runtime`: `normalize`, then `assess` with `fusion.v1`. The runtime is stateless, so the window is recomputed every pass and the same posts give the same events.
4. The events are fanned out (below), and ledger entries older than 24 h are deleted.

A pass that fails is logged and the loop goes on. A scheduler that dies leaves people without alerts and without any sign of it.

## Who is told

| Event | Rule |
| --- | --- |
| `issued`, `superseded` | An alert goes to each subscription whose cell is among the assessment's cells and that asked for its class (`drone`, `bomb`, `missile`). A `nearby` assessment reaches only those with `include_nearby`. The assessment must still be active |
| `retracted` | A retraction goes only to people who were told the alert for that assessment, and only while they still subscribe. It names other active reports of the same class that still cover their cell, so it never reads as "you are safe" while something else stands over them |
| `expired` | Nothing. A threat that lapses on its window is not an all-clear, and the hub never states one |

Also:

- **Once.** A person is told about one assessment once and its retraction once, however many posts renew it.
- **Cool-down.** After an alert, the same person gets no other alert of the same class for `PRISM_SIGNAL_COOLDOWN_SECONDS` (default 300). Different classes are independent. A held-back alert is not recorded, so its retraction is not sent either.
- **Maximum age.** Events older than `PRISM_SIGNAL_MAX_AGE_SECONDS` (default 1800) are history. After downtime the hub does not replay them.
- **A chat is required.** A subscriber with no active Telegram surface bound to the logical channel (default `alerts`) is skipped.
- **One failure is one failure.** A delivery that cannot be queued is logged and left unrecorded, so the next pass tries again while the event is recent. Everyone else is unaffected.

## What is stored

| Table | Holds | Why |
| --- | --- | --- |
| `signal_evidence` | the posts in the window, as the collector emitted them | assessments are recomputed from it |
| `signal_source_cursors` | the newest post read per source | resume without rereading |
| `signal_alert_deliveries` | `(assessment, workspace, kind)` | once-only, cool-down, and whom a retraction reaches |

The ledger holds a workspace and an assessment id. An assessment id names a class and a place, so it implies where someone was. It is therefore deleted after 24 h and whenever the person clears their subscription. The queued message carries the place the report is about and never the person's cell.

## The `signal.alert` artifact

Queued in the outbox as a `prism-hub.delivery-request.v1` envelope with artifact kind `signal.alert`; Porter renders it at dispatch. The payload:

```json
{
  "schema_version": "prism-hub.signal-alert.v1",
  "event": "alert",
  "hazard": {"class": "drone", "kinds": ["air.attack_drone"]},
  "place": {"name": "Київ"},
  "proximity": "target",
  "likelihood": "moderate",
  "first_reported_at": "2026-09-30T11:59:00Z",
  "valid_until": "2026-09-30T12:29:00Z",
  "event_at": "2026-09-30T11:59:00Z",
  "event_url": "https://t.me/vanek_nikolaev/43222",
  "sources": [{"source_id": "telegram.channel:vanek_nikolaev", "url": "https://t.me/vanek_nikolaev/43222", "observed_at": "2026-09-30T11:59:00Z"}],
  "still_active": []
}
```

`event` is `alert` or `retraction`. `event_at` and `event_url` are the statement that caused this message: the post that reported the threat, or the one that called it off. `sources` holds the newest three reports. Porter (`signal.alert`, `prism-hub.signal-alert.v1`) renders it in Ukrainian. `still_active` is filled only for a retraction. The idempotency key is derived from the assessment, the workspace, and the kind, so a retry can never queue a second message.

## Configuration

| Variable | Default | Meaning |
| --- | --- | --- |
| `PRISM_SIGNAL_TELEGRAM_CHANNELS` | one of these two | public channel usernames, comma separated: `vanek_nikolaev,other` |
| `PRISM_SIGNAL_SOURCES_JSON` | one of these two | `[{"kind":"telegram","channel":"<public username>"}]` |
| `PRISM_SIGNAL_COLLECT_COMMAND_JSON` | `["prism-signal-collect"]` | collector command |
| `PRISM_SIGNAL_RUNTIME_COMMAND_JSON` | `["prism-signal-runtime","--json"]` | runtime command |
| `PRISM_SIGNAL_TIMEOUT_SECONDS` | 60 | per subprocess |
| `PRISM_SIGNAL_INTERVAL_SECONDS` | 60 | pause between passes |
| `PRISM_SIGNAL_WINDOW_SECONDS` | 14400 | how long evidence is kept and assessed |
| `PRISM_SIGNAL_MAX_AGE_SECONDS` | 1800 | events older than this are not sent |
| `PRISM_SIGNAL_COOLDOWN_SECONDS` | 300 | per person, per class |
| `PRISM_SIGNAL_ALERT_CHANNEL` | `alerts` | logical channel the bound chat is looked up by |
| `PRISM_SIGNAL_ONESHOT` | unset | `true` runs one pass and exits |

A channel name is checked against Telegram's rules for a public username before it reaches a command line.

## Limits

- The sources are unofficial and the reading is heuristic. The window and the runtime cannot make a report true; alerts and retractions are proposals from a channel, and Porter's wording must say so.
- A stale or unreadable source is logged and not announced. Silence from the hub is not safety.
- An episode that outlives the window is re-identified once its first post is dropped, so a person may be told again after the cool-down. That is a true statement about an ongoing threat.
- Alerts are only as good as the subscription's cell: about 3 km, and the cover already adds one ring of margin.
- The loop is a single process. Running two would be safe, since the outbox and ledger are idempotent, but wasteful.

<!-- © 2026 aiaiaiai · aiaiaiai.org -->
