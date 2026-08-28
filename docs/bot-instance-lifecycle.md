# Bot instance lifecycle

`BotInstance` is Hub-owned persistent state for one machine client operating inside one human workspace.

A service principal authenticates the machine only. It may therefore own many bot instances, one per workspace. Pausing one instance must not affect another workspace served by the same Telegram process.

Lifecycle states are:

- `active` — ordinary bot behaviour may run for the workspace.
- `paused` — reversible user-controlled pause; the process remains alive.
- `disabled` — administrative or security state; normal resume cannot clear it.

The persistence boundary uses the unique pair `(service_principal_id, workspace_id)`. Every mutation re-checks an active owner membership inside the same database transaction that locks and changes the instance. Creation, pause and resume transitions append lifecycle audit events. Repeated ensure, pause and resume operations are idempotent and do not add duplicate audit events.

This layer intentionally exposes no HTTP endpoint yet. The API contract is a separate delivery increment so persistence invariants can be verified and merged independently before clients depend on them.

<!-- © 2026 aiaiaiai · aiaiaiai.org -->
