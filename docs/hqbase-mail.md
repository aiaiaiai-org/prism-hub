# HQBase Mail connection

Prism Hub can connect to an HQBase Mail API v1 deployment without Postman and
without copying an OAuth token through a prompt or command argument.

The operator connection command registers a public OAuth client, requests Device
Authorization for the exact resource `${HQBASE_ORIGIN}/api/v1`, and asks only for
`mail:read offline_access`. It prints the HQBase verification URL and user code,
then polls the token endpoint at the provider-supplied interval. The person opens
the verification URL in a browser they control and explicitly approves access.

After approval, Hub stores the access and refresh tokens encrypted with
AES-256-GCM. Tokens are never printed. The encryption key is supplied through
`PRISM_HUB_PROVIDER_TOKEN`, which must decode to exactly 32 random bytes and must
live in the server secret store rather than source control.

Connect from the deployed Hub environment:

```sh
bundle exec ruby bin/prism-hub-connect-hqbase-mail
```

Once connected, Hub can execute a Prism Mail digest without accepting or exposing
an access token at the command boundary. It resolves and decrypts the active HQBase
credential server-side, verifies `mail:read`, rejects an expired access token, and
passes the token only to the bounded Prism Mail subprocess environment.

```sh
PRISM_MAIL_MAILBOX_ID=<mailbox-id> \
PRISM_MAIL_SINCE=2026-09-10T00:00:00Z \
PRISM_MAIL_BEFORE=2026-09-11T00:00:00Z \
  bundle exec ruby bin/prism-hub-run-mail-digest
```

The digest artifact is written to stdout. Treat it as sensitive because extractive
entries may contain mail excerpts. Runtime diagnostics go to stderr and never print
provider tokens.

Required server configuration:

- `HQBASE_ORIGIN=https://mail.aiaiaiai.org` (or another exact HTTPS HQBase origin);
- `PRISM_HUB_PROVIDER_TOKEN=<strict base64 of 32 random bytes>`;
- `PRISM_MAIL_COMMAND_JSON=["prism-mail"]` or another explicit Prism Mail command;
- `PRISM_MAIL_TIMEOUT_SECONDS=30` or another positive timeout;
- the normal Hub `DATABASE_URL` and Rails runtime configuration.

Connection and digest commands are operator boundaries, not public Hub HTTP
endpoints. Automatic refresh-token rotation, revocation, scheduling and delivery
remain separate increments.

<!-- © 2026 aiaiaiai · aiaiaiai.org -->
