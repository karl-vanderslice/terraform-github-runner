# Single Ingress TLS And SSH Source Policy

Date: 2026-05-11
Status: Accepted

## Context

The live Hetzner runner stack already depended on an on-host reverse proxy for
Attic, but the tracked Terraform and bootstrap code still lagged the desired
operating model in three ways:

- the origin TLS story was still documented around a Terraform-managed
  Cloudflare Origin CA certificate instead of the requested public Let's
  Encrypt certificate on the origin
- SSH ingress remained manual `admin_cidrs` only, even though the operator
  policy was to allow GitHub-originated access plus the local external IPs
- the NixOS bootstrap path still relied on brittle assumptions that did not
  survive host replacement, including implicit Hetzner volume auto-mounts,
  persistent unit enables under an immutable `/etc`, and a port collision
  between CrowdSec and `atticd`

## Decision

Keep the Hetzner VM on a single-ingress model with Caddy as the only public
service in front of `atticd`, and tighten the firewall around explicit source
sets.

- Default `attic_tls_mode` to `letsencrypt` so Caddy manages the origin
  certificate directly while Cloudflare stays in Full (strict) mode.
- Retain `cloudflare-origin-ca` as an explicit fallback for environments that
  do not want public ACME issuance at the origin.
- Continue deriving Attic ingress CIDRs from Cloudflare when
  `attic_ingress_cidrs = []`.
- Treat GitHub-originated SSH as a host-side filter on NixOS because the
  current GitHub Actions CIDR feed is too large for a practical Hetzner edge
  firewall rule. Keep `github_actions_ssh_ingress_enabled` opt-in until the
  target image definitely includes the required packet-filter tooling.
- On NixOS, mount attached Hetzner volumes by `/dev/disk/by-id` identifiers,
  write generated configs under `/run`, and enable generated systemd units with
  `--runtime`.
- Move CrowdSec off the Attic loopback port so the proxy path is deterministic.

## Acceptance Gates

- `atticd` listens only on loopback while Caddy serves the Attic hostname on
  the public ingress ports.
- `attic_tls_mode = "letsencrypt"` produces an origin certificate usable by
  Cloudflare Full (strict) without requiring a Terraform-managed origin cert.
- When GitHub SSH ingress is enabled on a compatible NixOS image, the host
  filters port 22 to the union of `admin_cidrs` and the GitHub Actions CIDR
  feed.
- Replacing the NixOS host no longer requires manual volume mounts, `/etc`
  edits, or post-boot fixes to the runner helper script path.
- CrowdSec and Attic do not share the same loopback port.

## Rollback

- Set `attic_tls_mode = "cloudflare-origin-ca"` to return to the explicit
  Cloudflare Origin CA flow.
- Set `github_actions_ssh_ingress_enabled = false` to remove GitHub Actions
  CIDRs from SSH ingress while keeping `admin_cidrs` intact.
- Change `crowdsec_lapi_port` only in tandem with any future `attic_internal_port`
  move if the loopback port layout needs to be revised.
