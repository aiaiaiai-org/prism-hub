# Production credentials

Prism Hub no longer sends credentials to infra. Infra delivers verified images
on its own (see [`deployment.md`](deployment.md)), so the runtime secret values
live where the deployment happens: infra's `edge-prod-2` Environment, under the
names the `prism-hub` workload contract allowlists.

| Secret | Where | Notes |
| --- | --- | --- |
| `PRISM_POSTGRES_PASSWORD` | `aiaiaiai-org/infra` → `edge-prod-2` | the password `prism-postgres` was created with; changing it later does not change the database |
| `PRISM_HUB_SECRET_KEY_BASE` | `aiaiaiai-org/infra` → `edge-prod-2` | Rails secret key |
| `PRISM_BOT_DELIVERY_SECRET` | `aiaiaiai-org/infra` → `edge-prod-2` and `aiaiaiai-org/prism-hub` → `production` | exactly `0x0sky/h-ua-bot` → `production` → `HUA_DELIVERY_SECRET`; this repository keeps a copy only for **Verify h-ua delivery** |

Never put any of these values in logs. This repository holds no infra token,
no encryption recipient and no SSH material.

<!-- © 2026 aiaiaiai · aiaiaiai.org -->
