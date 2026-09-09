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

Its public `id` follows the canonical `pub_dress` grammar owned by
[`nilx-one/0x1`](https://github.com/nilx-one/0x1/blob/master/documents/04-identity.md):
the literal `0x` prefix plus a 2–32-character slug. Hub validates the complete
allowlist but its automatic allocator deliberately emits a 20-character
lowercase-letter/digit subset with cryptographic randomness. Public IDs never
derive from provider subject IDs or internal database UUIDs.

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

## Social accounts and access

A social provider account is not a human identity. `SocialAccount` stores
the provider namespace plus the provider-native stable account identifier. The
tuple `(provider, provider_account_id)` is globally unique in Hub. Mutable
usernames and display names are presentation metadata only and never own the
binding. This increment accepts only account IDs that are globally stable within
the provider namespace. Provider/application-scoped IDs must not be stored here
or disguised by changing the provider namespace. Supporting them requires an
explicit scope discriminator in both the domain key and database unique index.

Human access is represented separately by `SocialAccountAccess`:

```text
UserIdentity -> SocialAccountAccess -> SocialAccount
```

Its roles are `owner`, `manager`, and `publisher`; access can be `active` or
`revoked`. This allows one person to connect multiple provider accounts and one
provider account to be shared with multiple authorised people without cloning
the account or conflating access with credentials.

A grant is one retained row per account/person pair. Its identity, role, and
creation timestamp cannot change. Revocation changes active access to revoked
with its first timestamp; repeating the same persisted state is safe. Ordinary
writes cannot reactivate, reassign, delete, or change the role of a grant.
PostgreSQL enforces these transition invariants even for bulk writes and
association removal. Account identity keys are also immutable, while display
metadata remains editable.

Associations expose historical relationships, including revoked grants, and
must never be used as authorization evidence. `can_publish?` requires both an
active grant and an active human identity; it describes account-level eligibility
only, not provider capability, channel permission, or machine authorization.
A future publishing use case must resolve current persisted state and compose
those independent checks at the execution boundary.

This is a persistence foundation, not an access-management API. Explicit audited
role changes, regrant, ownership transfer, and last-owner policy are deferred
together with their focused repository ports and use cases. Ownerless accounts
are representable for discovery/import; this schema does not promise that an
account always has an active owner. Administrative retention/purge operations
are outside ordinary application writes.

OAuth access tokens, refresh tokens, app secrets, and other provider credentials
are deliberately not columns on either entity. Credential acquisition and
secret storage belong to a later server-side authorization boundary. Raw provider
credentials must never enter Telegram clients or become account identity keys.

Concrete publish destinations remain a separate `Channel` concern. A social
account may later own more than one channel/capability surface; this model does
not collapse account ownership into destination selection.

## Workspace membership

One `UserIdentity` is global within Hub rather than cloned per workspace.
Workspace authorization is represented by a separate `WorkspaceMembership`
relation between that identity and one existing workspace.

Membership roles are `owner`, `admin`, and `member`. They describe the human
relationship to a workspace; this increment does not translate roles into hidden
capability grants. Machine capabilities remain attached to `ServicePrincipal`.

There is one stable membership row for each `(workspace, user_identity)` pair.
Granting the same active role is idempotent. A different role requires a future
explicit role-change operation. Revocation preserves the row and its first
`revoked_at`; ordinary grant does not silently reactivate a revoked membership.

The last active `owner` membership cannot be revoked. Ownership transfer is
therefore explicit: establish another active owner first, then revoke the old
owner. This prevents a workspace from becoming human-ownerless through two
independent revoke operations.

`ResolveWorkspaceMembership` returns only an active membership whose
`UserIdentity` is also active.

## Workspace actor resolution

`ResolveWorkspaceActor` composes machine authorization and human evidence
without merging them. The calling `ServicePrincipal` must independently have the
`actors:resolve` capability. Only then may Hub resolve the provider subject,
require an active provider binding and human identity, and require an active
membership in the explicitly requested workspace. The machine principal is
global and never proves that workspace.

Successful resolution produces an immutable `WorkspaceActorContext` containing
the machine principal, workspace, canonical human identity, workspace role, and
provider evidence. Provider subject IDs remain opaque evidence and are not
promoted into canonical identity.

Unknown subjects, revoked bindings, disabled identities, and missing or revoked
memberships intentionally collapse to one authorization failure. This prevents
actor resolution from becoming an identity-enumeration oracle. Incoherent
repository results are treated as an internal invariant failure rather than a
normal authorization denial.

The composed chain is:

```text
client credential -> ServicePrincipal -> actors:resolve
                                      |
provider subject -> ProviderIdentityBinding -> UserIdentity
                                      |
requested workspace --------> WorkspaceMembership
                                      |
                           WorkspaceActorContext
```

Telegram is only one adapter for this generic contract. Its numeric user ID
enters as
`ProviderSubject(provider=telegram, provider_scope=global, subject_id=...)` at
the client/API boundary.

## Provider-backed onboarding

`OnboardProviderIdentity` requires the separate `actors:onboard` machine
capability. One repository transaction resolves or creates the provider
binding, canonical `UserIdentity`, deterministic personal workspace identifier,
and active `owner` membership. The provider-subject unique constraint arbitrates
concurrent first requests; a losing request resolves the committed winner rather
than creating a second identity.

The endpoint returns `200` with the same canonical identity, workspace, and role
shape whether state already existed or was created. It never returns a
`created` flag. Revoked bindings, disabled identities, revoked memberships, and
incoherent personal-workspace state collapse to `hub.actor.not_authorized`, so
onboarding cannot be used as an identity-state enumeration oracle.

Generated public-ID collisions roll back the complete attempted onboarding and
retry with a fresh candidate. After the bounded retry budget is exhausted, Hub
fails without publishing partial identity, binding, workspace, or membership
state.

`ResolvePersonalActor` is the read-only companion for stateless clients after
onboarding. It derives the personal workspace reference from the existing
canonical identity, requires its active `owner` membership, and returns the same
actor projection without creating or reactivating any row. Unknown, revoked,
disabled, missing, and incoherent personal-workspace states collapse to the same
non-enumerating `hub.actor.not_authorized` denial.

<!-- © 2026 aiaiaiai · aiaiaiai.org -->
