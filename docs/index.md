# Hetzner Runner Operator Guide

This repository provisions an opt-in self-hosted GitHub Actions runner on Hetzner Cloud ARM.

## Current Status

As of the CI/CD consolidation to `terraform-cloudflare-docs-sites`, the self-hosted runner is **disabled by default** and not required for standard workflows. All documentation publishing and validation runs on GitHub-hosted `ubuntu-latest` runners via the centralized `deploy-hub.yml` workflow.

**Re-enable this runner only if:**
- Testing ARM-specific builds or compatibility
- Running canary deployments on Hetzner infrastructure
- You explicitly set `CI_CANARY_HETZNER = '1'` in a workflow to route jobs to the self-hosted runner

## Deployment Pattern

- Keep `runner_enabled = false` until `just lint`, `just test`, and `just plan` are clean.
- Start with `registration_mode = "github-provider"` for first deployment.
- Move to `registration_mode = "vault-token"` when Vault-backed bootstrap is ready.

## Hetzner Baseline

- Server type: `cax21`
- Image: `ubuntu-24.04`
- Region default: `nbg1`
- Persistent volume: default `100` GB, mounted for runner cache/work path

## Security Baseline

- Leave `admin_cidrs = []` unless SSH is required.
- If enabling SSH CIDRs, provide `ssh_authorized_keys`.
- Use short-lived Vault bootstrap tokens for cloud-init token minting.

## Runner Labels

Default labels include:

- `hetzner`
- `arm64`
- `build`
- `cache`

Additional labels can be appended with `runner_labels`.

## CI Routing Example

```yaml
runs-on: ${{ vars.CI_CANARY_HETZNER == '1' && fromJSON('["self-hosted","Linux","ARM64","hetzner","build"]') || 'ubuntu-latest' }}
```
