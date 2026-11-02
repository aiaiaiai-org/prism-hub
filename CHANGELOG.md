# Changelog

All notable changes to Prism Hub will be documented here.

## Unreleased

### Changed

- Delivery moved to `aiaiaiai-org/infra`'s pull model: `Publish image` pushes and attests
  each Full CI-verified `master` head, and infra deploys it. `Deploy production`,
  `Deploy Prism PostgreSQL`, the infra recipient scripts and `INFRA_DEPLOY_TOKEN` are removed;
  runtime secrets stay in this repository's `production` Environment and never go to infra.
- `Publish image` also seals the runtime secrets to the target server's public key and publishes
  them as `ghcr.io/aiaiaiai-org/prism-hub:<sha>.secrets`, attested like the image.
- Delivery presentation now runs at dispatch instead of enqueue. The outbox holds a
  `prism-hub.delivery-request.v1` envelope and Porter is invoked once a surface is
  resolved, so the message split follows the target that receives it.
- The chunk bound is derived from the resolved targets, taking the smallest limit when
  several are bound to one logical channel. `PRISM_PORTER_CHUNK_MAX_CHARS` became a
  ceiling that can only lower that bound; previously any value up to 100000 was passed
  through and produced messages Telegram rejects.
- `PRISM_PORTER_COMMAND_JSON` and `PRISM_PORTER_TIMEOUT_SECONDS` are now read by the
  delivery worker rather than the enqueue command.

- Decoupled machine client credentials from human workspaces and bot lifecycle instances.
- Made actor resolution authorize an explicitly requested workspace through human membership.

### Added

- `POST /api/v1/telegram/surfaces/bind` is now part of the OpenAPI contract (API version
  `0.1.0-alpha.10`), and `bot_instance_id` is optional: omitted, it is the calling bot's own
  instance in that workspace. Bot instance identifiers are not part of the public API, so a client
  could not have supplied one.
- The signal loop: `bin/prism-hub-signal-scheduler` reads public Telegram channels through `prism-signal-collect poll`, keeps a window of evidence, assesses it with `prism-signal-runtime` (`prism-signal.v1`), and fans the result out to alert subscriptions by cell into the delivery outbox as `signal.alert` artifacts. An alert reaches a person once per assessment and at most once per cool-down per hazard class; a retraction reaches only the people who were told the alert, and names other reports that still cover them; an expiry says nothing. New tables `signal_evidence`, `signal_source_cursors`, and `signal_alert_deliveries`; clearing a subscription also deletes what the person was told. See `docs/signal-alerts.md`.
- Personal alert subscriptions: one subscription per personal workspace holding a resolution 6 grid
  cell (about 3 km), the categories (`drone`, `bomb`, `missile`) and a nearby-warnings flag. The client
  derives the cell from a position and sends only the cell, so the Hub never receives coordinates.
  `POST /api/v1/alert-subscriptions/personal/{status,save,clear}`, the
  `alert_subscriptions:read` and `alert_subscriptions:manage` capabilities, and API version
  `0.1.0-alpha.9`. Clearing deletes the row.
- Idempotent provider-backed actor onboarding with public user IDs and personal workspaces.
- Read-only provider-backed personal actor resolution for stateless clients.
- Per-workspace persistent bot lifecycle state with audit history.
- Personal bot lifecycle status, pause, and resume API operations.
- Provider-account persistence separated from human access through `SocialAccount` and `SocialAccountAccess`.
- Initial Clean Architecture foundation.
- Versioned channel, validation, and publication API contract.
- Injected `prism-execution.v1` process adapter.
- Provider-neutral Prism Porter gateway with strict `prism-porter.delivery-intent.v1` verification.
- Audited Telegram surface bindings from logical Porter context to chat/topic transport coordinates.

<!-- © 2026 aiaiaiai · aiaiaiai.org -->
