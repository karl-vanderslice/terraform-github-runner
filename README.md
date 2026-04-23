# terraform-github-runner

Terraform for a Hetzner-hosted self-hosted GitHub Actions runner, currently scoped to Hetzner only.

## Scope

- Provider: Hetzner Cloud (`hcloud`)
- Architecture: ARM64 (`cax21` default)
- Persistence: attached Hetzner volume for runner work/cache
- Registration: GitHub provider token mode or Vault-backed token minting

## What This Provisions

- `hcloud_server` for the runner host
- `hcloud_volume` for persistent cache/work data
- `hcloud_volume_attachment` for the cache mount
- `hcloud_firewall` with optional SSH ingress and unrestricted egress
- optional `vault_policy` for runner bootstrap token read access

## Quick Start

```bash
cp terraform.tfvars.example terraform.tfvars
cp backend.hcl.example backend.hcl

just format
just lint
just init
just plan
```

Set core values in `terraform.tfvars`:

```hcl
runner_enabled       = true
registration_scope   = "repository"
registration_mode    = "github-provider"
github_owner         = "your-org-or-user"
github_repository    = "agent-hub"
github_repositories  = ["nix-config", "retro-collection-tool"]

hcloud_location      = "nbg1"
hcloud_server_type   = "cax21"
hcloud_image         = "ubuntu-24.04"
hcloud_volume_size_gb = 100
```

Apply:

```bash
just apply
```

## Configuration Model

1. `runner_enabled` is a safety switch. Keep it `false` until plan output is reviewed.
2. `registration_scope` controls org-level vs repo-level registration.
3. `registration_mode` controls how registration tokens are sourced:
   - `github-provider`: Terraform fetches short-lived token(s) at apply.
   - `vault-token`: cloud-init reads a GitHub API token from Vault, then mints short-lived runner registration tokens on boot.

## Operational Guidance

- Use repository scope first for blast-radius control.
- Keep `admin_cidrs` empty unless direct SSH maintenance is required.
- If `admin_cidrs` is set, at least one SSH public key must be provided in `ssh_authorized_keys`.
- Keep `vault_bootstrap_token` short-lived when using `vault-token` mode.
- Runner bootstrap `user_data` is lifecycle-ignored to avoid churn from ephemeral token changes.

## Vault + Bitwarden Flow (Hetzner API Token)

1. Store the Hetzner token in Bitwarden field `HCLOUD_TOKEN`.
2. Sync to Vault:

```bash
just hcloud-token-sync-vault
```

1. Export for Terraform execution:

```bash
export TF_VAR_hcloud_token="..."
```

## Validation

```bash
just format
just lint
just test
just pre-commit
```

## Future Provider Expansion

This repository is intentionally Hetzner-only for the initial commit. Additional cloud providers can be added later through explicit module boundaries and separate environment overlays.
