set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

default:
  @just --list

enter-nix *args:
  @if [[ -n "${IN_NIX_SHELL:-}" ]]; then \
    just --justfile "{{justfile()}}" {{args}}; \
  else \
    nix develop --command just --justfile "{{justfile()}}" {{args}}; \
  fi

format:
  @just enter-nix _format

_format:
  alejandra .
  terraform fmt -recursive

lint:
  @just enter-nix _lint

_lint:
  markdownlint-cli2 README.md docs/**/*.md
  yamllint .
  checkov -d . --config-file .checkov.yaml
  terraform init -backend=false
  terraform validate

init:
  @just enter-nix _init

_init:
  terraform init -backend-config=backend.hcl

plan:
  @just enter-nix _plan

_plan:
  terraform init -backend-config=backend.hcl
  terraform plan

apply:
  @just enter-nix _apply

_apply:
  terraform init -backend-config=backend.hcl
  terraform apply

test:
  @just enter-nix _test

_test:
  terraform init -backend=false
  terraform validate

pre-commit:
  @just enter-nix _pre-commit

_pre-commit:
  pre-commit run --all-files --show-diff-on-failure

docs:
  @just enter-nix _docs

_docs:
  zensical build --clean

terraform-docs:
  @just enter-nix _terraform-docs

_terraform-docs:
  terraform-docs markdown table --output-file README.md --output-mode inject .

hcloud-token-sync-vault:
  @just enter-nix _hcloud-token-sync-vault

_hcloud-token-sync-vault:
  scripts/sync-hcloud-token-to-vault.sh
