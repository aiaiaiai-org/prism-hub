# Changelog

All notable changes to Prism Hub will be documented here.

## Unreleased

### Changed

- Decoupled machine client credentials from human workspaces and bot lifecycle instances.
- Made actor resolution authorize an explicitly requested workspace through human membership.

### Added

- Idempotent provider-backed actor onboarding with public user IDs and personal workspaces.
- Read-only provider-backed personal actor resolution for stateless clients.
- Per-workspace persistent bot lifecycle state with audit history.
- Personal bot lifecycle status, pause, and resume API operations.
- Initial Clean Architecture foundation.
- Versioned channel, validation, and publication API contract.
- Injected `prism-execution.v1` process adapter.

<!-- © 2026 aiaiaiai · aiaiaiai.org -->
