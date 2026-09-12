# Production deployment

Prism Hub production delivery is intentionally split into two stages:

1. `Validate deploy` proves the repository-side deployment contract without touching production.
2. `Deploy production` is a manual `workflow_dispatch` action that activates a verified `master` commit on the VPS.

A merge never triggers production deployment automatically.

## GitHub Environment

Create or use the `production` Environment in this repository.

Required Environment secrets:

- `SSH_HOST` — SSH hostname or address of the VPS.
- `SSH_USER` — unprivileged SSH deployment account.
- `SSH_PRIVATE_KEY` — private key for that account.
- `SSH_KNOWN_HOSTS` — pinned OpenSSH `known_hosts` entry for the VPS. The deploy workflow never disables host verification. The database bootstrap may perform a one-time `ssh-keyscan` when this secret is not configured yet and reports the observed fingerprints/entries for independent verification and pinning.
- `DATABASE_URL` — production PostgreSQL connection URL. For the self-hosted VPS database it must identify `prism_hub@127.0.0.1:5432/prism_hub_production` (or an equivalent loopback host) and include its password.
- `SECRET_KEY_BASE` — production Rails secret, at least 64 random characters.
- `PRISM_HUB_PROVIDER_TOKEN` — strict Base64 for exactly 32 random bytes; this encrypts provider credentials at rest.

Required Environment variable:

- `HQBASE_ORIGIN` — HTTPS origin only, for example `https://mail.aiaiaiai.org`.

Optional Environment variables:

- `SSH_PORT` — SSH port, default `22`.
- `PRISM_HUB_CHANNELS_JSON` — provider-neutral channel configuration, default `[]`.
- `PRISM_RUNTIME_COMMAND_JSON` — Prism execution command, default `["prism-runtime","--json"]`.
- `PRISM_RUNTIME_TIMEOUT_SECONDS` — default `10`.
- `PRISM_MAIL_COMMAND_JSON` — Prism Mail worker command, default `["prism-mail"]`.
- `PRISM_MAIL_TIMEOUT_SECONDS` — default `30`.
- `PRISM_HUB_PUBLIC_URL` — when configured, the workflow performs a public `/healthz` check after activation.

`HQBASE_ACCESS_TOKEN` is deliberately absent. Hub owns OAuth access/refresh tokens and injects the current access token into Prism Mail only at execution time.

## Production database bootstrap

The Hub database is self-hosted on the VPS. The manual **Bootstrap production database** workflow uses the existing `SSH_HOST`, `SSH_USER`, `SSH_PRIVATE_KEY`, `SSH_PORT`, and `DATABASE_URL` Environment configuration. It does not generate or print a database password; the password already present in `DATABASE_URL` is transferred transiently and used to create/update the local PostgreSQL role.

The bootstrap is deliberately constrained to:

- role `prism_hub`;
- database `prism_hub_production`;
- a loopback PostgreSQL host (`127.0.0.1`, `localhost`, or `::1`);
- the port encoded by `DATABASE_URL` (default `5432`).

It creates the role/database idempotently, makes `prism_hub` the database owner, removes `PUBLIC` database privileges, verifies a password-authenticated connection using the configured `DATABASE_URL` identity, and removes transient bootstrap files.

The VPS must already have PostgreSQL installed and locally usable through the `postgres` system account. Package installation is intentionally not hidden inside the database bootstrap: if PostgreSQL is absent, the workflow fails clearly before changing database state.

When `SSH_KNOWN_HOSTS` is not yet configured, bootstrap uses a one-time scanned host key so the initial connection can be made and publishes the observed SSH fingerprints and `known_hosts` entries in the Actions summary. Verify those fingerprints against the VPS/provider console before copying the entries into `SSH_KNOWN_HOSTS`; subsequent production deploys are pinned to that secret.

## VPS contract

The deployment account must have:

- Ruby `4.0.6` and Bundler compatible with the committed `Gemfile.lock`;
- `curl`, `tar`, `systemd`, and `systemd-run`;
- passwordless `sudo` for the service-management operations used by `script/deploy-production` and the PostgreSQL bootstrap;
- network access to PostgreSQL and HQBase;
- the configured `prism-runtime` and `prism-mail` executables available through its deployment `PATH` when those capabilities are used.

The workflow uploads an immutable Git archive to the VPS. The deployment script installs dependencies into `/srv/prism-hub/shared/bundle`, runs migrations before activation, switches `/srv/prism-hub/current` atomically, and manages `prism-hub.service` through systemd.

Runtime environment values are stored at `/srv/prism-hub/shared/production.env` with mode `0600`. Releases are stored by full Git SHA. The five newest releases are retained.

## Failure behavior

Deployment fails closed when prerequisites, migrations, service startup, or the local `/healthz` check fail. If a previous release exists and the new service fails its health check, the `current` pointer is restored and the service is restarted on the previous release.

Database migrations are not automatically reversed. Production migrations must therefore preserve the repository's normal backward-compatibility expectations for rollback across adjacent releases.

## Running a deploy

For first-time database provisioning, open **Actions → Bootstrap production database → Run workflow** and select `master`. After the role/database connection verification succeeds and `SSH_KNOWN_HOSTS` has been pinned, open **Actions → Deploy production → Run workflow** and select `master`.

GitHub applies the `production` Environment controls before either job can access Environment secrets. Both workflows refuse to mutate production from a non-`master` ref.

<!-- © 2026 aiaiaiai · aiaiaiai.org -->
