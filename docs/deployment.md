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

## Container image

`Dockerfile` builds the hub as one image, for a `container` workload of `aiaiaiai-org/infra`:

- Ruby 4.0.6, the hub's gems, and `postgresql-client` for loading `db/structure.sql` into an empty database;
- `prism-signal-collect` and `prism-signal-runtime`, built from `aiaiaiai-org/prism-signal` at a pinned commit (`PRISM_SIGNAL_REV`);
- Porter, from `aiaiaiai-org/prism-porter` at a pinned commit (`PRISM_PORTER_REV`);
- a non-root user, port `1927`, and `GET /healthz` without a credential.

`bin/prism-hub-container` is the image's one process. It runs `rails db:prepare`, so migrations finish before anything serves, and then the web server, the delivery worker, and the signal scheduler together. If any of the three stops, the others are stopped and the container exits with its status, so the container runtime restarts it whole. A hub with a dead scheduler and a live web server would look healthy while telling nobody anything.

The image holds no secret. Configuration is the environment: `DATABASE_URL`, `SECRET_KEY_BASE`, `PRISM_BOT_ORIGIN`, `PRISM_BOT_DELIVERY_SECRET`, `PRISM_SIGNAL_SOURCES_JSON`, and the rest of `.env.example`. The image sets the paths of Porter and the signal binaries, `PORT=1927`, and `RAILS_FORCE_SSL=false` because TLS ends at the edge.

`.github/workflows/image.yml` proves the image builds on every pull request and publishes `ghcr.io/aiaiaiai-org/prism-hub:<commit>` on a merge to `master`. Publishing an image does not deploy it.

Not yet done: the `prism-hub` workload contract in `aiaiaiai-org/infra`. Until it exists, **Deploy production** above has nothing to resolve, and a container workload is dispatched with an `image`, not a `ref`.


<!-- © 2026 aiaiaiai · aiaiaiai.org -->
