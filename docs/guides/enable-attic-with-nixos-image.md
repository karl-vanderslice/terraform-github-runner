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

## Build And Publish The Host Image

```bash
just publish-nixos-image
```

This validates the `nixos-runner-hetzner-image` qcow artifact in `result/`,
then creates a temporary Hetzner seed VM from the current published snapshot,
rebuilds it to the current root-flake `.#seed-publisher` configuration,
syspreps the machine identity, and publishes a fresh protected Hetzner
snapshot.

Record the published snapshot ID and use that as `hcloud_image`.

## Configure Terraform

Set the runner host to the NixOS image path and enable Attic:

```hcl
runner_enabled            = true
registration_mode         = "vault-token"
runner_ephemeral          = true
runner_image_family       = "nixos"
hcloud_image              = "<custom-image-or-snapshot>"
workspace_volume_size_gb  = 200
workspace_mount_path      = "/srv/workspaces"

attic_enabled             = true
attic_domain              = "attic.vslice.net"
attic_endpoint_scheme     = "https"
attic_tls_mode            = "letsencrypt"
attic_port                = 443
attic_internal_port       = 8080
attic_cache_name          = "github-actions"

vault_addr                = "https://vault.example.invalid:8200"
vault_namespace           = "admin"
vault_auth_mount          = "approle"
vault_admin_automation_role_id   = "<approle-role-id>"
vault_admin_automation_secret_id = "<approle-secret-id>"
# vault_bootstrap_token    = "<short-lived-token>" # optional fallback
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

On first boot, the metadata bootstrap service on the NixOS image performs these actions:

- installs systemd mount units for `/srv/workspaces` and `/var/cache/github-actions` so both durable paths survive reboots
- bind-mounts `/var/cache/github-actions` to `/srv/workspaces/workspaces/github-actions` so runner work directories and Attic share the same durable volume
- writes `/etc/atticd.env` from Vault
- writes `/etc/atticd.toml` with local SQLite and local storage settings bound to loopback
- writes `/etc/caddy/Caddyfile` so Cloudflare reaches Attic through the local reverse proxy instead of hitting `atticd` directly
- starts `atticd`
- starts the reverse proxy on the public Attic ingress port
- starts systemd-managed runner services that re-register after each job when `runner_ephemeral = true`
- creates the configured cache if it does not exist
- reuses any pre-seeded Vault tokens already present for that cache
- otherwise mints a shared pull token and a CI read-write token for that cache
- patches the Vault secret with the CI token, public key, and endpoints

Keep `registration_mode = "vault-token"` for this path. Ephemeral runners need a fresh GitHub registration token every time the service restarts, which the Terraform provider token mode cannot provide after the initial apply.

Leave `attic_ingress_cidrs = []` unless you need an explicit override. Terraform now derives the Cloudflare edge ranges directly from the provider's `cloudflare_ip_ranges` data source.

Enable `github_actions_ssh_ingress_enabled = true` only after rolling a NixOS image that includes the host-side packet-filter tooling needed to enforce the full GitHub Actions CIDR set, and use `admin_cidrs` only for the local external IPs that should be allowed alongside it.

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
