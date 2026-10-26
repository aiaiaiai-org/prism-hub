# Production deployment

Prism Hub production delivery is delegated to the canonical
`aiaiaiai-org/infra` repository.

The repository-side workflow resolves a published release image, requests the
target's public encryption recipient from infra, encrypts producer-owned
runtime credentials and dispatches `deploy-workload` for `prism-hub`.
The **Deploy Prism PostgreSQL** workflow uses the same recipient handoff for
the database password, but is only for explicit database activation.

The infra repository owns the deployment target, SSH credentials, release
layout, systemd service, activation, rollback and retention policy.

A merge never triggers production deployment automatically.

## GitHub Environment

Create or use the `production` Environment in this repository.

Required Environment secret:

- `INFRA_DEPLOY_TOKEN` — fine-grained GitHub token scoped to
  `aiaiaiai-org/infra` with Contents: write and Actions: read.
- `PRISM_POSTGRES_PASSWORD`, `PRISM_HUB_SECRET_KEY_BASE` and
  `PRISM_BOT_DELIVERY_SECRET` — producer-owned runtime secrets.

Do not configure `INFRA_AGE_RECIPIENT`. Infra publishes a short-lived
public-only recipient artifact for each manual deployment request.

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

Infra's workload contracts allowlist runtime credential **names** and own
persistent state. Secret **values** remain in the producer's GitHub Environment.
The workflow encrypts only the required values with the target SSH public key
and sends the armored `secrets_age` envelope in `repository_dispatch`.
Infra decrypts it under its SSH identity; no plaintext application secrets
are included in the dispatch. The recipient artifact contains no private key.

## Deployment contract

The `prism-hub` workload contract in `aiaiaiai-org/infra` is authoritative
for:

- production target;
- container placement and networking;
- runtime secret allowlist and image selection;
- activation, health checks and rollback.

The Prism Hub repository does not duplicate those values.

## Running a deploy

Use **Actions → Deploy production → Run workflow**.

The optional `ref` input defaults to `master`. The workflow verifies that
the ref exists and has a published immutable image. It retrieves a public
recipient from infra, encrypts the producer-owned credentials and dispatches
the workload to `aiaiaiai-org/infra`. This requires an infra-scoped token
authorized for Contents: write and Actions: read.

Activation happens only after the infra repository resolves the workload
contract and obtains its own production Environment credentials.

## Operational boundary

The deployment chain is:

`prism-hub → repository_dispatch → aiaiaiai-org/infra → SSH → production host`

The first arrow carries the image reference and encrypted credential envelope.
SSH private material never leaves infra. A successful producer dispatch
is not proof of activation; check the corresponding infra Deploy workload run.

## Container image

`Dockerfile` builds the hub as one image, for a `container` workload of `aiaiaiai-org/infra`:

- Ruby 4.0.6, the hub's gems, and `postgresql-client` for loading `db/structure.sql` into an empty database;
- `prism-signal-collect` and `prism-signal-runtime`, built from `aiaiaiai-org/prism-signal` at a pinned commit (`PRISM_SIGNAL_REV`);
- Porter, from `aiaiaiai-org/prism-porter` at a pinned commit (`PRISM_PORTER_REV`);
- a non-root user, port `1927`, and `GET /healthz` without a credential.

`bin/prism-hub-container` is the image's one process. It runs `rails db:prepare`, so migrations finish before anything serves, and then the web server, the delivery worker, and the signal scheduler together. If any of the three stops, the others are stopped and the container exits with its status, so the container runtime restarts it whole. A hub with a dead scheduler and a live web server would look healthy while telling nobody anything.

The image holds no secret. Configuration is the environment: `DATABASE_URL`, `SECRET_KEY_BASE`, `PRISM_BOT_ORIGIN`, `PRISM_BOT_DELIVERY_SECRET`, `PRISM_SIGNAL_SOURCES_JSON`, and the rest of `.env.example`. The image sets the paths of Porter and the signal binaries, `PORT=1927`, and `RAILS_FORCE_SSL=false` because TLS ends at the edge.

`.github/workflows/image.yml` proves the image builds on every pull request and publishes `ghcr.io/aiaiaiai-org/prism-hub:<commit>` on a merge to `master`. Publishing an image does not deploy it.

The `prism-hub` workload contract is already present in infra, and a
container workload is dispatched with an `image`, not a `ref`.


<!-- © 2026 aiaiaiai · aiaiaiai.org -->
