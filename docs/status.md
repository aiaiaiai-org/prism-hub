# Implementation status

## Implemented in the foundation

- Clean Architecture object boundaries and explicit composition root;
- server-side channel configuration with public/private field separation;
- bearer-authenticated channel, validation, and publication endpoints;
- paginated channel capability discovery with opaque cursors;
- one server-generated request ID across the HTTP and Prism execution boundary;
- multi-target mapping to `prism-execution.v1`;
- bounded process execution, timeout, output limits, response correlation, and
  safe error mapping;
- OpenAPI 3.1 contract and deterministic repository checks;
- Full CI for syntax, style, security analysis, tests, autoloading, contracts,
  architecture, and copyright policy.

## Explicitly not implemented

- accounts, users, workspaces, or role-based authorization;
- OAuth authorization, refresh, revocation, or encrypted provider-token storage;
- database-backed channel configuration, drafts, jobs, scheduling, approvals,
  audit history, or durable idempotency;
- media ingest, storage, transformation, or media-reference resolution;
- production container/deployment artifact;
- a production Prism runtime composition root with live provider bindings;
- Instagram publishing. A `story` or `post` variant in the Hub contract is a
  provider-neutral request shape, not evidence of an Instagram adapter.

## Next executable increments

1. Wire a production Prism composition root without moving provider HTTP or
   credential resolution into Hub policy.
2. Replace environment channel configuration with a workspace-owned repository
   and encrypted OAuth credential adapter.
3. Add durable publication records and database-backed jobs while preserving
   Prism's `outcome_unknown` reconciliation semantics.
4. Add media ingest only alongside a proven provider-media adapter.
5. Package and validate one self-hosted deployment profile.

<!-- © 2026 aiaiaiai · aiaiaiai.org -->
