# Implementation status

## Implemented in the foundation

- Clean Architecture object boundaries and explicit composition root;
- server-side channel configuration with public/private field separation;
- global machine-client `ServicePrincipal` persistence, independent of human
  workspaces and bot lifecycle;
- opaque client-credential issue, expiry, revocation, and atomic rotation;
- SHA-256 digest-only credential storage; raw credentials are not persisted;
- normalized capability and channel grants owned by service principals;
- provider-independent global `UserIdentity` projection for canonical human identity;
- scope-aware provider subjects and durable provider-to-human identity bindings;
- provider binding revocation that preserves historical ownership and forbids implicit reassignment;
- durable workspace memberships separated from global human identity;
- explicit `owner`, `admin`, and `member` membership roles without implicit capability mapping;
- membership revocation with stable history, no implicit reactivation, and last-owner protection;
- generic workspace actor resolution combining machine capability, an explicit
  target workspace, provider evidence, human identity, and active workspace
  membership;
- immutable `WorkspaceActorContext` preserving machine/human identity separation;
- `actors:resolve` machine capability and non-enumerating actor authorization failure semantics;
- versioned `POST /api/v1/actors/resolve` accepting an explicit workspace and
  exposing only canonical human identity and workspace role;
- canonical `0x` public user ID validation and cryptographically random allocation;
- idempotent, concurrency-safe `POST /api/v1/actors/onboard` creating or resolving
  provider identity, personal workspace, and owner membership as one transaction;
- non-enumerating onboarding responses with fail-closed revoked and disabled states;
- read-only personal actor resolution for stateless clients without implicit onboarding;
- persistent per-workspace bot lifecycle state with `active`, `paused`, and `disabled` semantics;
- retained bot lifecycle events with validated state transitions;
- personal bot lifecycle status, pause, and resume use cases and `v1` API operations;
- provider-global `SocialAccount` persistence keyed by immutable provider account identity;
- separate retained `SocialAccountAccess` grants with `owner`, `manager`, and `publisher` roles;
- account-access revocation that preserves history and forbids implicit reassignment,
  reactivation, role mutation, or deletion through ordinary writes;
- active-human account-level publishing eligibility without conflating account access,
  machine authorization, channel grants, or provider credentials;
- immutable `AuthorisationContext` returned by scoped credential authentication;
- scoped HTTP bearer authentication with explicit `401` for invalid credentials;
- explicit `403` capability and channel-grant enforcement in application use cases;
- `channels:read` discovery filtered before pagination to granted channels only;
- all-or-nothing publication authorization for `publications:validate` and `publications:publish`;
- legacy global bearer bridge disabled by default and activated only by an explicit migration flag;
- PostgreSQL migrations with foreign keys, uniqueness constraints, status checks, and identity-state invariants;
- CI PostgreSQL service, matching PostgreSQL client, migration rollback/reapply verification, and deterministic SQL schema drift checks;
- versioned `v1` endpoints for actor resolution, bot lifecycle, channel discovery, validation, and publication;
- paginated channel capability discovery with opaque cursors;
- one server-generated request ID across the HTTP and Prism execution boundary;
- multi-target mapping to `prism-execution.v1`;
- bounded process execution, timeout, output limits, response correlation, and safe error mapping;
- OpenAPI 3.1 contract with required `401`/`403` protected-endpoint semantics and deterministic repository checks.

## Explicitly not implemented

- explicit audited provider-identity ownership transfer;
- explicit workspace membership role-change or reactivation operations;
- public/admin social-account provisioning, discovery, role-change, regrant, ownership-transfer, or access-revocation operations;
- a public/admin HTTP surface for identity, service-principal, or credential provisioning;
- an explicit grant-update use case;
- OAuth authorization, refresh, revocation, or encrypted provider-token storage;
- binding persisted social accounts to provider credentials and concrete publishing channels;
- database-backed channel configuration, drafts, jobs, scheduling, approvals, audit history, or durable publication idempotency;
- media ingest, storage, transformation, or media-reference resolution;
- production container/deployment artifact;
- a production Prism runtime composition root with live provider bindings;
- Instagram publishing.

## Next executable increments

1. Add focused social-account repository/use-case operations without coupling account identity to provider credentials.
2. Add Meta OAuth authorization with encrypted provider credential storage behind a server-side authorization boundary.
3. Bind authorized social accounts to server-side channels and credential references without exposing raw provider tokens to clients.
4. Add a production Prism runtime composition root and run the controlled live Threads validation workflow.
5. Package Hub and `prism-bot` for deployment only after the live provider boundary is verified.

<!-- © 2026 aiaiaiai · aiaiaiai.org -->
