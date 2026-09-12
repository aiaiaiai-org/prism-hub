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
- `SECRET_KEY_BASE` — production Rails secret, at least 64 random characters.
- `PRISM_HUB_PROVIDER_TOKEN` — strict Base64 for exactly 32 random bytes; this encrypts provider credentials at rest.

Optional Environment secret:

- `DATABASE_URL` — explicit PostgreSQL connection URL. When present, Prism Hub uses it as the authoritative database configuration and does not provision or consume the managed VPS-local fallback. When absent, the aiaiaiai deployment path uses the self-hosted PostgreSQL database provisioned on the VPS.

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

## Database selection

Database ownership is provider-agnostic:

1. If `DATABASE_URL` is configured for a Prism Hub deployment, that URL wins.
2. If it is absent, the production workflow falls back to the managed database credential stored locally on the VPS.

This keeps Prism Hub usable with a user's own PostgreSQL service while keeping the aiaiaiai self-hosted default free of a database password in GitHub.

## Managed production database bootstrap

For the aiaiaiai fallback, the Hub database is self-hosted on the VPS. The manual **Bootstrap production database** workflow behaves conditionally:

- when `DATABASE_URL` exists, it records that the configured database is authoritative and skips local PostgreSQL provisioning;
- when `DATABASE_URL` is absent, it connects to the VPS and provisions the managed local database.

The managed fallback is deliberately constrained to:

- role `prism_hub`;
- database `prism_hub_production`;
- host `127.0.0.1`;
- PostgreSQL port `5432`.

The bootstrap generates a 256-bit PostgreSQL password locally with `openssl rand -hex 32`, creates the role/database idempotently, makes `prism_hub` the database owner, removes `PUBLIC` database privileges, verifies a password-authenticated application connection, then writes the canonical runtime connection string to `/srv/prism-hub/shared/database.env` with mode `0600`. The generated password is never printed or returned to GitHub. Re-running the bootstrap reuses the existing managed password instead of rotating it implicitly.

The VPS must already have PostgreSQL installed and locally usable through the `postgres` system account. Package installation is intentionally not hidden inside the database bootstrap: if PostgreSQL is absent, the workflow fails clearly before changing database state.

When `SSH_KNOWN_HOSTS` is not yet configured, managed bootstrap uses a one-time scanned host key so the initial connection can be made and publishes the observed SSH fingerprints and `known_hosts` entries in the Actions summary. Verify those fingerprints against the VPS/provider console before copying the entries into `SSH_KNOWN_HOSTS`; subsequent production deploys are pinned to that secret.

## VPS contract

The deployment account must have:

- Ruby `4.0.6` and Bundler compatible with the committed `Gemfile.lock`;
- `curl`, `tar`, `systemd`, and `systemd-run`;
- passwordless `sudo` for the service-management operations used by `script/deploy-production` and the PostgreSQL bootstrap;
- network access to the selected PostgreSQL database and HQBase;
- the configured `prism-runtime` and `prism-mail` executables available through its deployment `PATH` when those capabilities are used.

The deployment workflow uploads an immutable Git archive plus runtime configuration to the VPS. When the incoming environment contains `DATABASE_URL`, `script/deploy-production` uses it directly. Otherwise it requires `/srv/prism-hub/shared/database.env` and composes that managed VPS-local value with the incoming runtime settings. The resulting `/srv/prism-hub/shared/production.env` is stored with mode `0600`; migrations run before activation, `/srv/prism-hub/current` switches atomically, and `prism-hub.service` is managed through systemd.

The five newest application releases are retained. Normal application deploys do not rotate the managed database password.

## Failure behavior

Deployment fails closed when prerequisites, the selected database configuration, migrations, service startup, or the local `/healthz` check fail. If a previous release exists and the new service fails its health check, the `current` pointer is restored and the service is restarted on the previous release.

Database migrations are not automatically reversed. Production migrations must therefore preserve the repository's normal backward-compatibility expectations for rollback across adjacent releases.

## Running a deploy

For the managed aiaiaiai database, leave `DATABASE_URL` unset and open **Actions → Bootstrap production database → Run workflow** on `master`. After the role/database connection verification succeeds and `SSH_KNOWN_HOSTS` has been pinned, run **Deploy production**.

For an installation with its own PostgreSQL service, configure `DATABASE_URL`; the bootstrap workflow will skip local provisioning and the deploy workflow will use that URL directly.

GitHub applies the `production` Environment controls before either job can access Environment secrets. Both workflows refuse to mutate production from a non-`master` ref.

<!-- © 2026 aiaiaiai · aiaiaiai.org -->
