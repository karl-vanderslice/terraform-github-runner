#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)
remote_data_dir="$repo_root/.terraform-remote"
local_run_root="$repo_root/.terraform-local-run"
workdir="$local_run_root/work"

if [[ $# -eq 0 ]]; then
  echo "usage: $0 <terraform-subcommand> [args...]" >&2
  exit 64
fi

pull_remote_state() {
  TF_DATA_DIR="$remote_data_dir" terraform -chdir="$repo_root" init -backend-config=backend.hcl -reconfigure >/dev/null
  TF_DATA_DIR="$remote_data_dir" terraform -chdir="$repo_root" state pull > "$workdir/terraform.tfstate"
}

prepare_local_workspace() {
  rm -rf "$workdir"
  mkdir -p "$workdir"

  rsync -a \
    --delete \
    --exclude .git \
    --exclude .direnv \
    --exclude .terraform \
    --exclude .terraform-local-run \
    --exclude .terraform-remote \
    "$repo_root/" "$workdir/"

  perl -0pi -e 's/\n\s*backend\s+"remote"\s*\{\s*\}\n/\n/s' "$workdir/versions.tf"

  pull_remote_state
  terraform -chdir="$workdir" init -backend=false -reconfigure >/dev/null
}

push_state_if_needed() {
  case "$1" in
    apply|destroy|import|state)
      TF_DATA_DIR="$remote_data_dir" terraform -chdir="$repo_root" init -backend-config=backend.hcl -reconfigure >/dev/null
      TF_DATA_DIR="$remote_data_dir" terraform -chdir="$repo_root" state push "$workdir/terraform.tfstate"
      ;;
  esac
}

main() {
  local subcommand=$1
  shift

  prepare_local_workspace
  terraform -chdir="$workdir" "$subcommand" "$@"
  push_state_if_needed "$subcommand"
}

main "$@"