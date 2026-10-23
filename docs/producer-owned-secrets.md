# Producer-owned production credentials

Prism Hub owns its own runtime credentials even though
`aiaiaiai-org/infra` owns their deployment on `edge-prod-2`.

In the **aiaiaiai-org/prism-hub** GitHub `production` Environment, store:

- `PRISM_POSTGRES_PASSWORD` (Secret): the same password used by the
  `prism-postgres` workload and by Hub's `PGPASSWORD` setting.
- `PRISM_HUB_SECRET_KEY_BASE` (Secret): Rails secret key.
- `PRISM_BOT_DELIVERY_SECRET` (Secret): exactly the `HUA_DELIVERY_SECRET` stored
  in `0x0sky/h-ua-bot`'s production Environment. Never put either value in logs.
- `INFRA_DEPLOY_TOKEN` (Secret): minimum GitHub permission needed to dispatch
  production deployment via `aiaiaiai-org/infra`.
- `INFRA_AGE_RECIPIENT` (Variable): public SSH encryption recipient of
  infra's `edge-prod-2` Environment, obtained from infra's **Show workload
  encryption recipient** manual workflow.

The manual **Deploy Prism PostgreSQL** workflow encrypts only the database
password and dispatches the pinned PostgreSQL image from infra's reviewed
contract. The manual **Deploy production** workflow encrypts the database
password, Rails secret, bot delivery secret and an ephemeral GHCR pull token, then dispatches the
published Prism Hub image. Neither workflow gives the product repo SSH access.
Both only request a deployment; check infra's own workflow for success.

Do not run the database workflow as part of routine Hub releases. Do not
erase older infra secrets until the encrypted path has been tested, including
recovery and rollback. Prism's alert-delivery routing must be reviewed before
configuring `PRISM_BOT_ORIGIN` for multiple bot instances.

## Bot delivery route

Infra supplies `PRISM_BOT_ORIGIN=https://api.aiaiaiai.org` and
`PRISM_BOT_PATH_PREFIX=/hua-bot`. The worker sends HTTPS POST requests to
`/hua-bot/api/v1/delivery`; Caddy strips only `/hua-bot`.
The origin stays path-free. The prefix defaults to empty for existing callers,
and rejects traversal, encoded separators, queries and fragments.

Porter remains in the dispatch path before the HTTP gateway: it renders the
artifact into chunks, whose payload, authentication and idempotency keys are
unchanged by the prefix. Prism Bot and h-ua-bot retain their existing
`/api/v1/delivery` contract; neither needs an application path-prefix change.

This worker still has one global bot destination. It must not be shared with
unrelated bot destinations until per-bot routing is implemented.
The separate `/hua/` product API is not exposed by this change.

Rollout: configure matching secrets in the two producer Environments; activate
the reviewed edge route before deploying the updated Hub image and infra
contract. Preserve the existing bot-to-Hub `HUA_HUB_ORIGIN`.
Use a labelled synthetic delivery to the intended test chat to verify Porter,
bot authentication and the Telegram acknowledgement. No live delivery is
established by a successful build alone. Deployment remains a separate action.

<!-- © 2026 aiaiaiai · aiaiaiai.org -->
