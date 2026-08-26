# Security policy

Please report security issues privately to `security@aiaiaiai.org`. Do not open
a public issue for suspected credential exposure, authorization bypass, unsafe
external-action retry behavior, or provider-response leakage.

Hub API credentials and provider credentials are separate. Provider tokens must
remain inside server-side infrastructure adapters and must never appear in API
payloads, logs, exceptions, fixtures, or pull requests.

<!-- © 2026 aiaiaiai · aiaiaiai.org -->
