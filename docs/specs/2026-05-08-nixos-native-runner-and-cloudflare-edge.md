# NixOS Native Runner And Cloudflare Edge

Date: 2026-05-08
Status: Accepted

## Context

The previous NixOS path relied on two assumptions that did not hold on the live
Hetzner host:

- a custom NixOS image would honor cloud-init user-data like a stock cloud image
- the upstream GitHub Actions runner tarball could be executed directly on NixOS

The live host disproved both assumptions. Hetzner metadata remained available,
but cloud-init on the custom image did not apply the bootstrap payload. Once the
bootstrap script was forced to run manually, the upstream runner tarball still
failed because the generic Linux binary path is not a good fit for NixOS.

The Attic ingress path also remained incomplete. Cloudflare was intended to be
the public edge, but the origin still attempted to serve Attic directly instead
of placing a reverse proxy in front of the local service. The firewall default
for Cloudflare ingress was also hard-coded instead of being sourced from the
provider's published ranges. Once the firewall path was corrected, the live
edge still returned Cloudflare 525 because the origin had no explicit
Cloudflare-compatible certificate strategy.

## Decision

Adopt a Nix-native runtime path for the NixOS host and keep Cloudflare as the
only intended public edge for the Attic endpoint.

- Keep Ubuntu on the existing cloud-init path.
- For `runner_image_family = "nixos"`, disable cloud-init and use a baked
  first-boot systemd service that reads Hetzner user-data from the metadata
  endpoint and executes the extracted bootstrap script exactly once.
- Replace the NixOS runner tarball download path with the Nixpkgs
  `github-runner` package, using its packaged `config.sh` and `run.sh` wrappers.
- Keep per-repository runner instances and durable work directories, but make
  the runtime package-native on NixOS.
- Keep `atticd` bound to loopback and front it with an on-host reverse proxy on
  the public ingress port.
- When Cloudflare proxies the Attic hostname over HTTPS, generate a Cloudflare
  Origin CA certificate from a Terraform-managed CSR and write the resulting
  certificate and private key into the on-host reverse proxy config.
- Derive default Attic ingress CIDRs from `cloudflare_ip_ranges` instead of
  pinning a static list in Terraform variables.

## Acceptance Gates

- A NixOS custom image boots and completes first-boot bootstrap without relying
  on cloud-init's custom-image datasource behavior.
- NixOS runner services use the packaged `github-runner` runtime rather than
  downloading the upstream tarball into `/opt`.
- `atticd` listens only on loopback while the public ingress port is served by
  the reverse proxy.
- The Cloudflare-proxied HTTPS path completes successfully without relying on
  unmanaged ACME issuance at the origin.
- When `attic_ingress_cidrs = []`, the Hetzner firewall still resolves to the
  current Cloudflare IP ranges.
- `/srv/workspaces` and `/var/cache/github-actions` remain backed by durable
  Hetzner volumes.

## Rollback

- Switch `runner_image_family` back to `ubuntu` to return to the stock
  cloud-init path.
- Reintroduce explicit `attic_ingress_cidrs` values if provider-derived ranges
  must be overridden.
- Disable `attic_enabled` to fall back to a runner-only host if the proxy path
  must be removed.
