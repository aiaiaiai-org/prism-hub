# Implementation status

## Implemented in the foundation

- Clean Architecture object boundaries and explicit composition root;
- server-side channel configuration with public/private field separation;
- workspace-bound service-principal persistence;
- opaque client-credential issue, expiry, revocation, and atomic rotation;
- SHA-256 digest-only credential storage; raw credentials are not persisted;
- normalized capability and channel grants owned by service principals;
- provider-independent global `UserIdentity` projection for canonical human identity;
- scope-aware provider subjects and durable provider-to-human identity bindings;
- provider binding revocation that preserves historical ownership and forbids implicit reassignment;
- immutable `AuthorisationContext` returned by scoped credential authentication;
- scoped HTTP bearer authentication with explicit `401` for invalid credentials;
- explicit `403` capability and channel-grant enforcement in application use cases;
- `channels:read` discovery filtered before pagination to granted channels only;
- all-or-nothing publication authorization for `publications:validate` and `publications:publish`;
- legacy global bearer bridge disabled by default and activated only by an explicit migration flag;
- PostgreSQL migrations with foreign keys, uniqueness constraints, status checks, and identity-state invariants;
- CI PostgreSQL service, matching PostgreSQL client, migration rollback/reapply verification, and deterministic SQL schema drift checks;
- versioned `v1` endpoints for channel discovery, validation, and publication;
- paginated channel capability discovery with opaque cursors;
- one server-generated request ID across the HTTP and Prism execution boundary;
- multi-target mapping to `prism-execution.v1`;
- bounded process execution, timeout, output limits, response correlation, and safe error mapping;
- OpenAPI 3.1 contract with required `401`/`403` protected-endpoint semantics and deterministic repository checks.

## Explicitly not implemented

- workspace memberships for human identities;
- Telegram actor resolution through provider identity bindings;
- explicit audited provider-identity ownership transfer;
- persistent bot lifecycle state (`active`, `paused`, `disabled`);
- social accounts and per-account human access roles;
- a public/admin HTTP surface for identity, service-principal, or credential provisioning;
- an explicit grant-update use case;
- OAuth authorization, refresh, revocation, or encrypted provider-token storage;
- database-backed channel configuration, drafts, jobs, scheduling, approvals, audit history, or durable publication idempotency;
- media ingest, storage, transformation, or media-reference resolution;
- production container/deployment artifact;
- a production Prism runtime composition root with live provider bindings;
- Instagram publishing.

## Next executable increments

1. Add workspace memberships for `UserIdentity` without merging human identity into workspace policy.
2. Resolve Telegram numeric user IDs through provider bindings and combine human actor evidence with the bot's machine `ServicePrincipal` identity.
3. Add persistent Hub-owned bot lifecycle state (`active`, `paused`, `disabled`).
4. Expose the focused lifecycle operations needed for `/stop`, `/resume`, `/status`, and `/cancel`.
5. Add Meta OAuth with encrypted provider credential storage after the actor and lifecycle boundaries are stable.
6. Wire production packaging and infrastructure before activating live OAuth callbacks.

<!-- © 2026 aiaiaiai · aiaiaiai.org -->
