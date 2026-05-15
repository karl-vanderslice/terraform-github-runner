# terraform-github-runner

Terraform for a Hetzner-hosted GitHub Actions runner that installs NixOS with `nixos-anywhere`, partitions the local boot disk with Disko, exposes Attic only through a Cloudflare Tunnel, and stores Attic objects in Cloudflare R2.

## Architecture

- Bootstrap host: Hetzner `cax11` on the stock `ubuntu-24.04` image
- Install path: Terraform `null_resource` runs `nixos-anywhere --build-on-remote`
- Disk layout: Disko on the local machine disk, not Hetzner volumes
- Cache backend: `atticd` on loopback with R2 object storage
- Public ingress: Cloudflare Tunnel and proxied `attic.vslice.net` CNAME
- Runner behavior: Ephemeral GitHub runner configured from a long-lived PAT, with Attic reachable locally at `http://127.0.0.1:8080`

## Execution Model

`backend.hcl` still points at HCP Terraform, but `just plan` and `just apply` execute locally. The repo now pulls remote state, runs Terraform locally so `nixos-anywhere` and SSH material are available, and pushes the updated state back when the run succeeds.

This is deliberate. HCP Terraform remote execution cannot satisfy the install path because the remote worker does not have the repo dev shell, `nixos-anywhere`, or the local SSH private key needed to reach the Hetzner server.

## Quick Start

```bash
cp terraform.tfvars.example terraform.tfvars
cp backend.hcl.example backend.hcl

just format
just lint
just plan
just apply
```

The secret wrapper loads:

- Hetzner from `rbw get Hetzner`
- GitHub from `gh auth token`
- Cloudflare from `terraform-home-network/.env` or `agent-hub/.env`
- SSH access from `~/.ssh/ezra-device-access`

## Required Inputs

Set the non-secret values in `terraform.tfvars`:

```hcl
runner_enabled     = true
github_owner       = "karl-vanderslice"
github_repository  = "agent-hub"
runner_labels      = ["shared", "production"]

hcloud_location    = "nbg1"
hcloud_server_type = "cax11"
hcloud_image       = "ubuntu-24.04"

attic_domain       = "attic.vslice.net"
attic_cache_name   = "github-actions"
attic_cache_public = true
attic_local_port   = 8080
```

Secrets are expected through environment variables injected by `scripts/with-runner-secrets.sh`.

## Validation

```bash
just format
just lint
just test
just pre-commit
```

## Notes

- The public cache remains signed even though it is readable anonymously.
- The runner itself uses the local Attic endpoint on `127.0.0.1:8080`; only Cloudflare reaches the public hostname.
- The committed `nixos/generated-config.json` is a placeholder. The install step rewrites it in the local execution sandbox with live Terraform values before calling `nixos-anywhere`.
