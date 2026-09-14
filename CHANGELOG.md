# Changelog

All notable changes to Prism Hub will be documented here.

## Unreleased

### Changed

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
