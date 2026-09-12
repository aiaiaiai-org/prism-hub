# HQBase Mail connection

Prism Hub can connect to an HQBase Mail API v1 deployment without Postman and
without copying an OAuth token through a prompt or command argument.

The operator connection command registers a public OAuth client, requests Device
Authorization for the exact resource `${HQBASE_ORIGIN}/api/v1`, and asks only for
`mail:read offline_access`. It prints the HQBase verification URL and user code,
then polls the token endpoint at the provider-supplied interval. The person opens
the verification URL in a browser they control and explicitly approves access.

After approval, Hub stores the OAuth client identifier plus access and refresh
tokens. Tokens are encrypted with AES-256-GCM and never printed. The encryption key
is supplied through `PRISM_HUB_PROVIDER_TOKEN`, which must decode to exactly 32
random bytes and must live in the server secret store rather than source control.

Connect from the deployed Hub environment:

```sh
bundle exec ruby bin/prism-hub-connect-hqbase-mail
```

Once connected, Hub can discover every mailbox visible to the credential. This is
the supported way to map human-readable addresses to provider mailbox identifiers;
operators do not need ad-hoc Rails scripts or token-bearing curl commands.

```sh
bundle exec ruby bin/prism-hub-list-mailboxes
```

Mailbox discovery uses `GET /api/v1/mailboxes` with the same `mail:read` OAuth
credential. Unknown additive HQBase fields are ignored. The output schema is
`prism-hub.mailboxes.v1` and includes only the mailbox identity and access metadata
needed for selection; OAuth tokens are never emitted.

Hub can execute Prism Mail for one mailbox by setting its provider identifier:

```sh
PRISM_MAIL_MAILBOX_ID=<mailbox-id> \
PRISM_MAIL_SINCE=2026-09-10T00:00:00Z \
PRISM_MAIL_BEFORE=2026-09-11T00:00:00Z \
  bundle exec ruby bin/prism-hub-run-mail-digest
```

`PRISM_MAIL_MAILBOX_ID` is optional. When it is omitted, Hub discovers the visible
mailboxes and executes the deterministic single-mailbox Prism Mail worker once per
mailbox. Hub then returns one `prism-hub.mail-digests.v1` aggregate with per-mailbox
`prism-mail.digest.v1` artifacts and summed matched/selected/omitted counts:

```sh
PRISM_MAIL_SINCE=2026-09-10T00:00:00Z \
PRISM_MAIL_BEFORE=2026-09-11T00:00:00Z \
  bundle exec ruby bin/prism-hub-run-mail-digest
```

The aggregate also exposes a top-level `entries` timeline. It contains the selected
source excerpts from every child digest, tagged with their mailbox metadata and
sorted newest-first across mailbox boundaries. Equal timestamps are resolved by
stable mailbox and evidence identifiers, so the same inputs always produce the same
order. The original per-mailbox digests remain available for provenance.

Before aggregation, Hub verifies that every child artifact preserves the expected
schema, mode, mailbox identity, canonical time window, count invariants, evidence
mailbox boundary, and evidence timestamps. Invalid child output fails the aggregate
instead of silently producing a misleading digest. The request window is validated
before mailbox discovery, so invalid input does not cause provider access.

This ordering is chronological, not semantic. `prism-hub.mail-digests.v1` does not
score importance, classify messages, summarize content, or infer actions. Those are
explicitly outside the extractive digest contract.

Prism Mail remains a single-mailbox deterministic adapter. Mailbox discovery,
selection, OAuth lifecycle, and multi-mailbox orchestration belong to Prism Hub.
This keeps HQBase provider semantics out of Prism Mail's digest contract while
removing provider IDs from the normal all-mailboxes operator path.

Before discovery or execution, Hub resolves and decrypts the active HQBase
credential server-side, verifies `mail:read`, and rotates the access/refresh token
pair through the original public OAuth client when the access token is expired or
within 60 seconds of expiry. The rotated pair replaces the old encrypted credential
before provider access or a bounded Prism Mail worker starts.

Digest artifacts are written to stdout. Treat them as sensitive because extractive
entries may contain mail excerpts. Runtime diagnostics go to stderr and never print
provider tokens.

Required server configuration:

- `HQBASE_ORIGIN=https://mail.aiaiaiai.org` (or another exact HTTPS HQBase origin);
- `PRISM_HUB_PROVIDER_TOKEN=<strict base64 of 32 random bytes>`;
- `PRISM_MAIL_COMMAND_JSON=["prism-mail"]` or another explicit Prism Mail command;
- `PRISM_MAIL_TIMEOUT_SECONDS=30` or another positive timeout;
- the normal Hub `DATABASE_URL` and Rails runtime configuration.

Credentials created before OAuth client identifiers were persisted remain usable
until their access token needs refresh; at that point Hub fails closed with a
reconnect-required error instead of guessing a client identity. HQBase
`invalid_grant` also requires reconnection unless Hub observes that another process
already stored a newer rotated credential.

Connection, discovery, and digest commands are operator boundaries, not public Hub
HTTP endpoints. Provider revocation, scheduling, delivery, and end-user UI remain
separate increments.

<!-- © 2026 aiaiaiai · aiaiaiai.org -->
