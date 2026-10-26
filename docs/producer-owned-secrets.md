# Producer-owned production credentials

Prism Hub owns its own runtime credentials even though
`aiaiaiai-org/infra` owns their deployment on `edge-prod-2`.

In the **aiaiaiai-org/prism-hub** GitHub `production` Environment, store:

- `PRISM_POSTGRES_PASSWORD` (Secret): the same password used by the
  `prism-postgres` workload and by Hub's `PGPASSWORD` setting.
- `PRISM_HUB_SECRET_KEY_BASE` (Secret): Rails secret key.
- `PRISM_BOT_DELIVERY_SECRET` (Secret): exactly the `HUA_DELIVERY_SECRET` stored
  in `0x0sky/h-ua-bot`'s production Environment. Never put either value in logs.
- `INFRA_DEPLOY_TOKEN` (Secret): a fine-grained token with access to the
  private `aiaiaiai-org/infra` repository (Contents: write to dispatch;
  Actions: read to retrieve its public recipient artifact).

Both manual workflows request the target Environment's SSH **public** encryption
recipient from infra's `Issue workload encryption recipient` workflow.
The per-request artifact contains only `recipient.pub`, is correlated by the
GitHub Actions run ID, and expires after one day. Neither a persistent
`INFRA_AGE_RECIPIENT` Variable nor an infra SSH private key belongs in this repo.

**Deploy Prism PostgreSQL** encrypts only the database password and dispatches
the image pinned by infra's reviewed contract. **Deploy production** encrypts
the database password, Rails secret, bot delivery secret and the ephemeral
GitHub registry pull token, then dispatches the published Hub image. Both
fail closed if infra access, recipient issuance, artifact validation or
encryption fails. Neither workflow gives the product repo SSH access.
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

## Secret rotation and runtime activation

GitHub Environment secrets are deployment inputs, not a live secret store.
The producer encrypts them, infra assembles the workload environment on the
VPS, and the container receives them at creation. Editing a GitHub secret or
restarting an existing container does not inject the new value.

After rotating `HUA_DELIVERY_SECRET`, set the same value as Hub's
`PRISM_BOT_DELIVERY_SECRET` and redeploy both workloads using their producer
workflows. Do not copy values into source, issue comments or shell output.
During the interval when only one workload has been updated, requests can be
rejected with 401/403. A rollback must restore a matching credential pair;
rolling back only an image does not restore a previous secret.

For the current rollout, the Hub image pins Signal to the merged #16 commit
`4939796b3768419ee71f2bcf36d909e7c2739cf9`. The image build compiles this exact
revision with `--locked`; a merge in Signal alone never updates the Hub binary.
Porter remains pinned independently and is still invoked before HTTP delivery.

After explicit deployment authorization, verify the reviewed edge route,
activate the bot with its new secret, then activate the matching Hub release.
Check both infra workload results, delivery-worker health, and one labelled
synthetic message to the intended test recipient. Confirm a Telegram provider
receipt separately from the recipient seeing the message. Do not replay or
manufacture live threat events as a smoke test.

<!-- © 2026 aiaiaiai · aiaiaiai.org -->
