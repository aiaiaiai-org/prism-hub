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
- HQBase Mail API v1 Device Authorization for an operator-run connection flow,
  requesting only `mail:read offline_access` and never printing access or refresh tokens;
- AES-256-GCM authenticated encryption for persisted HQBase access and refresh tokens,
  with the encryption key supplied only through server secret configuration;
- server-side HQBase credential resolution for Prism Mail digest execution, with
  `mail:read` and token-type checks before the bounded worker process starts;
- automatic HQBase access/refresh-token rotation through the persisted public OAuth
  client identity when an access token is expired or within 60 seconds of expiry;
- fail-closed reconnect semantics for legacy credentials without a persisted OAuth
  client identity and for refresh-token families rejected with `invalid_grant`;
- operator-run Prism Mail digest execution that never accepts or prints raw provider
  tokens and canonicalizes the requested window before crossing the worker boundary;
- OpenAPI 3.1 contract with required `401`/`403` protected-endpoint semantics and deterministic repository checks.

## Explicitly not implemented

- explicit audited provider-identity ownership transfer;
- explicit workspace membership role-change or reactivation operations;
- public/admin social-account provisioning, discovery, role-change, regrant, ownership-transfer, or access-revocation operations;
- a public/admin HTTP surface for identity, service-principal, credential provisioning, HQBase OAuth connection, or mail digest execution;
- an explicit grant-update use case;
- provider-side OAuth credential revocation;
- unattended mail scheduling or delivery;
- binding persisted social accounts to provider credentials and concrete publishing channels;
- database-backed channel configuration, drafts, jobs, scheduling, approvals, audit history, or durable publication idempotency;
- media ingest, storage, transformation, or media-reference resolution;
- production container/deployment artifact;
- a production Prism runtime composition root with live provider bindings;
- Instagram publishing.

## Next executable increments

1. Add controlled scheduling and delivery around the mail digest use case.
2. Add explicit provider-token revocation and reconnect lifecycle operations.
3. Add focused social-account repository/use-case operations without coupling account identity to provider credentials.
4. Add Meta OAuth authorization behind the same encrypted provider-credential boundary.
5. Bind authorized social accounts to server-side channels and credential references without exposing raw provider tokens to clients.

<!-- © 2026 aiaiaiai · aiaiaiai.org -->
