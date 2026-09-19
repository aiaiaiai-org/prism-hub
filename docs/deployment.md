# Production deployment

Prism Hub production delivery is delegated to the canonical
`aiaiaiai-org/infra` repository.

The repository-side workflow has one responsibility:

1. validate the requested Git ref;
2. dispatch `deploy-workload` for workload `prism-hub` to `aiaiaiai-org/infra`.

The infra repository owns the deployment target, SSH credentials, release
layout, systemd service, activation, rollback and retention policy.

A merge never triggers production deployment automatically.

## GitHub Environment

Create or use the `production` Environment in this repository.

Required Environment secret:

- `INFRA_DEPLOY_TOKEN` — fine-grained GitHub token scoped to
  `aiaiaiai-org/infra`, with the minimum permission required to create the
  repository dispatch.

The repository no longer stores or consumes production SSH credentials.

Do not add these secrets back to this repository:

- `SSH_HOST`
- `SSH_USER`
- `SSH_PRIVATE_KEY`
- `SSH_KNOWN_HOSTS`
- `SSH_PORT`

Those credentials belong to the target Environment managed by
`aiaiaiai-org/infra`.

## Runtime configuration

Application runtime secrets and persistent state are part of the workload
contract on the deployment host, not of the repository dispatch payload.
They must already exist in the infra-managed shared runtime configuration
before the first activation.

The application release is expected to consume the shared environment supplied
by the infra deployment contract. Repository-side workflows never transfer
production secrets to the infra repository through `repository_dispatch`.

## Deployment contract

The `prism-hub` workload contract in `aiaiaiai-org/infra` is authoritative
for:

- production target;
- deployment path;
- systemd service;
- release retention;
- activation and rollback;
- post-activation commands.

The Prism Hub repository does not duplicate those values.

## Running a deploy

Use **Actions → Deploy production → Run workflow**.

The optional `ref` input defaults to `master`. The workflow verifies that
the requested branch or tag exists and then sends the workload dispatch to
`aiaiaiai-org/infra`.

Activation happens only after the infra repository resolves the workload
contract and obtains its own production Environment credentials.

## Operational boundary

The deployment chain is:

`prism-hub → repository_dispatch → aiaiaiai-org/infra → SSH → production host`

The first arrow carries only deployment intent and a source ref. SSH material
never crosses that boundary.

<!-- © 2026 aiaiaiai · aiaiaiai.org -->
