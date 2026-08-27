# Human identity

Prism Hub separates human identity from machine identity.

`ServicePrincipal` answers which client process is calling Hub. `UserIdentity`
answers which canonical person is acting through that client. A machine
credential is never accepted as proof of a human actor.

`CanonicalIdentityRef` stores only provider-independent `type` and `id` values.
Its type vocabulary aligns with the universal Mind Identity vocabulary, but Hub
does not fetch Mind or depend on a Mind repository at runtime. A Hub
`UserIdentity` is specifically a human runtime projection, so its canonical type
is constrained to `person` in both the domain and PostgreSQL.

Provider handles, Telegram numeric IDs, GitHub IDs, OAuth subjects, and social
account names do not belong in `canonical_id`. They will enter through explicit
provider-binding objects in the next increment.

One `UserIdentity` is global within Hub rather than cloned per workspace.
Workspace access remains a separate relationship so human identity and
authorization policy can evolve independently.

<!-- © 2026 aiaiaiai · aiaiaiai.org -->
