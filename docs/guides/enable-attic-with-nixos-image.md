# Enable Attic With The NixOS Image

Use this path when the Hetzner runner host should also publish the shared Attic
binary cache.

## Prerequisites

- A Vault token with read access to the Attic signing secret and write access to
  the same secret path for bootstrap metadata.
- A Vault KV secret that already contains
  `ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64` as a base64-encoded RSA PKCS#1 PEM
  private key.
- A workspace volume size greater than `0` so Attic can persist data under
  `/srv/workspaces/attic`.
- A Hetzner custom image or snapshot workflow that can publish the qcow output
  from this repository as a usable `hcloud_image` target.

## Build The Host Image

```bash
just build-nixos-image
```

This produces the `nixos-runner-hetzner-image` qcow artifact in `result/`.
Publish that image through your existing Hetzner custom image or snapshot flow,
then record the resulting image name or ID.

## Configure Terraform

Set the runner host to the NixOS image path and enable Attic:

```hcl
runner_enabled            = true
runner_image_family       = "nixos"
hcloud_image              = "<custom-image-or-snapshot>"
workspace_volume_size_gb  = 200
workspace_mount_path      = "/srv/workspaces"

attic_enabled             = true
attic_domain              = "attic.vslice.net"
attic_endpoint_scheme     = "http"
attic_port                = 8080
attic_cache_name          = "github-actions"

vault_addr                = "https://vault.example.invalid:8200"
vault_namespace           = "admin"
vault_bootstrap_token     = "<short-lived-token>"
attic_vault_secret_mount  = "mcp-kv"
attic_vault_secret_name   = "github/runner-attic"
attic_vault_secret_key    = "ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64"
```

## Apply And Verify

```bash
just lint
just test
just plan
just apply
```

On first boot, cloud-init performs these actions:

- bind-mounts the workspace volume at `/srv/workspaces`
- writes `/etc/atticd.env` from Vault
- writes `/etc/atticd.toml` with local SQLite and local storage settings
- starts `atticd`
- creates the configured cache if it does not exist
- reuses any pre-seeded Vault tokens already present for that cache
- otherwise mints a shared pull token and a CI read-write token for that cache
- patches the Vault secret with the CI token, public key, and endpoints

## Resulting Vault Fields

After bootstrap, the Attic secret path contains these additional fields:

- `ATTIC_CACHE_NAME`
- `ATTIC_CACHE_PULL_TOKEN`
- `ATTIC_CACHE_RW_TOKEN`
- `ATTIC_PUBLIC_KEY`
- `ATTIC_API_ENDPOINT`
- `ATTIC_SUBSTITUTER_ENDPOINT`

Use `ATTIC_CACHE_PULL_TOKEN` for developer systems that only need authenticated
substituter access. Use `ATTIC_CACHE_RW_TOKEN` in CI so changed-only builds can
pull from and push to the co-located cache without embedding secrets in
repository config.
