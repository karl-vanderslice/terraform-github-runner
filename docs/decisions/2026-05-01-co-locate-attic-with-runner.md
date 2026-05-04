# Co-locate Attic with the Hetzner CI runner

Date: 2026-05-01
Status: Accepted

## Context

The existing Hetzner runner stack provisions one ARM build host with a single
attached cache volume. There is no Attic deployment yet, which means Nix builds
cannot benefit from a dedicated self-hosted binary cache tied to the CI host.

The desired target is `attic.vslice.net` on the same machine as the GitHub
runner, with enough persistent storage for both runner work data and future
cache growth.

## Decision

Co-locate Attic with the self-hosted Hetzner runner and reserve a second
persistent volume for workspaces, Attic data, and other durable CI state.

- Keep the existing cache volume focused on runner work and ephemeral build
  cache paths.
- Add an optional workspace volume mounted at `/srv/workspaces`.
- Use that second volume as the future home for Attic storage and checked-out
  repository state.
- Use a NixOS host image path for Attic-enabled deployments so the runner host
  can provide `atticd`, `atticadm`, Docker, and Vault tooling without ad hoc
  package bootstrap.
- Read the Attic signing secret from Vault at first boot and patch the CI cache
  token and public key back into Vault after bootstrap.

## Consequences

- The runner host can grow storage independently for work data instead of
  overloading the cache volume.
- Attic rollout now has both a durable filesystem target and a supported host
  bootstrap path in Terraform.
- Ubuntu images remain supported for runner-only deployments but are not the
  Attic path.
- Future DNS and reverse-proxy work for `attic.vslice.net` can assume the cache
  service lives on the runner machine.
