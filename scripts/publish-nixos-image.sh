#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TFVARS_FILE="${TFVARS_FILE:-${ROOT_DIR}/terraform.tfvars}"
PUBLISH_WORKDIR="${PUBLISH_WORKDIR:-/root/terraform-github-runner}"
SEED_FLAKE_PATH="${SEED_FLAKE_PATH:-.#seed-publisher}"
KEEP_PUBLISH_SERVER="${KEEP_PUBLISH_SERVER:-false}"
PROTECT_SNAPSHOT="${PROTECT_SNAPSHOT:-true}"
PUBLISH_SSH_USER="${PUBLISH_SSH_USER:-root}"
DEFAULT_SSH_KEY_PATH="${HOME}/.ssh/ezra-device-access"
PUBLISH_SSH_PRIVATE_KEY="${PUBLISH_SSH_PRIVATE_KEY:-${DEFAULT_SSH_KEY_PATH}}"

created_server_id=""
created_server_ip=""
published_snapshot_id=""

require_command() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "missing required command: ${command_name}" >&2
    exit 1
  fi
}

tfvars_get() {
  local key="$1"
  local raw_value

  raw_value="$(awk -F= -v key="${key}" '
    $1 ~ "^[[:space:]]*" key "[[:space:]]*$" {
      print $2
    }
  ' "${TFVARS_FILE}" | tail -n1)"

  raw_value="${raw_value%%#*}"
  raw_value="$(printf '%s' "${raw_value}" | xargs)"
  raw_value="${raw_value#\"}"
  raw_value="${raw_value%\"}"

  printf '%s' "${raw_value}"
}

git_revision() {
  local revision dirty_suffix=""

  revision="$(git -C "${ROOT_DIR}" rev-parse --short HEAD 2>/dev/null || echo unknown)"

  if ! git -C "${ROOT_DIR}" diff --quiet --ignore-submodules -- || \
    ! git -C "${ROOT_DIR}" diff --cached --quiet --ignore-submodules --; then
    dirty_suffix="-dirty"
  fi

  printf '%s%s' "${revision}" "${dirty_suffix}"
}

json_field() {
  local json_input="$1"
  local jq_filter="$2"

  jq -r "${jq_filter}" <<<"${json_input}"
}

ssh_options=()

build_ssh_options() {
  ssh_options=(
    -o BatchMode=yes
    -o ConnectTimeout=10
    -F /dev/null
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
  )

  if [[ -r "${PUBLISH_SSH_PRIVATE_KEY}" ]]; then
    ssh_options+=( -i "${PUBLISH_SSH_PRIVATE_KEY}" )
  fi
}

remote_shell() {
  ssh "${ssh_options[@]}" "${PUBLISH_SSH_USER}@${created_server_ip}" "$@"
}

remote_shell_stdin() {
  ssh "${ssh_options[@]}" "${PUBLISH_SSH_USER}@${created_server_ip}" 'bash -seuo pipefail'
}

cleanup() {
  local exit_code="$1"

  if [[ -n "${created_server_id}" && "${KEEP_PUBLISH_SERVER}" != "true" && -n "${published_snapshot_id}" ]]; then
    HCLOUD_TOKEN="${TF_VAR_hcloud_token}" hcloud server delete "${created_server_id}" >/dev/null || true
  fi

  if [[ "${exit_code}" -ne 0 && -n "${created_server_id}" ]]; then
    echo "publish server retained for debugging: id=${created_server_id} ip=${created_server_ip}" >&2
  fi
}

trap 'cleanup "$?"' EXIT

wait_for_server_status() {
  local expected_status="$1"
  local current_status=""
  local attempt=0

  while (( attempt < 120 )); do
    current_status="$(HCLOUD_TOKEN="${TF_VAR_hcloud_token}" hcloud server describe "${created_server_id}" -o json | jq -r '.status')"

    if [[ "${current_status}" == "${expected_status}" ]]; then
      return 0
    fi

    attempt=$((attempt + 1))
    sleep 2
  done

  echo "server ${created_server_id} did not reach status ${expected_status}; current status=${current_status}" >&2
  exit 1
}

wait_for_ssh() {
  local attempt=0

  while (( attempt < 90 )); do
    if remote_shell true >/dev/null 2>&1; then
      return 0
    fi

    attempt=$((attempt + 1))
    sleep 5
  done

  echo "ssh did not become ready on ${created_server_ip}" >&2
  exit 1
}

copy_workspace() {
  tar \
    --exclude='.git' \
    --exclude='.direnv' \
    --exclude='.terraform' \
    --exclude='result' \
    --exclude='terraform.tfstate' \
    --exclude='terraform.tfstate.*' \
    -C "${ROOT_DIR}" \
    -czf - . | remote_shell "rm -rf '${PUBLISH_WORKDIR}' && mkdir -p '${PUBLISH_WORKDIR}' && tar xzf - -C '${PUBLISH_WORKDIR}'"
}

