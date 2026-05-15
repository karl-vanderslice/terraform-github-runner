# 2026-05-15 — Replace Image Bootstrap with nixos-anywhere, R2, and Cloudflare Tunnel

## Status

Accepted.

## Context

The previous design depended on a custom NixOS image, large cloud-init bootstrap logic, Hetzner data volumes, and a public VM ingress path. That design had three problems:

- the install flow drifted from the rest of the NixOS estate, which already uses `nixos-anywhere` and Disko for Day 0 installs
- HCP Terraform remote execution could not run the required local Nix toolchain
- Attic was tied to host-local disk and public reverse-proxy exposure instead of R2 object storage and tunnel-only ingress

## Decision

The replacement path is:

- Terraform still stores state in HCP Terraform, but plans and applies execute locally
- Hetzner creates a stock `ubuntu-24.04` `cax11` server with an injected SSH key
- Terraform runs `nixos-anywhere --build-on-remote` from a `null_resource`
- Disko owns the local boot disk layout
- NixOS runs `atticd` on loopback only and stores objects in Cloudflare R2
- Cloudflare Tunnel exposes `attic.vslice.net`; the public DNS record is a proxied CNAME to `<tunnel-id>.cfargotunnel.com`
- The GitHub runner remains ephemeral and uses `http://127.0.0.1:8080` for Attic interactions on the host

## Consequences

- HCP Terraform is now a remote state store, not a remote execution target, for this repo
- The custom image publication path and Hetzner volume bootstrap are removed
- The public Attic endpoint stays signed but becomes readable without an auth token
- The repo now depends on locally available `nixos-anywhere`, SSH material, `gh`, and `rbw` during `just apply`
