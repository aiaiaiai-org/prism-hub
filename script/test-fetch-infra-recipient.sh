#!/usr/bin/env bash
# © 2026 aiaiaiai · aiaiaiai.org
# Regression: a failed prior issuance must not poison a job rerun.
set -Eeuo pipefail
root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT
mkdir -p "$root/bin" "$root/runner"
ssh-keygen -q -t ed25519 -N '' -f "$root/identity" >/dev/null
cp "$root/identity.pub" "$root/public.key"
jq -n --arg title "Recipient prism-hub / 123456" \
  '{workflow_runs:[{id:101,display_title:$title,event:"repository_dispatch",head_branch:"master",status:"completed",conclusion:"failure"}]}' > "$root/old.json"
jq -n --arg title "Recipient prism-hub / 123456" \
  '{workflow_runs:[{id:101,display_title:$title,event:"repository_dispatch",head_branch:"master",status:"completed",conclusion:"failure"},
    {id:202,display_title:$title,event:"repository_dispatch",head_branch:"master",status:"completed",conclusion:"success"}]}' > "$root/new.json"
cat > "$root/bin/gh" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "$1" == api ]]; then
  if [[ "$2" == --silent ]]; then exit 0; fi
  if [[ "$2" == --method && "$3" == POST ]]; then touch "$GH_MOCK_ROOT/dispatched"; exit 0; fi
  if [[ "$2" == *"/runs?"* ]]; then
    if [[ -e "$GH_MOCK_ROOT/dispatched" ]]; then
      cat "$GH_MOCK_ROOT/new.json"
    else
      cat "$GH_MOCK_ROOT/old.json"
    fi
    exit 0
  fi
elif [[ "$1" == run && "$2" == download ]]; then
  [[ "$3" == 202 ]] || exit 1
  dir=""
  while (( $# > 0 )); do
    if [[ "$1" == --dir ]]; then dir="$2"; break; fi
    shift
  done
  [[ -n "$dir" ]] || exit 1
  cp "$GH_MOCK_ROOT/public.key" "$dir/recipient.pub"
  if [[ "$GH_MOCK_BAD_KEY" == 1 ]]; then
    printf 'foo=bar' >> "$dir/recipient.pub"
  fi
  exit 0
fi
echo "Unexpected mock command: $*" >&2
exit 1
MOCK
chmod +x "$root/bin/gh"
export GH_MOCK_ROOT="$root" GH_MOCK_BAD_KEY=0 GH_TOKEN=mock GITHUB_RUN_ID=123456
export RUNNER_TEMP="$root/runner" PATH="$root/bin:$PATH" GITHUB_OUTPUT="$root/output"
bash script/fetch-infra-recipient.sh prism-hub
expected="$(cat "$root/public.key")"
[[ "$(cat "$root/output")" == "key=$expected" ]] || {
  echo "The rerun did not receive its fresh recipient." >&2
  exit 1
}
rm -f "$root/dispatched"
: > "$root/output"
if GH_MOCK_BAD_KEY=1 bash script/fetch-infra-recipient.sh prism-hub; then
  echo "Malformed public key unexpectedly accepted." >&2
  exit 1
fi
[[ ! -s "$root/output" ]] || {
  echo "Malformed public key injected a GitHub output." >&2
  exit 1
}
echo "Recipient rerun isolation and output safety passed."
