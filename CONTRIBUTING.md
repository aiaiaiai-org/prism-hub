# Contributing

Prism Hub follows the aiaiaiai GitHub delivery flow: Draft pull request, Full
CI, green correctness checks, deploy validation when applicable, explicit merge,
and manual deployment after merge.

Every material change must answer the review questions in Prism's normative
[`engineering-principles.md`](https://github.com/aiaiaiai-org/prism/blob/master/docs/engineering-principles.md).
In particular, controllers or HTTP endpoints must not own application policy,
and use cases must depend on focused ports rather than Rails, PostgreSQL,
provider SDKs, or process APIs.

Run the checks documented in the README before requesting review. Start work
from the latest `master` on a `feature/*` or `fix/*` branch. Never commit feature
work directly to `master`.

<!-- © 2026 aiaiaiai · aiaiaiai.org -->
