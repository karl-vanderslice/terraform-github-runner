#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENT_HUB_DIR="/home/karl/Projects/src/github.com/karl-vanderslice/agent-hub"
TF_HOME_NETWORK_DIR="/home/karl/Projects/src/github.com/karl-vanderslice/terraform-home-network"

if [[ ! -f "${AGENT_HUB_DIR}/.env" ]]; then
  echo "Missing ${AGENT_HUB_DIR}/.env" >&2
  exit 1
fi

if [[ ! -f "${TF_HOME_NETWORK_DIR}/.env" ]]; then
  echo "Missing ${TF_HOME_NETWORK_DIR}/.env" >&2
  exit 1
fi

dotenv_get() {
  local env_file="$1"
  local key="$2"
  local line value

  line="$(grep -E "^(export[[:space:]]+)?${key}=" "${env_file}" | tail -n1 || true)"
  if [[ -z "${line}" ]]; then
    return 1
  fi

  value="${line#*=}"
  value="${value%$'\r'}"

  if [[ "${value}" == \"*\" && "${value}" == *\" ]]; then
    value="${value:1:-1}"
  elif [[ "${value}" == \'*\' && "${value}" == *\' ]]; then
    value="${value:1:-1}"
  fi

  printf '%s' "${value}"
}

BW_CLIENT_ID_FILE="$(dotenv_get "${AGENT_HUB_DIR}/.env" BW_CLIENT_ID || true)"
BW_CLIENTID_FILE="$(dotenv_get "${AGENT_HUB_DIR}/.env" BW_CLIENTID || true)"
BW_CLIENT_SECRET_FILE="$(dotenv_get "${AGENT_HUB_DIR}/.env" BW_CLIENT_SECRET || true)"
BW_CLIENTSECRET_FILE="$(dotenv_get "${AGENT_HUB_DIR}/.env" BW_CLIENTSECRET || true)"
EZRA_BITWARDEN_MASTER_PW="$(dotenv_get "${AGENT_HUB_DIR}/.env" EZRA_BITWARDEN_MASTER_PW || true)"

export BW_CLIENTID="${BW_CLIENT_ID_FILE:-${BW_CLIENTID_FILE:-}}"
export BW_CLIENTSECRET="${BW_CLIENT_SECRET_FILE:-${BW_CLIENTSECRET_FILE:-}}"
export EZRA_BITWARDEN_MASTER_PW
export NODE_NO_WARNINGS=1

if [[ -z "${BW_CLIENTID}" || -z "${BW_CLIENTSECRET}" ]]; then
  echo "BW client credentials are missing in ${AGENT_HUB_DIR}/.env" >&2
  exit 1
fi

if [[ -z "${EZRA_BITWARDEN_MASTER_PW:-}" ]]; then
  echo "EZRA_BITWARDEN_MASTER_PW is missing in ${AGENT_HUB_DIR}/.env" >&2
  exit 1
fi

bw_run_guarded() {
  local output err rc out_file err_file combined
  out_file="$(mktemp)"
  err_file="$(mktemp)"
  rc=0

  if ! timeout 30s "$@" >"${out_file}" 2>"${err_file}"; then
    rc=$?
    output="$(cat "${out_file}")"
    err="$(cat "${err_file}")"
    combined="${output}"$'\n'"${err}"
    rm -f "${out_file}" "${err_file}"
    if grep -qi "Input Master Password" <<<"${combined}"; then
      echo "Bitwarden requested interactive master password input. Refusing interactive flow." >&2
      exit 1
    fi
    if [[ -n "${err}" ]]; then
      echo "${err}" >&2
    fi
    if [[ -n "${output}" ]]; then
      echo "${output}" >&2
    fi
    return "${rc}"
  fi

  output="$(cat "${out_file}")"
  err="$(cat "${err_file}")"
  combined="${output}"$'\n'"${err}"
  rm -f "${out_file}" "${err_file}"

  if grep -qi "Input Master Password" <<<"${combined}"; then
    echo "Bitwarden requested interactive master password input. Refusing interactive flow." >&2
    exit 1
  fi

  if [[ -n "${err}" ]]; then
    echo "${err}" >&2
  fi

  printf '%s' "${output}"
}

bw_run_guarded bw login --apikey >/dev/null || true

status_json="$(bw_run_guarded bw status)"
if ! jq -e . >/dev/null <<<"${status_json}"; then
  echo "Unexpected non-JSON output from 'bw status'." >&2
  exit 1
fi
status_value="$(jq -r '.status // ""' <<<"${status_json}")"

if [[ "${status_value}" != "unlocked" ]]; then
  BW_SESSION="$(bw_run_guarded bw unlock --raw --passwordenv EZRA_BITWARDEN_MASTER_PW)"
  export BW_SESSION
fi

if [[ -z "${BW_SESSION:-}" ]]; then
  echo "BW_SESSION is empty after non-interactive unlock." >&2
  exit 1
fi

bw_run_guarded bw sync --session "${BW_SESSION}" >/dev/null

hetzner_item="$(bw_run_guarded bw get item "Hetzner" --session "${BW_SESSION}")"
vault_item="$(bw_run_guarded bw get item "HCP Vault Ezra" --session "${BW_SESSION}")"

TF_VAR_hcloud_token="$(jq -r '(.fields[]? | select(.name=="HCLOUD_TOKEN") | .value) // .login.password // empty' <<<"${hetzner_item}")"
TF_VAR_vault_bootstrap_token="$(jq -r '(.fields[]? | select(.name=="VAULT_TOKEN") | .value) // .login.password // empty' <<<"${vault_item}")"
TF_VAR_vault_auth_mount="$(jq -r '(.fields[]? | select(.name=="VAULT_AUTH_MOUNT") | .value) // empty' <<<"${vault_item}")"
TF_VAR_vault_admin_automation_role_id="$(jq -r '(.fields[]? | select(.name=="VAULT_ADMIN_AUTOMATION_ROLE_ID") | .value) // empty' <<<"${vault_item}")"
TF_VAR_vault_admin_automation_secret_id="$(jq -r '(.fields[]? | select(.name=="VAULT_ADMIN_AUTOMATION_SECRET_ID") | .value) // empty' <<<"${vault_item}")"

if [[ -z "${TF_VAR_hcloud_token}" ]]; then
  echo "HCLOUD_TOKEN missing from Bitwarden item Hetzner." >&2
  exit 1
fi

if [[ -z "${TF_VAR_vault_bootstrap_token}" && ( -z "${TF_VAR_vault_auth_mount}" || -z "${TF_VAR_vault_admin_automation_role_id}" || -z "${TF_VAR_vault_admin_automation_secret_id}" ) ]]; then
  echo "HCP Vault Ezra must contain either VAULT_TOKEN or the full AppRole tuple (VAULT_AUTH_MOUNT, VAULT_ADMIN_AUTOMATION_ROLE_ID, VAULT_ADMIN_AUTOMATION_SECRET_ID)." >&2
  exit 1
fi

TF_VAR_cloudflare_api_token="${TF_VAR_cloudflare_api_token:-$(dotenv_get "${TF_HOME_NETWORK_DIR}/.env" TF_VAR_cloudflare_api_token || true)}"
TF_VAR_cloudflare_zone_id="${TF_VAR_cloudflare_zone_id:-$(dotenv_get "${TF_HOME_NETWORK_DIR}/.env" TF_VAR_cloudflare_zone_id || true)}"

if [[ -z "${TF_VAR_cloudflare_api_token}" || -z "${TF_VAR_cloudflare_zone_id}" ]]; then
  echo "Cloudflare TF_VAR values missing from ${TF_HOME_NETWORK_DIR}/.env" >&2
  exit 1
fi

export TF_VAR_hcloud_token
export TF_VAR_vault_bootstrap_token
export TF_VAR_vault_auth_mount
export TF_VAR_vault_admin_automation_role_id
export TF_VAR_vault_admin_automation_secret_id
export TF_VAR_cloudflare_api_token
export TF_VAR_cloudflare_zone_id

cd "${ROOT_DIR}"

if [[ "${1:-}" == "--" ]]; then
  shift
fi

if [[ "$#" -eq 0 ]]; then
  echo "Loaded TF_VAR_* secrets non-interactively." >&2
  exit 0
fi

exec "$@"
