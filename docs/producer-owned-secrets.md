# Producer-owned production credentials

Prism Hub owns its runtime credentials. Infra deploys the hub but holds only
its own `SSH_*`; it never stores a Prism secret. The values may be shared with
another product that needs the same one, never with infra.

In the **aiaiaiai-org/prism-hub** GitHub `production` Environment, store:

| Secret | Notes |
| --- | --- |
| `PRISM_POSTGRES_PASSWORD` | the password `prism-postgres` was created with, and Hub's `PGPASSWORD`; changing it later does not change the database |
| `PRISM_HUB_SECRET_KEY_BASE` | Rails secret key |
| `PRISM_BOT_DELIVERY_SECRET` | exactly `HUA_DELIVERY_SECRET` in `0x0sky/h-ua-bot`'s production Environment; also used by **Verify h-ua delivery** |

They reach the workload only in an `age` envelope encrypted to the target
server's public SSH key, which infra's server contract publishes. Only infra's
deploy job, holding that server's private key, can decrypt it, and it keeps
nothing. Never put any of these values in logs.

This repository holds no infra token and no SSH material.

<!-- © 2026 aiaiaiai · aiaiaiai.org -->
