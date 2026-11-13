# Missed-alert investigation: 2026-11-13 (Prism Hub #78)

This is a diagnostic runbook, **not** evidence that the production incident has been fixed.

## Observation and important distinction

The owner observed @kpszsu updates at 03:05–03:06 Europe/Kyiv about a reactive UAV near named Kyiv districts. The private Telegram chat showed no corresponding **new** alert by 03:12, although an earlier 03:00 alert was visible. Do not publish the owner's exact location, cell, subscriber ID or chat ID.

The default `PRISM_SIGNAL_DELIVERY=board` intentionally sends a new audible status only if `SignalBoardPlan#grew?` sees a higher level (`region` → `here`) or a newly observed *kind* at the same level. Further reports of the same kind at the same level silently edit the board/status. A change in the named district or another track of the same kind does **not** by itself ring. This behavior is covered by `test_more_of_the_same_edits_quietly_and_something_closer_or_new_rings`. Therefore absence of a **new message** is not, alone, proof of delivery failure.

However, the owner did not see an updated board either. This needs independent verification: whether the bot had a pinned board, whether an edit was queued, whether Telegram accepted it, and whether the source posts were ever assessed for the subscription.

## Read-only incident correlation (UTC 2026-11-13 01:00–01:20)

1. Identify deployed Hub image and pinned Signal/Porter commits, effective `PRISM_SIGNAL_DELIVERY`, four source channels, scheduler/worker liveness and errors. Never output secrets.
2. For `telegram.channel:kpszsu`, inspect cursor progression and source evidence around 01:05–01:06 UTC. Distinguish missing post, parsed-but-ignored text, and valid normalized reports. A bare place-name update should inherit threat context **only** if an explicit source/thread relationship justifies it.
3. Trace normalized reports through Signal assessment, Fusion, track state, `cells` and `region_cells` (H3 res 6), and `SignalBoardPlan#relevant`. Do not interpret adjacent place names as a precise UAV trajectory.
4. With the private subscription checked in a restricted environment, determine whether the assessment cell matches `subscription.cell` or `region_cells` with `include_nearby`. Do not export the cell.
5. Inspect `signal_boards` revision, digest, status/board message IDs and pending timestamps. Determine whether the plan emitted no op, a silent edit, or an audible replacement.
6. Correlate delivery outbox, Porter render, bot HTTP response, Telegram provider acknowledgement and recipient observation. Distinguish `not generated`, `filtered`, `silent edit`, `queued`, `rejected`, and `accepted`. Provider acceptance is not a read receipt.
7. Preserve only redacted correlation IDs and outcomes in issue #78; do not publish raw subscriber records.

## Regression expectations

- Same kind/level with a new track or changed place: current contract emits a silent edit; assert that this is intentional before changing notification policy.
- New kind at same level or escalation `region` → `here`: new audible status.
- A source post with insufficient context must not be promoted to a verified track.
- A stale/expired track never creates a false all-clear.
- Failed edits must be observable and retryable without duplicating audible alerts.
- A private, clearly labelled synthetic E2E may be run only with the authorized recipient; it must not masquerade as a real warning.

## Release gate

Do not change the audible-notification policy, geo radius, or source interpretation until a reproducible cause is established and negative controls rule out noisy city-wide alerts. The Nov 6 synthetic delivery acceptance (#56) bypassed ingestion/Fusion/fan-out and does not establish this incident's cause. Any code fix should live in the responsible repository, with tests and full CI before merge; deployment needs separate authorization.
