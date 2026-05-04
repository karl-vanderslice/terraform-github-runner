# Hetzner Runner Operator Guide

This repository provisions an opt-in self-hosted GitHub Actions runner on Hetzner Cloud ARM.

## Current Status

The active target is a repository-scoped runner for `karl-vanderslice/nix-config`
using a NixOS host image with Attic enabled at `attic.vslice.net`.

This deployment is intended for private Nix CI workloads that need:

- deterministic ARM64 execution on Hetzner
- authenticated access to the private Attic cache
- CI read-write cache token usage without exposing that token to developer
  machines

## Deployment Pattern

- Keep `runner_enabled = true` for the nix-config runner deployment.
- Start with `registration_mode = "github-provider"` for first deployment.
- Move to `registration_mode = "vault-token"` when Vault-backed bootstrap is ready.
- Use `runner_image_family = "nixos"` only when `hcloud_image` points at a
  custom NixOS image or snapshot built from this repository.

## Hetzner Baseline

- Server type: `cax21`
- Image: NixOS custom image or snapshot (`hcloud_image`)
- Region default: `nbg1`
- Persistent volume: default `100` GB, mounted for runner cache/work path
- Workspace volume: enabled and mounted at `/srv/workspaces` for Attic state
  (`/srv/workspaces/attic`) and durable CI data

## NixOS Attic Path

- Build the qcow artifact with `just build-nixos-image`.
- Publish that artifact through your Hetzner custom image or snapshot workflow,
  then set `hcloud_image` to the resulting image name or ID.
- Set `runner_image_family = "nixos"` and `attic_enabled = true`.
- Set `workspace_volume_size_gb > 0`; Attic stores its SQLite database and NAR
  objects under `/srv/workspaces/attic`.
- Pre-populate the Vault secret named by `attic_vault_secret_mount` and
  `attic_vault_secret_name` with the
  `attic_vault_secret_key = "ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64"` field as
  a base64-encoded RSA PKCS#1 PEM private key.
- On first boot, cloud-init writes `/etc/atticd.toml`, starts `atticd`, creates
  the cache, reuses pre-seeded Vault tokens when present, and otherwise mints
  `ATTIC_CACHE_PULL_TOKEN` and `ATTIC_CACHE_RW_TOKEN` before patching them plus
  `ATTIC_PUBLIC_KEY`, `ATTIC_API_ENDPOINT`, and
  `ATTIC_SUBSTITUTER_ENDPOINT` back into Vault.

Operator runbook: see `docs/guides/enable-attic-with-nixos-image.md`.

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

The current deployment appends the repository-specific label `nix-config`.

## CI Routing Example

```yaml
runs-on: [self-hosted, Linux, ARM64, hetzner, build, cache, nix-config]
```

## Attic rollout

The intended cache endpoint is `attic.vslice.net` on the same Hetzner host as
the runner. The NixOS image path is now the supported bootstrap route for that
service. Keep Ubuntu images on the slim runner-only path.
