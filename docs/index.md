# Hetzner Runner Operator Guide

This repository provisions an opt-in self-hosted GitHub Actions runner on Hetzner Cloud ARM.

## Current Status

The active target is a repository-scoped runner for `karl-vanderslice/agent-hub`
using a NixOS host image with Attic enabled at `attic.vslice.net`.

This deployment is intended for private Nix CI workloads that need:

- deterministic ARM64 execution on Hetzner
- authenticated access to the private Attic cache
- CI read-write cache token usage without exposing that token to developer
  machines
- self-re-registering ephemeral runner services on a persistent host
- Cloudflare-proxied DNS and a single Caddy ingress in front of the cache endpoint
- host-level intrusion signal and blocking with containerized CrowdSec

## Deployment Pattern

- Keep `runner_enabled = true` for the agent-hub runner deployment.
- Keep the default random pet-name runner naming unless a hard requirement
  exists for an explicit name. This repository treats runner hosts as cattle
  for replacement and drift control while using pet-style names for operator
  ergonomics.
- Keep `registration_mode = "vault-token"` for the Attic-enabled path so the host
  can mint fresh runner registration tokens on each restart.
- Keep `runner_ephemeral = true` when the host should process one GitHub job per
  runner registration and immediately re-register.
- Use `runner_image_family = "nixos"` only when `hcloud_image` points at a
  custom NixOS image built from this repository.
- The NixOS image path uses a baked metadata bootstrap service instead of
  relying on cloud-init support in Hetzner custom images.
- Keep `attic_tls_mode = "letsencrypt"` for the default origin certificate path
  behind Cloudflare Full (strict). Switch to `cloudflare-origin-ca` only when
  public ACME issuance at the origin is undesirable.

## Hetzner Baseline

- Server type: `cax21`
- Image: NixOS custom image or snapshot (`hcloud_image`)
- Region default: `nbg1`
- Persistent volume: default `100` GB, mounted for runner cache/work path
- Workspace volume: enabled and mounted at `/srv/workspaces` for Attic state
  (`/srv/workspaces/attic`) and durable CI data
- Systemd mount units keep `/srv/workspaces` and `/var/cache/github-actions`
  backed by Hetzner volumes across host reboots

## NixOS Attic Path

- Publish the image with `just publish-nixos-image`.
- The publish workflow validates the qcow artifact, rebuilds a temporary
  NixOS seed VM from the current repo state, syspreps it, and snapshots it in
  Hetzner before setting `hcloud_image` to the resulting snapshot ID.
- Set `runner_image_family = "nixos"` and `attic_enabled = true`.
- Set `workspace_volume_size_gb > 0`; Attic stores its SQLite database and NAR
  objects under `/srv/workspaces/attic`.
- Pre-populate the Vault secret named by `attic_vault_secret_mount` and
  `attic_vault_secret_name` with the
  `attic_vault_secret_key = "ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64"` field as
  a base64-encoded RSA PKCS#1 PEM private key.
- On first boot, the NixOS metadata bootstrap writes `/etc/atticd.toml`, writes
  the reverse-proxy config, starts `atticd`, creates the cache, reuses
  pre-seeded Vault tokens when present, and otherwise mints
  `ATTIC_CACHE_PULL_TOKEN` and `ATTIC_CACHE_RW_TOKEN` before patching them plus
  `ATTIC_PUBLIC_KEY`, `ATTIC_API_ENDPOINT`, and
  `ATTIC_SUBSTITUTER_ENDPOINT` back into Vault.
- When `runner_ephemeral = true`, bootstrap installs systemd runner services
  that fetch a fresh registration token from Vault for each restart while using
  the Nixpkgs `github-runner` package on the host.

Operator runbook: see `docs/guides/enable-attic-with-nixos-image.md`.

## Security Baseline

- Leave `admin_cidrs = []` unless SSH is required.
- If enabling SSH CIDRs, provide `ssh_authorized_keys`.
- Keep `github_actions_ssh_ingress_enabled = false` on older snapshots. Enable
  it only after rolling a NixOS image that includes the host-side filter
  tooling needed to enforce the full GitHub Actions CIDR set, and continue to
  use `admin_cidrs` for the local external IPs that must also reach the host.
- Use short-lived Vault bootstrap tokens for first-boot token minting.
- Leave `attic_ingress_cidrs = []` to derive Cloudflare ranges dynamically when
  `cloudflare_attic_proxied = true`, or set explicit CIDRs only when an
  override is required.
- Keep `crowdsec_lapi_port` off the Attic loopback port so the proxy always
  reaches `atticd` instead of the CrowdSec API.
- Keep `crowdsec_enabled = true` and `crowdsec_firewall_bouncer_enabled = true`
  for containerized host hardening.

## Runner Labels

Default labels include:

- `hetzner`
- `arm64`
- `build`
- `cache`

Additional labels can be appended with `runner_labels`.

The current deployment appends the shared labels `shared` and `production`.

## CI Routing Example

```yaml
runs-on: [self-hosted, Linux, ARM64, hetzner, build, cache, shared, production]
```

## Attic rollout

The intended cache endpoint is `attic.vslice.net` on the same Hetzner host as
the runner. The NixOS image path is now the supported bootstrap route for that
service. Keep Ubuntu images on the slim runner-only path.

Key implementation notes: see `docs/decisions/2026-05-01-co-locate-attic-with-runner.md`, `docs/decisions/2026-05-04-attic-cloudflare-and-crowdsec-hardening.md`, `docs/specs/2026-05-08-runner-lifecycle-and-state.md`, `docs/specs/2026-05-08-nixos-native-runner-and-cloudflare-edge.md`, and `docs/specs/2026-05-11-single-ingress-tls-and-ssh-source-policy.md`.
