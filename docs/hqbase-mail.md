# HQBase Mail connection

Prism Hub can connect to an HQBase Mail API v1 deployment without Postman and
without copying an OAuth token through a prompt or command argument.

The operator command registers a public OAuth client, requests Device Authorization
for the exact resource `${HQBASE_ORIGIN}/api/v1`, and asks only for
`mail:read offline_access`. It prints the HQBase verification URL and user code,
then polls the token endpoint at the provider-supplied interval. The person opens
the verification URL in a browser they control and explicitly approves access.

After approval, Hub stores the access and refresh tokens encrypted with
AES-256-GCM. Tokens are never printed. The encryption key is supplied through
`PRISM_HUB_PROVIDER_TOKEN_KEY_BASE64`, which must decode to exactly 32 random
bytes and must live in the server secret store rather than source control.

Run from the deployed Hub environment:

```sh
bundle exec ruby bin/prism-hub-connect-hqbase-mail
```

Required server configuration:

- `HQBASE_ORIGIN=https://mail.aiaiaiai.org` (or another exact HTTPS HQBase origin);
- `PRISM_HUB_PROVIDER_TOKEN_KEY_BASE64=<strict base64 of 32 random bytes>`;
- the normal Hub `DATABASE_URL` and Rails runtime configuration.

The command is an operator boundary, not a public Hub HTTP endpoint. Automatic
refresh/revocation and wiring the stored credential into scheduled Prism Mail jobs
are separate increments.

<!-- © 2026 aiaiaiai · aiaiaiai.org -->
