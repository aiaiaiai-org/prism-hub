#!/usr/bin/env bash
# © 2026 aiaiaiai · aiaiaiai.org
#
# Read-only production delivery authentication check. Sends an invalid body
# WITHOUT chat_id/text/idempotency_key, so no Telegram message can be sent.
set -Eeuo pipefail
umask 077

: "${PRISM_BOT_DELIVERY_SECRET:?Set PRISM_BOT_DELIVERY_SECRET in prism-hub/production}"
if (( ${#PRISM_BOT_DELIVERY_SECRET} < 32 )) ||
   [[ "$PRISM_BOT_DELIVERY_SECRET" == *$'\r'* || "$PRISM_BOT_DELIVERY_SECRET" == *$'\n'* ]]; then
  echo "::error::Invalid Hub delivery secret format (expected one line, >=32 chars)" >&2
  exit 78
fi

for tool in curl jq; do
  command -v "$tool" >/dev/null || { echo "::error::$tool required" >&2; exit 78; }
done

origin="https://api.aiaiaiai.org"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
printf 'x-prism-bot-delivery-secret: %s\n' "$PRISM_BOT_DELIVERY_SECRET" > "$tmp/header"

health() {
  local label="$1" path="$2"
  curl --fail --silent --show-error --proto '=https' --max-time 15 \
    --output "$tmp/health.json" "$origin$path"
  if ! jq -e --arg label "$label" \
    '.status == "ok" and (.service == $label or .service == null)' \
    "$tmp/health.json" >/dev/null; then
    echo "::error::$label did not return healthy JSON" >&2
    exit 1
  fi
  echo "$label: HTTP health ok"
}

health "prism-hub" "/prism-hub/healthz"
health "h-ua-bot" "/hua-bot/health"

# No chat_id, text, idempotency_key or delivery payload. Authentication runs
# before payload validation; 400/invalid_request proves credential acceptance.
status="$(curl --silent --show-error --proto '=https' --max-time 15 \
  --header 'content-type: application/json' \
  --header "@$tmp/header" \
  --data-binary '{}' \
  --output "$tmp/delivery.json" \
  --write-out '%{http_code}' \
  "$origin/hua-bot/api/v1/delivery")"
if [[ "$status" != 400 ]] ||
   ! jq -e '.status == "error" and .error.code == "invalid_request"' \
     "$tmp/delivery.json" >/dev/null; then
  echo "::error::Delivery authentication/routing did not pass (HTTP $status)." >&2
  echo "Check deployed Hub secret versus bot HUA_DELIVERY_SECRET; no Telegram send was attempted." >&2
  exit 1
fi
echo "Hub-to-h-ua-bot delivery authentication accepted; invalid payload rejected."
echo "NOT VERIFIED: hub subscriptions, provider API, source scheduler, Porter, Telegram delivery."