rebuild_seed_host() {
  remote_shell_stdin <<EOF
cd '${PUBLISH_WORKDIR}'
export NIX_CONFIG='experimental-features = nix-command flakes'
nixos-rebuild switch --flake '${SEED_FLAKE_PATH}'
EOF
}

sysprep_seed_host() {
  remote_shell_stdin <<'EOF'
journalctl --rotate >/dev/null 2>&1 || true
journalctl --vacuum-time=1s >/dev/null 2>&1 || true
rm -f /etc/ssh/ssh_host_*
rm -f /var/lib/systemd/random-seed
rm -f /run/hetzner-user-data
rm -f /usr/local/bin/github-runner-bootstrap
rm -rf /root/.cache /root/.npm /root/.local/state
rm -rf /tmp/* /var/tmp/*
rm -rf /var/lib/caddy/.config/* /var/lib/caddy/.local/share/*
rm -rf /var/lib/github-runner-bootstrap/*
rm -rf /root/terraform-github-runner
find /var/log -mindepth 1 -delete || true
truncate -s 0 /etc/machine-id
ln -sf /etc/machine-id /var/lib/dbus/machine-id
sync
EOF
}

poweroff_seed_host() {
  HCLOUD_TOKEN="${TF_VAR_hcloud_token}" hcloud server poweroff "${created_server_id}" >/dev/null
  wait_for_server_status off
}

create_snapshot() {
  local snapshot_description="$1"
  local create_output

  create_output="$(HCLOUD_TOKEN="${TF_VAR_hcloud_token}" hcloud server create-image --type snapshot --description "${snapshot_description}" --label role=github-runner --label managed-by=terraform-github-runner "${created_server_id}" -o json)"
  published_snapshot_id="$(jq -r '(.image.id // (.action.resources[]? | select(.type == "image") | .id) // empty)' <<<"${create_output}")"

  if [[ -z "${published_snapshot_id}" ]]; then
    echo "failed to resolve published snapshot id from Hetzner response" >&2
    echo "${create_output}" >&2
    exit 1
  fi

  if [[ "${PROTECT_SNAPSHOT}" == "true" ]]; then
    HCLOUD_TOKEN="${TF_VAR_hcloud_token}" hcloud image enable-protection "${published_snapshot_id}" >/dev/null
  fi
}

main() {
  local current_image_id location server_type snapshot_name commit_ref timestamp snapshot_description
  local create_output ssh_key_name="${HCLOUD_PUBLISH_SSH_KEY_NAME:-}"

  require_command git
  require_command hcloud
  require_command jq
  require_command ssh
  require_command tar

  if [[ ! -f "${TFVARS_FILE}" ]]; then
    echo "missing terraform vars file: ${TFVARS_FILE}" >&2
    exit 1
  fi

  if [[ -z "${TF_VAR_hcloud_token:-}" ]]; then
    echo "TF_VAR_hcloud_token must be exported before publishing the NixOS image" >&2
    exit 1
  fi

  current_image_id="${SOURCE_IMAGE:-$(tfvars_get hcloud_image)}"
  location="${HCLOUD_LOCATION:-$(tfvars_get hcloud_location)}"
  server_type="${HCLOUD_SERVER_TYPE:-$(tfvars_get hcloud_server_type)}"
  snapshot_name="${SNAPSHOT_NAME:-nixos-runner-hetzner-image}"
  commit_ref="$(git_revision)"
  timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  snapshot_description="${SNAPSHOT_DESCRIPTION:-terraform-github-runner ${commit_ref} ${timestamp}}"

  if [[ -z "${current_image_id}" || -z "${location}" || -z "${server_type}" ]]; then
    echo "failed to derive publish inputs from ${TFVARS_FILE}" >&2
    exit 1
  fi

  build_ssh_options

  if [[ -n "${ssh_key_name}" ]]; then
    create_output="$(HCLOUD_TOKEN="${TF_VAR_hcloud_token}" hcloud server create --name "${snapshot_name}" --type "${server_type}" --image "${current_image_id}" --location "${location}" --ssh-key "${ssh_key_name}" -o json)"
  else
    create_output="$(HCLOUD_TOKEN="${TF_VAR_hcloud_token}" hcloud server create --name "${snapshot_name}" --type "${server_type}" --image "${current_image_id}" --location "${location}" -o json)"
  fi

  created_server_id="$(json_field "${create_output}" '.server.id // empty')"
  created_server_ip="$(json_field "${create_output}" '.server.public_net.ipv4.ip // empty')"

  if [[ -z "${created_server_id}" || -z "${created_server_ip}" ]]; then
    echo "failed to create temporary publish server" >&2
    echo "${create_output}" >&2
    exit 1
  fi

  wait_for_ssh
  copy_workspace
  rebuild_seed_host
  sysprep_seed_host
  poweroff_seed_host
  create_snapshot "${snapshot_description}"

  printf 'published_snapshot_id=%s\n' "${published_snapshot_id}"
  printf 'published_snapshot_name=%s\n' "${snapshot_name}"
  printf 'published_snapshot_description=%s\n' "${snapshot_description}"
}

main "$@"
