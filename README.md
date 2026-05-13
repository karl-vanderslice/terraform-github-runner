# terraform-github-runner

Terraform for a Hetzner-hosted self-hosted GitHub Actions runner, currently scoped to Hetzner only.

## Scope

- Provider: Hetzner Cloud (`hcloud`)
- Architecture: ARM64 (`cax21` default)
- Persistence: attached Hetzner volume for runner work/cache
- Registration: GitHub provider token mode or Vault-backed token minting
- Optional cache: Attic bootstrap on the same host when using the NixOS image path, fronted by Cloudflare through a reverse proxy on the VM
- Optional ephemeral runner mode: systemd-managed self re-registration using Vault-backed GitHub token minting

## What This Provisions

- `hcloud_server` for the runner host
- `hcloud_volume` for persistent cache/work data
- optional `hcloud_volume` for workspaces, Attic data, and other durable CI state
- `hcloud_volume_attachment` for the cache mount
- `hcloud_firewall` with optional SSH ingress and unrestricted egress
- optional `cloudflare_dns_record` for `attic_domain` origin routing
- optional `cloudflare_origin_ca_certificate` fallback when `attic_tls_mode = "cloudflare-origin-ca"`
- optional `vault_policy` for runner bootstrap token read access
- optional Attic bootstrap with local storage on the workspace volume, Vault-backed token publication, and a single on-host Caddy ingress in front of `atticd`
- runner cache/work directories that prefer the workspace volume when attached (with cache-volume fallback)
- optional containerized CrowdSec agent + firewall bouncer bootstrap

## Quick Start

```bash
cp terraform.tfvars.example terraform.tfvars
cp backend.hcl.example backend.hcl

just format
just lint
just init
just plan
```

Set core values in `terraform.tfvars` for the nix-config runner + Attic path:

```hcl
runner_enabled       = true
registration_scope   = "repository"
registration_mode    = "vault-token"
github_owner         = "your-org-or-user"
github_repository    = "nix-config"
github_repositories  = []
runner_labels        = ["nix-config"]
runner_ephemeral     = true

hcloud_location      = "nbg1"
hcloud_server_type   = "cax21"
hcloud_image         = "nixos-runner-hetzner-image"
runner_image_family  = "nixos"
hcloud_volume_size_gb = 100
workspace_volume_size_gb = 200
workspace_mount_path     = "/srv/workspaces"

attic_enabled            = true
attic_domain             = "attic.vslice.net"
attic_endpoint_scheme    = "https"
attic_tls_mode           = "letsencrypt"
attic_port               = 443
attic_internal_port      = 8080
attic_cache_name         = "github-actions"

cloudflare_attic_dns_enabled = true
cloudflare_attic_proxied     = true
cloudflare_attic_ttl         = 1

crowdsec_enabled                 = true
crowdsec_lapi_port               = 18080
crowdsec_firewall_bouncer_enabled = true
```

Apply:

```bash
just apply
```

## Configuration Model

1. `runner_enabled` is a safety switch. Keep it `false` until plan output is reviewed.
2. `runner_name` is optional. When unset, Terraform uses a persistent
   `random_pet` name with `github-runner-` prefix so hostnames stay generic.
   This codifies a pets-vs-cattle policy: instances remain replaceable
   infrastructure, but human-readable pet names are preferred over rigid
   environment-bound hostnames.
3. `registration_scope` controls org-level vs repo-level registration.
4. `registration_mode` controls how registration tokens are sourced:
   - `github-provider`: Terraform fetches short-lived token(s) at apply.
   - `vault-token`: the first-boot bootstrap reads a GitHub API token from Vault, then mints short-lived runner registration tokens on boot.
5. `runner_ephemeral` switches the host from long-lived runner services to self-re-registering ephemeral runners. It requires `registration_mode = "vault-token"` so each restart can mint a fresh GitHub registration token.
6. `runner_image_family` selects the bootstrap path:
   - `ubuntu`: use Hetzner stock images and cloud-init package installation.
   - `nixos`: point `hcloud_image` at a custom NixOS image built from this repo. The image boots a metadata-driven first-boot service, so the host no longer depends on cloud-init applying the custom-image user-data.
