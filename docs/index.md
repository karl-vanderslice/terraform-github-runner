# Hetzner Runner Operator Guide

This repository now manages a single replacement path for the runner host:

- create a Hetzner `cax11` bootstrap VM
- reach it over SSH with an injected Ezra key
- install NixOS with `nixos-anywhere --build-on-remote`
- partition the local disk with Disko
- run `atticd` only on loopback
- expose `attic.vslice.net` only through a Cloudflare Tunnel
- store Attic objects in Cloudflare R2

## Operational Baseline

- `just plan` and `just apply` execute locally while syncing state with HCP Terraform.
- The runner remains repository-scoped and ephemeral.
- The host bootstrap image is always `ubuntu-24.04`; the final system is always NixOS.
- No Hetzner data volumes are used in the replacement design.
- The public cache endpoint is readable anonymously, but signatures remain required.

## Service Topology

- `atticd` listens on `127.0.0.1:8080`
- the GitHub runner gets `ATTIC_ENDPOINT=http://127.0.0.1:8080`
- `cloudflared` proxies `attic.vslice.net` to the loopback Attic listener
- the DNS record for `attic.vslice.net` is a proxied Cloudflare CNAME targeting `<tunnel-id>.cfargotunnel.com`

## References

- Decision log: `docs/decisions/2026-05-15-nixos-anywhere-r2-and-tunnel-replacement.md`
- Historical decisions retained for context: `docs/decisions/2026-05-01-co-locate-attic-with-runner.md`, `docs/decisions/2026-05-04-attic-cloudflare-and-crowdsec-hardening.md`, and `docs/decisions/2026-05-11-immutable-image-publication.md`
