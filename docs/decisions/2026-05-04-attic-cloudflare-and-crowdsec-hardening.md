# Attic Cloudflare and CrowdSec hardening

Date: 2026-05-04
Status: Accepted

## Context

The Attic endpoint for the GitHub runner stack is intended to be
`attic.vslice.net` behind Cloudflare, but DNS publication and origin filtering
were not declaratively enforced in this Terraform stack.

The runner host also lacked a concrete intrusion-response control plane tied to
failed authentication activity. Existing Hetzner firewall controls were present,
but not paired with local behavioral enforcement.

## Decision

Extend this stack to manage Attic edge and host hardening directly:

- Add Cloudflare provider wiring and manage the `attic_domain` A record with
  Terraform when Attic is enabled.
- Keep the DNS record proxied by default.
- Restrict Hetzner Attic ingress CIDRs to Cloudflare anycast ranges by default.
- Bootstrap CrowdSec as containerized services (`crowdsec` and
  `crowdsec-firewall-bouncer`) through cloud-init.
- Keep CrowdSec enabled by default and run it with Docker-managed lifecycle.

## Consequences

- DNS drift for the Attic endpoint is reduced because origin publication is now
  Terraform-managed.
- Attic origin exposure is reduced by defaulting ingress to Cloudflare ranges.
- Host-level security posture improves with automated detection and blocking.
- Bootstrap complexity increases, especially around CrowdSec container startup
  ordering and bouncer key registration.
- Operational validation must now include Cloudflare API token/zone inputs and
  CrowdSec container health checks.
