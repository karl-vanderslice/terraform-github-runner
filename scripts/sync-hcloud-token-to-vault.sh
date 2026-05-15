#!/usr/bin/env bash
set -euo pipefail

cd /home/karl/Projects/src/github.com/karl-vanderslice/agent-hub
set +u
source .env
set -u

export RBW_SERVER_URL="${RBW_SERVER_URL:-}"
export RBW_EMAIL="${RBW_EMAIL:-}"
export RBW_CLIENT_ID="${RBW_CLIENT_ID:-}"
export RBW_CLIENT_SECRET="${RBW_CLIENT_SECRET:-}"
export RBW_PASSWORD="${RBW_PASSWORD:-}"

if [[ -z "${RBW_EMAIL}" || -z "${RBW_CLIENT_ID}" || -z "${RBW_CLIENT_SECRET}" || -z "${RBW_PASSWORD}" ]]; then
  echo "RBW_* credentials are required in agent-hub .env" >&2
  exit 1
fi

rbw unlock >/dev/null
rbw sync >/dev/null

hcloud_token="$(rbw get --field HCLOUD_TOKEN "Hetzner" 2>/dev/null || true)"
if [[ -z "$hcloud_token" || "$hcloud_token" == "null" ]]; then
  hcloud_token="$(rbw get "Hetzner" 2>/dev/null || true)"
fi

if [[ -z "$hcloud_token" ]]; then
  echo "HCLOUD_TOKEN not found in rbw item Hetzner" >&2
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
