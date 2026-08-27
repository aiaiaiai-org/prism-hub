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

## Provider subjects and bindings

External systems enter through an explicit `ProviderSubject` value:

```text
provider + provider_scope + subject_id
```

`provider` identifies the integration namespace, `provider_scope` distinguishes
global identifiers from provider/application-scoped identifiers, and
`subject_id` is the provider's opaque stable subject identifier. Telegram uses
`provider=telegram` and `provider_scope=global`; the model does not assume that
all future providers expose globally scoped IDs.

A `ProviderIdentityBinding` relates one provider subject to one `UserIdentity`.
Provider subjects are evidence about a person, not canonical identities. Handles,
usernames, profile labels, avatars, and other mutable presentation metadata are
not authentication keys and do not participate in identity equality.

The tuple `(provider, provider_scope, subject_id)` is unique for the entire
lifetime of Hub data. Revocation preserves that ownership history. A revoked
provider subject cannot be rebound through ordinary `bind`, even to the same
identity, and revocation does not make a subject available to another identity.
A future ownership transfer must be a separate explicit audited operation rather
than an accidental side effect of revoke-and-bind.

`ResolveProviderIdentity` returns only active bindings whose `UserIdentity` is
also active. Repository lookup can still return revoked bindings for audit and
conflict detection. Provider subject IDs are redacted from default domain
`inspect` output to reduce accidental identifier leakage in debug logs.

One `UserIdentity` is global within Hub rather than cloned per workspace.
Workspace access remains a separate relationship so human identity and
authorization policy can evolve independently.

<!-- © 2026 aiaiaiai · aiaiaiai.org -->
