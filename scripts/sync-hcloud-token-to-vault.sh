#!/usr/bin/env bash
set -euo pipefail

cd /home/karl/Projects/src/github.com/karl-vanderslice/agent-hub
set +u
source .env
set -u

export BW_CLIENTID="${BW_CLIENT_ID:-${BW_CLIENTID:-}}"
export BW_CLIENTSECRET="${BW_CLIENT_SECRET:-${BW_CLIENTSECRET:-}}"

bw login --apikey >/dev/null 2>&1 || true
if [[ -z "${BW_SESSION:-}" ]]; then
  if [[ -z "${EZRA_BITWARDEN_MASTER_PW:-}" ]]; then
    echo "EZRA_BITWARDEN_MASTER_PW is not set and BW_SESSION is missing; cannot unlock Bitwarden non-interactively." >&2
    exit 1
  fi
  BW_SESSION="$(bw unlock --raw --passwordenv EZRA_BITWARDEN_MASTER_PW)"
  export BW_SESSION
fi

bw sync --session "${BW_SESSION}" >/dev/null

item="$(bw list items --search "Hetzner" --session "$BW_SESSION" | jq -r 'first(.[])')"
if [[ -z "$item" || "$item" == "null" ]]; then
  echo "No Bitwarden item found matching Hetzner" >&2
  exit 1
fi

hcloud_token="$(jq -r '.fields[]? | select(.name=="HCLOUD_TOKEN") | .value' <<<"$item")"
if [[ -z "$hcloud_token" || "$hcloud_token" == "null" ]]; then
  hcloud_token="$(jq -r '.login.password // empty' <<<"$item")"
fi

if [[ -z "$hcloud_token" ]]; then
  echo "HCLOUD_TOKEN not found in Bitwarden item fields or login.password" >&2
  exit 1
fi

payload="$(jq -n --arg token "$hcloud_token" '{data:{HCLOUD_TOKEN:$token}}')"

curl -fsS -X POST \
  -H "X-Vault-Token: ${VAULT_TOKEN}" \
  -H "X-Vault-Namespace: ${VAULT_NAMESPACE:-}" \
  -H "Content-Type: application/json" \
  -d "$payload" \
  "${VAULT_ADDR}/v1/mcp-kv/data/hetzner/terraform-runner" >/dev/null

echo "Synced HCLOUD_TOKEN to Vault path mcp-kv/data/hetzner/terraform-runner"
