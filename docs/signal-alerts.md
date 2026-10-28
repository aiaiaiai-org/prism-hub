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
3. The ingestion window is capped at 500 items **shared fairly across configured sources**, with a maximum of `floor(500 / source_count)` newest reports per channel. The reports are sorted chronologically before being sent to `prism-signal-runtime`: `normalize`, then `assess` with `fusion.v1`. One high-volume channel cannot evict all evidence from quieter channels. The cap may still discard older posts from a very busy channel; window truncation never implies an official all-clear. The runtime is stateless, so the same sampled window gives the same assessment.
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

## Threat incident registry

Prism Hub persists each distinct assessment as a **threat incident** in
`signal_threat_records` before attempting to fan out a notification.

- `id` is a durable server-generated UUID (`threat_id`). The existing
  `assessment_id` is the unique idempotency key for an episode. Neither contains
  a subscriber identifier or Telegram chat ID.
- `hazard_class` and `hazard_kinds` describe what the sources reported.
- `first_reported_at` is the timestamp of the first source report,
  `last_reported_at` is the latest contributing report, and `created_at`
  is when Hub first registered the incident. These are distinct concepts.
- `destination_id` and `destination_name` are the **reported named place**
  for the assessment, not a predicted strike location. Each existing Fusion
  assessment describes one place; reports at different places remain separate
  episodes unless Fusion explicitly links them. The registry never stores
  geographic coordinates.
- `status` is `active`, `expired` or `retracted`. A missing report may
  become `expired` after its validity window; expiry is **not** an all-clear.
  The record retains the attribution URLs and report timestamps even after
  the rolling ingestion window is pruned.
- `source_reports` is a **JSONB array of source-reported threat messages**, not
  a single source or a count. Each entry has `source_id`, `evidence_id`,
  `url`, and `observed_at`. The pair (`source_id`, `evidence_id`) is the
  deduplication key; one channel may report multiple messages, and the full
  history remains after a channel clears or expires. Explicit clears are
  source-specific Fusion events; they are not forged as threat reports.
- `active_sources` is a **separate nullable JSONB array** of unique, sorted
  channel IDs whose source reports are unexpired and uncleared as of the last
  assessment evaluation. `NULL` means an older Signal runtime did not supply
  this field; `[]` means no live source remains. It is not a list of verified
  independent observations, and source count is not a probability of impact.
- `reported_arrival_from`, `reported_arrival_until` and `arrival_source_url`
  are nullable, jointly validated placeholders for an explicitly sourced
  arrival window. **The current pipeline never populates them.** It does not
  estimate a route, compute an impact time from distance/TTL, or invent an ETA.
  Any later source-reported estimate needs a separately reviewed extraction
  contract and visible uncertainty.

The registry is independent of users, subscriptions, delivery and workspace
identity. It is persistent audit state, not a live operational track. An
`assessment_id` can change when its first evidence leaves the 4-hour Fusion
window; until a cross-window episode-identity contract exists, an old and new
record can refer to the same continuing situation. Do not claim global incident
deduplication or prediction precision.

## What is stored

| Table | Holds | Why |
| --- | --- | --- |
| `signal_evidence` | the posts in the window, as the collector emitted them | assessments are recomputed from it |
| `signal_source_cursors` | the newest post read per source | resume without rereading |
| `signal_alert_deliveries` | `(assessment, workspace, kind)` | once-only, cool-down, and whom a retraction reaches |
| `signal_threat_records` | incident UUID, source history, live channel IDs and lifecycle | auditable source-only journal without subscriber identity |

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

`event` is `alert` or `retraction`. `event_at` and `event_url` are the statement that caused this message: the post that reported the threat, or the one that called it off. `sources` contains at most eight **different channel identifiers**, each represented by its newest source report. When `active_sources` is available, active channels are selected first; if absent (older runtime), citations fall back to one latest report per channel. A frequent poster cannot suppress the other configured sources. The full historical `source_reports` array is preserved separately in the threat registry. Porter (`signal.alert`, `prism-hub.signal-alert.v1`) renders it in Ukrainian. `still_active` is filled only for a retraction. The idempotency key is derived from the assessment, the workspace, and the kind, so a retry can never queue a second message.

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

- The input reports are not official air-raid warnings. The collector and runtime cannot make a report true; Porter presents threat and update time without displaying provider names, channel IDs or post URLs, while retaining a clear unofficial-service warning. Neither `retracted` nor `expired` represents an **official air-raid all-clear**. `likelihood` and channel count are not calibrated risk or proof of independent reporting.
- A stale or unreadable source is logged and not announced. Silence from the hub is not safety.
- An episode that outlives the window is re-identified once its first post is dropped, so a person may be told again after the cool-down. That is a true statement about an ongoing threat.
- Alerts are only as good as the subscription's cell: about 3 km, and the cover already adds one ring of margin.
- The loop is a single process. Running two would be safe, since the outbox and ledger are idempotent, but wasteful.

<!-- © 2026 aiaiaiai · aiaiaiai.org -->
