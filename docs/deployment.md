# Production deployment

Prism Hub publishes; `aiaiaiai-org/infra` deploys. This repository holds no
credential for infra and never dispatches to it.

## Delivery chain

`Full CI (master) → Publish image → ghcr.io + provenance attestation → infra Reconcile deliveries → infra Deploy workload → edge-prod-2`

1. **Full CI** verifies a commit on `master`.
2. **Publish image** (`.github/workflows/publish.yml`) runs only after a green
   Full CI for the current `master` head. It builds that exact commit, pushes
   `ghcr.io/aiaiaiai-org/prism-hub:<full commit SHA>` and attests the digest's
   build provenance with this workflow's own OIDC identity. A late build of a
   superseded commit is skipped.
3. **Infra** finds the branch head's image, verifies the attestation came from
   this repository, this workflow, `refs/heads/master` and that commit, and
   deploys it through its own **Deploy workload**, with placement, health
   checks and the deployment record (`delivery/prism-hub`). See infra's
   `docs/automatic-delivery.md`.

Publishing is the last step this repository owns. Whether a release is live is
answered by infra's **Deliver workload** run and its `delivery/prism-hub`
deployment, not by this repository. Rollbacks are manual in infra: **Deploy
workload** with an earlier verified digest.

## Runtime configuration

The `prism-hub` workload contract in `aiaiaiai-org/infra` is authoritative for
the target, container placement and networking, the runtime environment, the
secret allowlist, activation, health checks and rollback. This repository does
not duplicate those values.

Runtime secret values live in infra's target Environment (`edge-prod-2`), named
by the contract: `PRISM_POSTGRES_PASSWORD`, `PRISM_HUB_SECRET_KEY_BASE` and
`PRISM_BOT_DELIVERY_SECRET`. A secret the contract names but the Environment
lacks stops the deployment before anything changes. The database itself
(`prism-postgres`) is pinned by its contract and deployed by hand from infra.

The registry pull uses infra's own token: the `prism-hub` package grants
`aiaiaiai-org/infra` **Read** (Package settings → Manage Actions access).

## This repository's `production` Environment

It keeps only what this repository still uses itself:

- `PRISM_BOT_DELIVERY_SECRET` — for **Verify h-ua delivery**, the manual
  handshake against the bot. It must equal infra's copy and
  `0x0sky/h-ua-bot → production → HUA_DELIVERY_SECRET`.

`INFRA_DEPLOY_TOKEN`, `PRISM_POSTGRES_PASSWORD` and `PRISM_HUB_SECRET_KEY_BASE`
are no longer read here and can be deleted. Never add SSH credentials
(`SSH_HOST`, `SSH_USER`, `SSH_PRIVATE_KEY`, `SSH_KNOWN_HOSTS`, `SSH_PORT`): they
belong to infra's target Environment.

## Container image

`Dockerfile` builds the hub as one image, for a `container` workload of `aiaiaiai-org/infra`:

- Ruby 4.0.6, the hub's gems, and `postgresql-client` for loading `db/structure.sql` into an empty database;
- `prism-signal-collect` and `prism-signal-runtime`, built from `aiaiaiai-org/prism-signal` at a pinned commit (`PRISM_SIGNAL_REV`);
- Porter, from `aiaiaiai-org/prism-porter` at a pinned commit (`PRISM_PORTER_REV`);
- a non-root user, port `1927`, and `GET /healthz` without a credential.

`bin/prism-hub-container` is the image's one process. It runs `rails db:prepare`, so migrations finish before anything serves, and then the web server, the delivery worker, and the signal scheduler together. If any of the three stops, the others are stopped and the container exits with its status, so the container runtime restarts it whole. A hub with a dead scheduler and a live web server would look healthy while telling nobody anything.

The image holds no secret. Configuration is the environment: `DATABASE_URL`, `SECRET_KEY_BASE`, `PRISM_BOT_ORIGIN`, `PRISM_BOT_DELIVERY_SECRET`, `PRISM_SIGNAL_SOURCES_JSON`, and the rest of `.env.example`. The image sets the paths of Porter and the signal binaries, `PORT=1927`, and `RAILS_FORCE_SSL=false` because TLS ends at the edge.

`.github/workflows/image.yml` proves the image builds on every pull request. `.github/workflows/publish.yml` publishes and attests it once Full CI has verified the `master` head; infra delivers it from there.

Infra deploys a container workload by its immutable digest, never by a ref.


<!-- © 2026 aiaiaiai · aiaiaiai.org -->
