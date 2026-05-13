# Runner Lifecycle And State Wiring

Date: 2026-05-08
Status: Accepted

## Context

The Hetzner runner stack had four end-to-end gaps that prevented reliable
operation:

- Terraform backend configuration existed in `backend.hcl`, but the root module
  had no backend block, so state operations defaulted to local state.
- Durable storage for `/srv/workspaces` and `/var/cache/github-actions` was only
  established through one-shot cloud-init bind mounts, which would not survive a
  reboot.
- Runner services were installed once with `svc.sh`, which created long-lived
  registrations instead of self-re-registering ephemeral runners.
- The non-interactive secret helper sourced full `.env` files directly, which is
  fragile when those files contain values that are not valid shell syntax.

## Decision

Treat the Hetzner host as a persistent control plane with durable volumes and
systemd-managed runtime wiring, while the GitHub runner registrations can be
ephemeral.

- Activate the remote Terraform backend in the root module.
- Materialize bind mounts for `/srv/workspaces` and `/var/cache/github-actions`
  as systemd mount units so the Hetzner volumes remain the source of truth
  across reboots.
- Run GitHub runner processes under systemd instead of `svc.sh` so the host can
  re-register runners after each job when `runner_ephemeral = true`.
- Require `registration_mode = "vault-token"` for ephemeral runner mode because
  that is the only supported path that can mint new GitHub registration tokens
  after the initial Terraform apply.
- Parse only the required keys from `.env` files in the Terraform secret helper
  instead of sourcing the full files.

## Acceptance Gates

- `terraform init -backend-config=backend.hcl` uses the declared remote backend
  instead of silently defaulting to local state.
- Rebooting the host preserves the workspace and GitHub cache bind mounts.
- When `runner_ephemeral = true`, the runner service mints a new token through
  Vault, registers one runner, processes one job, exits, and re-registers on
  the next systemd restart.
- Attic state continues to live under `/srv/workspaces/attic`.
- The operator path for `just plan-guarded`, `just apply-auto`, and
  `just destroy-auto` does not rely on shell-sourcing arbitrary `.env` files.

## Rollback

- Set `runner_ephemeral = false` to return to long-lived runner processes on the
  same host.
- Disable the generated systemd runner units and re-run bootstrap if the host
  must return to the previous `svc.sh`-managed shape.
- Revert the backend block only if state must intentionally move back to local
  development mode.
