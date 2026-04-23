# Hetzner Runner Operator Guide

This repository provisions an opt-in self-hosted GitHub Actions runner on Hetzner Cloud ARM.

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
