# Immutable Image Publication

Date: 2026-05-11
Status: Accepted

## Context

The Hetzner runner stack already had a Nix-built qcow image derivation, but the
actual publication step remained implicit and operator-driven. The repository
also still carried an old Packer template for Oracle Cloud Infrastructure,
which was not part of the live Hetzner path and created false confidence that a
generic image publication workflow existed.

The desired operating model is immutable replacement: bake the runner host
software into a NixOS image, publish that image, and replace the Hetzner VM by
changing `hcloud_image` instead of hand-mutating the live instance.

## Decision

Adopt a Hetzner-specific seed-and-snapshot publication workflow as the
repository's canonical immutable image path.

- Keep the Nix qcow build as the local validation artifact for the image
  definition.
- Publish with `just publish-nixos-image`, which creates a temporary seed VM
  from the currently published snapshot, copies the current repo state to that
  VM, rebuilds the root-flake `.#seed-publisher` configuration, removes
  machine-specific identity material, powers the VM off, and snapshots it back
  into Hetzner.
- Protect the published snapshot by default so the active image cannot be
  deleted accidentally.
- Remove the stale OCI-only Packer configuration so the repo has a single clear
  Hetzner image publication story.

## Consequences

- Runner host replacement is now driven by a published snapshot ID instead of
  manual runtime drift.
- The publish flow remains fully compatible with the baked Hetzner metadata
  bootstrap model already used by the NixOS runner image.
- The qcow artifact still validates the same image modules locally even though
  Hetzner publication currently happens through a snapshot workflow instead of a
  direct custom-image import.
- Future adoption of Hetzner-specific Packer or direct image import can still
  happen later, but it must replace this workflow explicitly instead of
  coexisting as unused parallel machinery.
