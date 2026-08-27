# Implementation status

## Implemented in the foundation

- Clean Architecture object boundaries and explicit composition root;
- server-side channel configuration with public/private field separation;
- workspace-bound service-principal persistence;
- opaque client-credential issue, expiry, revocation, and atomic rotation;
- SHA-256 digest-only credential storage; raw credentials are not persisted;
- normalized capability and channel grants owned by service principals;
- immutable `AuthorisationContext` returned by scoped credential authentication;
- scoped HTTP bearer authentication with explicit `401` for invalid credentials;
- explicit `403` capability and channel-grant enforcement in application use cases;
- `channels:read` discovery filtered before pagination to granted channels only;
- all-or-nothing publication authorization for `publications:validate` and `publications:publish`;
- legacy global bearer bridge disabled by default and activated only by an explicit migration flag;
- PostgreSQL migration with foreign keys, uniqueness constraints, status checks, and digest-format validation;
- CI PostgreSQL service, matching PostgreSQL client, migration rollback/reapply verification, and deterministic SQL schema drift checks;
- versioned `v1` endpoints for channel discovery, validation, and publication;
- paginated channel capability discovery with opaque cursors;
- one server-generated request ID across the HTTP and Prism execution boundary;
- multi-target mapping to `prism-execution.v1`;
- bounded process execution, timeout, output limits, response correlation, and safe error mapping;
- OpenAPI 3.1 contract with required `401`/`403` protected-endpoint semantics and deterministic repository checks.

## Explicitly not implemented

- Telegram actor-to-service-principal authorization;
- persistent bot lifecycle state (`active`, `paused`, `disabled`);
- human accounts, users, memberships, or interactive role management;
- a public/admin HTTP surface for service-principal or credential provisioning;
- an explicit grant-update use case;
- OAuth authorization, refresh, revocation, or encrypted provider-token storage;
- database-backed channel configuration, drafts, jobs, scheduling, approvals, audit history, or durable publication idempotency;
- media ingest, storage, transformation, or media-reference resolution;
- production container/deployment artifact;
- a production Prism runtime composition root with live provider bindings;
- Instagram publishing.

## Next executable increments

1. Add Telegram actor authorization in `prism-bot`, binding the numeric Telegram user ID to the Hub service principal without duplicating workspace policy in the bot.
2. Add persistent Hub-owned bot lifecycle state (`active`, `paused`, `disabled`).
3. Expose the focused lifecycle operations needed for `/stop`, `/resume`, `/status`, and `/cancel`.
4. Add Meta OAuth with encrypted provider credential storage after the lifecycle boundary is stable.
5. Wire production packaging and infrastructure before activating live OAuth callbacks.

<!-- © 2026 aiaiaiai · aiaiaiai.org -->
