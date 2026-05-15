#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)
org_root="/home/karl/Projects/src/github.com/karl-vanderslice"
agent_hub_root="$org_root/agent-hub"
home_network_root="$org_root/terraform-home-network"

if [[ $# -eq 0 ]]; then
  echo "usage: $0 -- <command> [args...]" >&2
  exit 64
fi

if [[ "$1" == "--" ]]; then
  shift
fi

if [[ $# -eq 0 ]]; then
  echo "usage: $0 -- <command> [args...]" >&2
  exit 64
fi

read_env_value() {
  local key=$1
  local file=$2
  [[ -f "$file" ]] || return 1
  rg -N "^(export[[:space:]]+)?${key}=" "$file" | tail -n 1 | sed 's/^[^=]*=//'
}

export_if_unset() {
  local key=$1
  local value=$2
  if [[ -z "${!key:-}" && -n "$value" ]]; then
    export "$key=$value"
  fi
}

resolve_cloudflare_zone_id() {
  local token=$1
  local domain=$2

  curl -fsSL \
    -H "Authorization: Bearer $token" \
    "https://api.cloudflare.com/client/v4/zones?per_page=100" | \
    jq -r --arg domain "$domain" '
      .result
      | map(select(.name as $zone | $domain | endswith($zone)))
      | sort_by(.name | length)
      | reverse
      | .[0].id // empty
    '
}

resolve_hcloud_existing_key_names() {
  local token=$1
  local public_key=$2

  HCLOUD_TOKEN="$token" hcloud ssh-key list -o json | \
    jq -c --arg key "$public_key" '[.[] | select(.public_key == $key) | .name]'
}

home_network_env="$home_network_root/.env"
agent_hub_env="$agent_hub_root/.env"

export_if_unset TF_VAR_cloudflare_api_token "$(read_env_value TF_VAR_cloudflare_api_token "$home_network_env" 2>/dev/null || read_env_value CLOUDFLARE_API_TOKEN "$agent_hub_env" 2>/dev/null || true)"
export_if_unset TF_VAR_cloudflare_account_id "$(read_env_value TF_VAR_cloudflare_account_id "$home_network_env" 2>/dev/null || read_env_value CLOUDFLARE_ACCOUNT_ID "$agent_hub_env" 2>/dev/null || true)"
export_if_unset TF_VAR_cloudflare_zone_id "$(read_env_value TF_VAR_cloudflare_zone_id "$home_network_env" 2>/dev/null || read_env_value CLOUDFLARE_ZONE_ID "$agent_hub_env" 2>/dev/null || true)"

if [[ -z "${TF_VAR_hcloud_token:-}" ]]; then
  export TF_VAR_hcloud_token="$(rbw get -f HCLOUD_TOKEN Hetzner | tr -d '\r\n')"
fi

export HCLOUD_TOKEN="$TF_VAR_hcloud_token"

if [[ -z "${TF_VAR_github_runner_token:-}" ]]; then
  export TF_VAR_github_runner_token="$(gh auth token | tr -d '\r\n')"
fi

if [[ -z "${TF_VAR_ssh_private_key_path:-}" ]]; then
  export TF_VAR_ssh_private_key_path="$HOME/.ssh/ezra-device-access"
fi

if [[ -z "${TF_VAR_ssh_authorized_keys:-}" ]]; then
  public_key=$(ssh-keygen -y -f "$TF_VAR_ssh_private_key_path")
  export TF_VAR_ssh_authorized_keys="$(jq -cn --arg key "$public_key" '[ $key ]')"
fi

if [[ -z "${TF_VAR_hcloud_existing_ssh_key_names:-}" ]]; then
  public_key=$(ssh-keygen -y -f "$TF_VAR_ssh_private_key_path")
  export TF_VAR_hcloud_existing_ssh_key_names="$(resolve_hcloud_existing_key_names "$TF_VAR_hcloud_token" "$public_key")"
fi

resolved_zone_id="$(resolve_cloudflare_zone_id "$TF_VAR_cloudflare_api_token" "${TF_VAR_attic_domain:-attic.vslice.net}")"
if [[ -n "$resolved_zone_id" ]]; then
  export TF_VAR_cloudflare_zone_id="$resolved_zone_id"
fi

exec "$@"
