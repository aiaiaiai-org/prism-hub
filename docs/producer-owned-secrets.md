# Producer-owned production credentials

Prism Hub owns its own runtime credentials even though
`aiaiaiai-org/infra` owns their deployment on `edge-prod-2`.

In the **aiaiaiai-org/prism-hub** GitHub `production` Environment, store:

- `PRISM_POSTGRES_PASSWORD` (Secret): the same password used by the
  `prism-postgres` workload and by Hub's `PGPASSWORD` setting.
- `PRISM_HUB_SECRET_KEY_BASE` (Secret): Rails secret key.
- `INFRA_DEPLOY_TOKEN` (Secret): minimum GitHub permission needed to dispatch
  production deployment via `aiaiaiai-org/infra`.
- `INFRA_AGE_RECIPIENT` (Variable): public SSH encryption recipient of
  infra's `edge-prod-2` Environment, obtained from infra's **Show workload
  encryption recipient** manual workflow.

The manual **Deploy Prism PostgreSQL** workflow encrypts only the database
password and dispatches the pinned PostgreSQL image from infra's reviewed
contract. The manual **Deploy production** workflow encrypts the database
password, Rails secret and an ephemeral GHCR pull token, then dispatches the
published Prism Hub image. Neither workflow gives the product repo SSH access.
Both only request a deployment; check infra's own workflow for success.

Do not run the database workflow as part of routine Hub releases. Do not
erase older infra secrets until the encrypted path has been tested, including
recovery and rollback. Prism's alert-delivery routing must be reviewed before
configuring `PRISM_BOT_ORIGIN` for multiple bot instances.

<!-- © 2026 aiaiaiai · aiaiaiai.org -->
