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

RBW_SERVER_URL="$(dotenv_get "${AGENT_HUB_DIR}/.env" RBW_SERVER_URL || true)"
RBW_EMAIL="$(dotenv_get "${AGENT_HUB_DIR}/.env" RBW_EMAIL || true)"
RBW_CLIENT_ID="$(dotenv_get "${AGENT_HUB_DIR}/.env" RBW_CLIENT_ID || true)"
RBW_CLIENT_SECRET="$(dotenv_get "${AGENT_HUB_DIR}/.env" RBW_CLIENT_SECRET || true)"
RBW_PASSWORD="$(dotenv_get "${AGENT_HUB_DIR}/.env" RBW_PASSWORD || true)"

export RBW_SERVER_URL
export RBW_EMAIL
export RBW_CLIENT_ID
export RBW_CLIENT_SECRET
export RBW_PASSWORD
export NODE_NO_WARNINGS=1

if [[ -z "${RBW_EMAIL}" || -z "${RBW_CLIENT_ID}" || -z "${RBW_CLIENT_SECRET}" ]]; then
  echo "RBW credentials are missing in ${AGENT_HUB_DIR}/.env" >&2
  exit 1
fi

if [[ -z "${RBW_PASSWORD:-}" ]]; then
  echo "RBW_PASSWORD is missing in ${AGENT_HUB_DIR}/.env" >&2
  exit 1
fi

rbw_run_guarded() {
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
    if grep -qi "password" <<<"${combined}"; then
      echo "rbw requested interactive password input. Refusing interactive flow." >&2
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

  if grep -qi "password" <<<"${combined}"; then
    echo "rbw requested interactive password input. Refusing interactive flow." >&2
    exit 1
  fi

  if [[ -n "${err}" ]]; then
    echo "${err}" >&2
  fi

  printf '%s' "${output}"
}

rbw_run_guarded rbw unlock >/dev/null
rbw_run_guarded rbw sync >/dev/null

rbw_get_field() {
  local item_name="$1"
  local field_name="$2"
  local value
  value="$(rbw_run_guarded rbw get --field "${field_name}" "${item_name}" 2>/dev/null || true)"
  if [[ -z "${value}" ]]; then
    value="$(rbw_run_guarded rbw get "${item_name}" 2>/dev/null || true)"
  fi
  printf '%s' "${value}"
}

TF_VAR_hcloud_token="$(rbw_get_field "Hetzner" "HCLOUD_TOKEN")"
TF_VAR_vault_bootstrap_token="$(rbw_get_field "HCP Vault Ezra" "VAULT_TOKEN")"
TF_VAR_vault_auth_mount="$(rbw_get_field "HCP Vault Ezra" "VAULT_AUTH_MOUNT")"
TF_VAR_vault_admin_automation_role_id="$(rbw_get_field "HCP Vault Ezra" "VAULT_ADMIN_AUTOMATION_ROLE_ID")"
TF_VAR_vault_admin_automation_secret_id="$(rbw_get_field "HCP Vault Ezra" "VAULT_ADMIN_AUTOMATION_SECRET_ID")"

if [[ -z "${TF_VAR_hcloud_token}" ]]; then
  echo "HCLOUD_TOKEN missing from rbw item Hetzner." >&2
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
