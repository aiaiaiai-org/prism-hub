#!/usr/bin/env bash
# © 2026 aiaiaiai · aiaiaiai.org
#
# Fetch only the public SSH encryption recipient for an infra-owned workload.
# GH_TOKEN must be the producer's scoped INFRA_DEPLOY_TOKEN.
set -Eeuo pipefail
umask 077

workload="${1:?Usage: fetch-infra-recipient.sh <workload>}"
[[ "$workload" =~ ^[a-z0-9][a-z0-9-]*$ ]] || { echo "::error::Invalid workload" >&2; exit 64; }
: "${GH_TOKEN:?INFRA_DEPLOY_TOKEN is required}"
: "${GITHUB_RUN_ID:?GitHub run ID is required}"
: "${GITHUB_OUTPUT:?GitHub output file is required}"
: "${RUNNER_TEMP:?GitHub runner temp is required}"
[[ "$GITHUB_RUN_ID" =~ ^[0-9]{1,20}$ ]] || exit 64

infra_repo="aiaiaiai-org/infra"
recipient_dir="$(mktemp -d "$RUNNER_TEMP/infra-recipient.XXXXXXXX")"
trap 'rm -rf "$recipient_dir"' EXIT

# Use the scoped token for all reads and writes: a repo-local GITHUB_TOKEN
# cannot read private infra. The checks distinguish common permission gaps.
if ! gh api --silent "repos/$infra_repo" >/dev/null 2>&1; then
  echo "::error::INFRA_DEPLOY_TOKEN cannot access private $infra_repo." >&2
  exit 1
fi
if ! gh api --silent "repos/$infra_repo/contents/.github/workflows/issue-workload-recipient.yml?ref=master" >/dev/null 2>&1; then
  echo "::error::Missing or inaccessible infra recipient workflow on master (Contents: read)." >&2
  exit 1
fi
if ! gh api --silent "repos/$infra_repo/actions/workflows/issue-workload-recipient.yml" >/dev/null 2>&1; then
  echo "::error::INFRA_DEPLOY_TOKEN requires Actions: read for recipient issuance." >&2
  exit 1
fi

# Rerunning a GitHub job preserves GITHUB_RUN_ID. Ignore prior issuance runs.
recipient_title="Recipient $workload / $GITHUB_RUN_ID"
list_recipient_runs() {
  gh api "repos/$infra_repo/actions/workflows/issue-workload-recipient.yml/runs?event=repository_dispatch&per_page=100"
}
seen_run_ids="$(list_recipient_runs | jq -c --arg title "$recipient_title" \
  '[.workflow_runs[] | select(.display_title == $title and .event == "repository_dispatch" and .head_branch == "master") | .id]')"

jq -n --arg workload "$workload" --arg request_id "$GITHUB_RUN_ID" \
  '{event_type:"issue-workload-recipient",client_payload:{workload:$workload,request_id:$request_id}}' \
  > "$recipient_dir/request.json"
if ! gh api --method POST "repos/$infra_repo/dispatches" --input "$recipient_dir/request.json"; then
  echo "::error::Recipient dispatch requires infra Contents: write." >&2
  exit 1
fi

recipient_run=""
for attempt in $(seq 1 180); do
  runs="$(list_recipient_runs)"
  recipient_run="$(jq -c --arg title "$recipient_title" --argjson seen "$seen_run_ids" \
    '[.workflow_runs[] | select(.display_title == $title and .event == "repository_dispatch" and .head_branch == "master" and (.id as $id | $seen | index($id) | not))][0] // empty' <<< "$runs")"
  if [[ -n "$recipient_run" && "$(jq -r '.status' <<< "$recipient_run")" == completed ]]; then
    if [[ "$(jq -r '.conclusion' <<< "$recipient_run")" != success ]]; then
      echo "::error::Infra recipient issuance failed: $(jq -r '.html_url' <<< "$recipient_run")" >&2
      exit 1
    fi
    break
  fi
  sleep 5
done
[[ -n "$recipient_run" && "$(jq -r '.status' <<< "$recipient_run")" == completed ]] || {
  echo "::error::Timed out waiting for correlated infra recipient." >&2
  exit 1
}

run_id="$(jq -r '.id' <<< "$recipient_run")"
[[ "$run_id" =~ ^[0-9]+$ ]] || exit 1
gh run download "$run_id" --repo "$infra_repo" \
  --name "recipient-$workload-$GITHUB_RUN_ID" --dir "$recipient_dir"

public_key="$recipient_dir/recipient.pub"
test -s "$public_key"
[[ "$(wc -l < "$public_key")" -eq 1 ]] || { echo "::error::Invalid public key line count." >&2; exit 1; }
ssh-keygen -lf "$public_key" >/dev/null
recipient="$(cat "$public_key")"
# A first line plus an unterminated second line may pass wc -l.
[[ "$recipient" != *[[ "$recipient" =~ ^ssh-(ed25519|rsa)\ [A-Za-z0-9+/=]+([[:space:]].*)?$ ]] || {
  echo "::error::Invalid public encryption recipient." >&2
  exit 1
}
printf 'key=%s\n' "$recipient" >> "$GITHUB_OUTPUT"
\n'* && "$recipient" != *[[ "$recipient" =~ ^ssh-(ed25519|rsa)\ [A-Za-z0-9+/=]+([[:space:]].*)?$ ]] || {
  echo "::error::Invalid public encryption recipient." >&2
  exit 1
}
printf 'key=%s\n' "$recipient" >> "$GITHUB_OUTPUT"
\r'* ]] || {
  echo "::error::Invalid multiline recipient for GitHub step output." >&2
  exit 1
}
[[ "$recipient" =~ ^ssh-(ed25519|rsa)\ [A-Za-z0-9+/=]+([[:space:]].*)?$ ]] || {
  echo "::error::Invalid public encryption recipient." >&2
  exit 1
}
printf 'key=%s\n' "$recipient" >> "$GITHUB_OUTPUT"
