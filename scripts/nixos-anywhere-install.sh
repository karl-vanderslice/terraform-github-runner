#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)
tmpdir=""

: "${ATTIC_ENV_FILE_CONTENT:?}"
: "${CLOUDFLARE_TUNNEL_CREDENTIALS_JSON:?}"
: "${CLOUDFLARE_TUNNEL_ID:?}"
: "${GENERATED_CONFIG_JSON:?}"
: "${GITHUB_RUNNER_TOKEN:?}"
: "${SSH_PRIVATE_KEY_PATH:?}"
: "${TARGET_HOST:?}"

render_generated_config() {
  local install_disk=$1

  jq --arg install_disk "$install_disk" '.disk = { device: $install_disk }' \
    <<<"$GENERATED_CONFIG_JSON" > "$repo_root/nixos/generated-config.json"
}

write_secret_tree() {
  local tmpdir=$1

  install -Dm750 /dev/null "$tmpdir/var/lib/terraform-github-runner/.keep"
  rm -f "$tmpdir/var/lib/terraform-github-runner/.keep"

  install -Dm600 /dev/null "$tmpdir/var/lib/terraform-github-runner/github-runner-token"
  printf '%s' "$GITHUB_RUNNER_TOKEN" > "$tmpdir/var/lib/terraform-github-runner/github-runner-token"

  install -Dm600 /dev/null "$tmpdir/var/lib/terraform-github-runner/atticd.env"
  printf '%s\n' "$ATTIC_ENV_FILE_CONTENT" > "$tmpdir/var/lib/terraform-github-runner/atticd.env"

  install -Dm600 /dev/null "$tmpdir/var/lib/terraform-github-runner/cloudflare-tunnel-attic.json"
  printf '%s\n' "$CLOUDFLARE_TUNNEL_CREDENTIALS_JSON" > "$tmpdir/var/lib/terraform-github-runner/cloudflare-tunnel-attic.json"
}

detect_install_disk() {
  if [[ -n "${INSTALL_DISK_DEVICE:-}" ]]; then
    printf '%s\n' "$INSTALL_DISK_DEVICE"
    return
  fi

  ssh \
    -F /dev/null \
    -i "$SSH_PRIVATE_KEY_PATH" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    root@"$TARGET_HOST" \
    "lsblk -dn -o NAME,TYPE | awk '\$2 == \"disk\" { print \"/dev/\" \$1; exit }'"
}

wait_for_ssh() {
  local attempts=0

  while (( attempts < 60 )); do
    if ssh \
      -F /dev/null \
      -i "$SSH_PRIVATE_KEY_PATH" \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      root@"$TARGET_HOST" \
      true >/dev/null 2>&1; then
      return
    fi

    attempts=$((attempts + 1))
    sleep 5
  done

  echo "Timed out waiting for SSH on $TARGET_HOST" >&2
  exit 1
}

verify_services() {
  ssh \
    -F /dev/null \
    -i "$SSH_PRIVATE_KEY_PATH" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    root@"$TARGET_HOST" \
    "systemctl is-active attic-bootstrap atticd github-runner-runner cloudflared-tunnel-${CLOUDFLARE_TUNNEL_ID} >/dev/null"
}

main() {
  local install_disk

  install_disk=$(detect_install_disk)
  render_generated_config "$install_disk"

  tmpdir=$(mktemp -d)
  trap 'if [[ -n "${tmpdir:-}" ]]; then rm -rf "$tmpdir"; fi' EXIT
  write_secret_tree "$tmpdir"

  export NIX_SSHOPTS="-F /dev/null"
  nixos-anywhere \
    -i "$SSH_PRIVATE_KEY_PATH" \
    --build-on remote \
    --extra-files "$tmpdir" \
    --flake "path:$repo_root#github-runner" \
    --ssh-option GlobalKnownHostsFile=/dev/null \
    --ssh-option IdentitiesOnly=yes \
    --ssh-option StrictHostKeyChecking=no \
    --ssh-option UserKnownHostsFile=/dev/null \
    --target-host "root@$TARGET_HOST"

  wait_for_ssh
  verify_services
}

main "$@"