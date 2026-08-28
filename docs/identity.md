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

<!-- © 2026 aiaiaiai · aiaiaiai.org -->
