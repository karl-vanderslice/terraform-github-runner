set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

default:
  @just --list

enter-nix *args:
  @if [[ -n "${IN_NIX_SHELL:-}" ]]; then \
    just --justfile "{{justfile()}}" {{args}}; \
  else \
    direnv exec . just --justfile "{{justfile()}}" {{args}}; \
  fi

format:
  @just enter-nix _format

_format:
  nix fmt

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
  chmod +x scripts/with-runner-secrets.sh scripts/terraform-local.sh scripts/nixos-anywhere-install.sh
  scripts/with-runner-secrets.sh -- scripts/terraform-local.sh plan

apply:
  @just enter-nix _apply

_apply:
  chmod +x scripts/with-runner-secrets.sh scripts/terraform-local.sh scripts/nixos-anywhere-install.sh
  scripts/with-runner-secrets.sh -- scripts/terraform-local.sh apply

apply-auto:
  @just enter-nix _apply-auto

_apply-auto:
  chmod +x scripts/with-runner-secrets.sh scripts/terraform-local.sh scripts/nixos-anywhere-install.sh
  scripts/with-runner-secrets.sh -- scripts/terraform-local.sh apply -auto-approve

plan-guarded:
  @just enter-nix _plan-guarded

_plan-guarded:
  chmod +x scripts/with-runner-secrets.sh scripts/terraform-local.sh scripts/nixos-anywhere-install.sh
  scripts/with-runner-secrets.sh -- scripts/terraform-local.sh plan

destroy-auto:
  @just enter-nix _destroy-auto

_destroy-auto:
  chmod +x scripts/with-runner-secrets.sh scripts/terraform-local.sh scripts/nixos-anywhere-install.sh
  scripts/with-runner-secrets.sh -- scripts/terraform-local.sh destroy -auto-approve

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
