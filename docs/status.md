# Implementation status

## Implemented in the foundation

- Clean Architecture object boundaries and explicit composition root;
- server-side channel configuration with public/private field separation;
- workspace-bound service-principal persistence;
- explicit service-principal provisioning with principal-owned capability/channel grants;
- credential issue that requires a pre-provisioned principal and cannot mutate grants;
- opaque client-credential expiry, revocation, and atomic rotation;
- SHA-256 digest-only credential storage; raw credentials are not persisted;
- immutable `AuthorisationContext` returned by the credential repository;
- PostgreSQL migration with foreign keys, uniqueness constraints, status checks, and digest-format validation;
- CI PostgreSQL service plus migration rollback/reapply verification;
- bearer-authenticated `v1` endpoints for channel discovery, validation, and publication using the existing global-token bridge;
- paginated channel capability discovery with opaque cursors;
- one server-generated request ID across the HTTP and Prism execution boundary;
- multi-target mapping to `prism-execution.v1`;
- bounded process execution, timeout, output limits, response correlation, and safe error mapping;
- OpenAPI 3.1 contract and deterministic repository checks.

## Explicitly not implemented

- scoped client credentials wired into HTTP authentication and authorization;
- capability/channel-grant enforcement on HTTP routes;
- an operation for changing grants on an existing service principal;
- human accounts, users, memberships, or interactive role management;
- a public/admin HTTP surface for service-principal or credential provisioning;
- OAuth authorization, refresh, revocation, or encrypted provider-token storage;
- database-backed channel configuration, drafts, jobs, scheduling, approvals, audit history, or durable publication idempotency;
- media ingest, storage, transformation, or media-reference resolution;
- production container/deployment artifact;
- a production Prism runtime composition root with live provider bindings;
- Instagram publishing.

## Next executable increments

1. Replace the global HTTP token path with scoped credential authentication and explicit `401`/`403` semantics, keeping the old token only as a disabled-by-default migration bridge.
2. Enforce route capabilities and per-channel grants from `AuthorisationContext`.
3. Add Telegram actor-to-service-principal authorization.
4. Add persistent bot lifecycle state (`active`, `paused`, `disabled`).
5. Wire a production Prism composition root without moving provider HTTP or credential resolution into Hub policy.

<!-- © 2026 aiaiaiai · aiaiaiai.org -->
