#!/usr/bin/env bash
# © 2026 aiaiaiai · aiaiaiai.org
#
# Local fixture-only regression for production delivery authentication.
set -Eeuo pipefail
root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT
mkdir -p "$root/bin"
cat > "$root/bin/curl" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
out="" url="" header="" data=""
while (($#)); do
  case "$1" in
    --output|--write-out|--header|--data-binary|--proto|--max-time)
      case "$1" in
        --output) out="$2" ;;
        --header) header="$2" ;;
        --data-binary) data="$2" ;;
      esac
      shift 2 ;;
    --*) shift ;;
    *) url="$1"; shift ;;
  esac
done
case "$url" in
  https://api.aiaiaiai.org/prism-hub/healthz)
    printf '{"status":"ok","service":"prism-hub"}' > "$out" ;;
  https://api.aiaiaiai.org/hua-bot/health)
    printf '{"status":"ok","service":"h-ua-bot"}' > "$out" ;;
  https://api.aiaiaiai.org/hua-bot/api/v1/delivery)
    [[ "$header" == @* && "$data" == '{}' ]] || exit 12
    [[ "$(cat "${header#@}")" == "x-prism-bot-delivery-secret: $PRISM_BOT_DELIVERY_SECRET" ]] || exit 13
    if [[ "$MOCK_RESULT" == accepted ]]; then
      printf '{"status":"error","error":{"code":"invalid_request"}}' > "$out"
      printf '400'
    elif [[ "$MOCK_RESULT" == unauthorized ]]; then
      printf '{"status":"error","error":{"code":"unauthorized"}}' > "$out"
      printf '401'
    else
      printf '{"status":"error","error":{"code":"unknown"}}' > "$out"
      printf '400'
    fi ;;
  *) echo "Unexpected endpoint: $url" >&2; exit 99 ;;
esac
MOCK
chmod +x "$root/bin/curl"
export PATH="$root/bin:$PATH"
export PRISM_BOT_DELIVERY_SECRET="0123456789abcdef0123456789abcdef"
export MOCK_RESULT=accepted
bash script/check-hua-delivery-handshake.sh > "$root/accepted.log"
grep -F 'authentication accepted' "$root/accepted.log" >/dev/null

export MOCK_RESULT=unauthorized
if bash script/check-hua-delivery-handshake.sh > "$root/unauthorized.log" 2>&1; then
  echo "401 must fail" >&2; exit 1
fi
if grep -F "$PRISM_BOT_DELIVERY_SECRET" "$root/unauthorized.log"; then
  echo "Secret must not be logged" >&2; exit 1
fi

export MOCK_RESULT=wrong-body
if bash script/check-hua-delivery-handshake.sh > "$root/wrong.log" 2>&1; then
  echo "Unexpected response body must fail" >&2; exit 1
fi
echo "Mock delivery handshake tests passed."