7. `attic_enabled` turns on Attic bootstrap. It requires `runner_image_family = "nixos"`, `workspace_volume_size_gb > 0`, and Vault settings so the host can read the signing key and publish both the shared pull token and the CI read-write token.
8. `cloudflare_attic_dns_enabled` lets Terraform publish the `attic_domain` A record in Cloudflare using the runner IPv4 as origin.
9. `attic_tls_mode` selects the origin TLS path. `letsencrypt` is the default and lets Caddy manage a public certificate for Cloudflare Full (strict); `cloudflare-origin-ca` keeps the Terraform-managed origin certificate flow as a fallback.
10. `attic_ingress_cidrs` can be left empty to derive Cloudflare anycast ranges from the provider's `cloudflare_ip_ranges` data source, so the Hetzner firewall only accepts Attic traffic from Cloudflare when proxying is enabled.
11. `github_actions_ssh_ingress_enabled` is an opt-in NixOS host-side filter for GitHub Actions plus local operator SSH sources. Enable it only after rolling an image that includes the required packet-filter tooling.
12. `crowdsec_enabled` starts CrowdSec and its firewall bouncer as Docker containers at bootstrap time.

## Operational Guidance

- Use repository scope first for blast-radius control.
- Keep `admin_cidrs` empty unless direct SSH maintenance is required.
- If `admin_cidrs` is set, at least one SSH public key must be provided in `ssh_authorized_keys`.
- Leave `github_actions_ssh_ingress_enabled = false` on older snapshots. Enable it only after the NixOS image includes the host-side packet-filter tooling needed to enforce the full GitHub Actions CIDR set.
- Prefer `vault_auth_mount` plus the admin automation AppRole fields for `vault-token` mode; keep `vault_bootstrap_token` short-lived when used as a fallback.
- Runner bootstrap `user_data` is lifecycle-ignored to avoid churn from ephemeral token changes.
- Use `workspace_volume_size_gb` when the host needs additional persistent
   capacity for checked-out repos, cache expansions, or future Attic data.
- Bind mounts for `/srv/workspaces` and `/var/cache/github-actions` are managed as systemd mount units so durable volumes remain attached across host reboots.
- On the NixOS image path, the host reads its bootstrap script directly from the Hetzner metadata endpoint on first boot instead of relying on cloud-init's custom-image datasource behavior.
- The NixOS bootstrap mounts attached Hetzner volumes by their stable `/dev/disk/by-id/scsi-0HC_Volume_<id>` paths instead of assuming Hetzner auto-mounts `/mnt/HC_Volume_*`.
- CrowdSec now binds its loopback API on `crowdsec_lapi_port` instead of contending with the Attic backend port.
- When `attic_enabled = true`, pre-populate the Vault secret named by
   `attic_vault_secret_mount` and `attic_vault_secret_name` with the
   `attic_vault_secret_key` field containing
   `ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64` as a base64-encoded RSA PKCS#1 PEM
   private key. Bootstrap patches the same secret with
   `ATTIC_CACHE_PULL_TOKEN`, `ATTIC_CACHE_RW_TOKEN`, `ATTIC_PUBLIC_KEY`, and
   the published endpoints.

## Attic direction

The target cache topology is an Attic service co-located with the runner host at
`attic.vslice.net`.

- Ubuntu images keep Attic disabled.
- The NixOS image path now supports Attic bootstrap directly on the runner host.
- The host stores Attic data on the workspace volume under `/srv/workspaces/attic`.
- Runner work directories also use the workspace volume under `/srv/workspaces/workspaces` when attached so build work and cache data stay durable alongside Attic.
- Ephemeral runner mode is implemented as systemd services that mint a fresh registration token from Vault for each runner restart while delegating the runner runtime to the Nixpkgs `github-runner` package on NixOS.
- Attic now listens only on loopback and is intended to be served publicly through the on-host reverse proxy on `attic_port`, keeping Cloudflare as the only origin ingress path.
- Caddy is the single public ingress point for Attic; by default it issues and renews a Let's Encrypt certificate for the origin while Cloudflare remains the public edge.
- If the environment must avoid public ACME issuance at the origin, switch `attic_tls_mode` to `cloudflare-origin-ca`.
- Bootstrap creates the cache, reuses any pre-seeded tokens already present in
  Vault, and otherwise mints both a shared pull token and a CI read-write
  token before patching them plus the public key back into Vault.
- Use `just publish-nixos-image` to validate the qcow build, rebuild the
   temporary NixOS seed host, and publish a fresh Hetzner snapshot before
   setting `runner_image_family = "nixos"`.

## Vault + Bitwarden Flow (Hetzner API Token)

1. Store the Hetzner token in Bitwarden field `HCLOUD_TOKEN`.
2. Sync to Vault:

```bash
just hcloud-token-sync-vault
```

1. Export for Terraform execution:

```bash
export TF_VAR_hcloud_token="..."
```

## Validation

```bash
just format
just lint
just test
just pre-commit
```

## Future Provider Expansion

This repository is intentionally Hetzner-only for the initial commit. Additional cloud providers can be added later through explicit module boundaries and separate environment overlays.
