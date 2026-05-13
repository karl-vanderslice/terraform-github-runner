variable "runner_enabled" {
  description = "Whether to provision the Hetzner runner instance and cache volume."
  type        = bool
  default     = false
}

variable "registration_mode" {
  description = "github-provider injects a short-lived registration token. vault-token reads a GitHub API token from Vault and mints a registration token at boot."
  type        = string
  default     = "github-provider"

  validation {
    condition     = contains(["github-provider", "vault-token"], var.registration_mode)
    error_message = "registration_mode must be github-provider or vault-token."
  }
}

variable "registration_scope" {
  description = "Runner registration scope. organization makes the runner available to repositories in the configured runner group; repository keeps the runner scoped to one repository."
  type        = string
  default     = "organization"

  validation {
    condition     = contains(["organization", "repository"], var.registration_scope)
    error_message = "registration_scope must be organization or repository."
  }
}

variable "github_owner" {
  description = "GitHub owner for the target repository."
  type        = string
  default     = null

  validation {
    condition     = !var.runner_enabled || (var.github_owner != null && length(trimspace(var.github_owner)) > 0)
    error_message = "github_owner must be set when runner_enabled is true."
  }
}

variable "github_repository" {
  description = "GitHub repository name for repository-scoped runner registration. Leave null for organization scope."
  type        = string
  default     = null

  validation {
    condition     = !var.runner_enabled || var.registration_scope == "organization" || (var.github_repository != null && length(trimspace(var.github_repository)) > 0)
    error_message = "github_repository must be set when registration_scope is repository."
  }
}

variable "github_repositories" {
  description = "Additional repositories that should receive dedicated runner registrations on the same host when using repository scope."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for repo in var.github_repositories : length(trimspace(repo)) > 0])
    error_message = "github_repositories cannot contain empty values."
  }
}

variable "github_runner_group" {
  description = "Runner group name to pass to the GitHub runner config command."
  type        = string
  default     = "Default"
}

variable "runner_name" {
  description = "Runner name override. Leave null to use a persistent random pet-name such as github-runner-quiet-otter."
  type        = string
  default     = null

  validation {
    condition     = var.runner_name == null || length(trimspace(var.runner_name)) > 0
    error_message = "runner_name must be null or a non-empty string."
  }
}

variable "runner_labels" {
  description = "Additional labels applied to the runner."
  type        = list(string)
  default     = []
}

variable "runner_ephemeral" {
  description = "Whether runner services should self-register as ephemeral GitHub runners and re-register after each job. Requires registration_mode = vault-token."
  type        = bool
  default     = false
}

variable "actions_runner_version" {
  description = "GitHub Actions runner version to install."
  type        = string
  default     = "2.329.0"
}

variable "hcloud_token" {
  description = "Hetzner Cloud API token with RW access."
  type        = string
  sensitive   = true
  default     = null

  validation {
    condition     = !var.runner_enabled || (var.hcloud_token != null && length(trimspace(var.hcloud_token)) > 0)
    error_message = "hcloud_token must be set when runner_enabled is true."
  }
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token used to manage attic DNS records."
  type        = string
  sensitive   = true
  default     = null

  validation {
    condition     = !(var.attic_enabled && var.cloudflare_attic_dns_enabled && (var.cloudflare_api_token == null || length(trimspace(var.cloudflare_api_token)) == 0))
    error_message = "cloudflare_api_token must be set when attic_enabled and cloudflare_attic_dns_enabled are true."
  }
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID that owns attic_domain."
  type        = string
  default     = null

  validation {
    condition     = !(var.attic_enabled && var.cloudflare_attic_dns_enabled && (var.cloudflare_zone_id == null || length(trimspace(var.cloudflare_zone_id)) == 0))
    error_message = "cloudflare_zone_id must be set when attic_enabled and cloudflare_attic_dns_enabled are true."
  }
}

variable "cloudflare_attic_dns_enabled" {
  description = "Whether Terraform should manage an attic_domain A record in Cloudflare."
  type        = bool
  default     = true
}

variable "cloudflare_attic_proxied" {
  description = "Whether the attic_domain DNS record is proxied through Cloudflare."
  type        = bool
  default     = true
}

variable "cloudflare_attic_ttl" {
  description = "TTL for the Cloudflare attic_domain DNS record. Use 1 for automatic TTL."
  type        = number
  default     = 1

  validation {
    condition     = var.cloudflare_attic_ttl == 1 || (var.cloudflare_attic_ttl >= 60 && var.cloudflare_attic_ttl <= 86400)
    error_message = "cloudflare_attic_ttl must be 1 (automatic) or between 60 and 86400 seconds."
  }
}

variable "hcloud_location" {
  description = "Hetzner location for the runner server."
  type        = string
  default     = "nbg1"
}

variable "hcloud_server_type" {
  description = "Hetzner ARM server type. cax21 is 4 vCPU / 8 GB RAM."
  type        = string
  default     = "cax21"
}

variable "hcloud_image" {
  description = "Hetzner image to use for the runner host."
  type        = string
  default     = "ubuntu-24.04"
}

variable "runner_image_family" {
  description = "Host image family. Use nixos when hcloud_image points at a custom NixOS image that boots a metadata-driven first-boot service instead of relying on cloud-init."
  type        = string
  default     = "ubuntu"

  validation {
    condition     = contains(["ubuntu", "nixos"], var.runner_image_family)
    error_message = "runner_image_family must be ubuntu or nixos."
  }
}

variable "hcloud_volume_size_gb" {
  description = "Persistent volume size for build/cache data in GB."
  type        = number
  default     = 100

  validation {
    condition     = var.hcloud_volume_size_gb >= 10
    error_message = "hcloud_volume_size_gb must be >= 10."
  }
}

variable "workspace_volume_size_gb" {
  description = "Optional second Hetzner volume for workspaces, Attic data, and other durable CI state. Set to 0 to disable."
  type        = number
  default     = 0

  validation {
    condition     = var.workspace_volume_size_gb == 0 || var.workspace_volume_size_gb >= 10
    error_message = "workspace_volume_size_gb must be 0 or >= 10."
  }
}

variable "workspace_mount_path" {
  description = "Host path where the optional workspace volume is bind-mounted when enabled."
  type        = string
  default     = "/srv/workspaces"
}

variable "attic_enabled" {
  description = "Whether to bootstrap an Attic binary cache on the runner host. Requires runner_image_family = nixos and a workspace volume."
  type        = bool
  default     = false
}

variable "attic_domain" {
  description = "Canonical DNS name for the Attic service."
  type        = string
  default     = "attic.vslice.net"

  validation {
    condition     = !var.attic_enabled || length(trimspace(var.attic_domain)) > 0
    error_message = "attic_domain must be set when attic_enabled is true."
  }
}

variable "attic_endpoint_scheme" {
  description = "Endpoint scheme advertised by Attic. Use https when a reverse proxy or TLS terminator fronts the service."
  type        = string
  default     = "http"

  validation {
    condition     = contains(["http", "https"], var.attic_endpoint_scheme)
    error_message = "attic_endpoint_scheme must be http or https."
  }
}

variable "attic_tls_mode" {
  description = "TLS strategy for the Attic reverse proxy when attic_endpoint_scheme is https. letsencrypt uses Caddy-managed ACME on the origin; cloudflare-origin-ca uses a Terraform-managed Cloudflare Origin CA certificate."
  type        = string
  default     = "letsencrypt"

  validation {
    condition     = contains(["letsencrypt", "cloudflare-origin-ca"], var.attic_tls_mode)
    error_message = "attic_tls_mode must be letsencrypt or cloudflare-origin-ca."
  }
}

variable "attic_port" {
  description = "Public TCP port used by the Attic reverse proxy on the runner host. Keep 443 when Cloudflare proxies the cache endpoint."
  type        = number
  default     = 8080

  validation {
    condition     = var.attic_port >= 1 && var.attic_port <= 65535
    error_message = "attic_port must be between 1 and 65535."
  }
}

variable "attic_internal_port" {
  description = "Loopback port used by atticd behind the reverse proxy on the runner host."
  type        = number
  default     = 8080

  validation {
    condition     = var.attic_internal_port >= 1 && var.attic_internal_port <= 65535
    error_message = "attic_internal_port must be between 1 and 65535."
  }
}

variable "attic_ingress_cidrs" {
  description = "CIDR blocks allowed to reach the Attic reverse proxy. Leave empty to derive Cloudflare anycast ranges dynamically."
  type        = list(string)
  default     = []
}

variable "attic_cache_name" {
  description = "Attic cache name created during bootstrap."
  type        = string
  default     = "github-actions"
}

variable "attic_cache_public" {
  description = "Whether the Attic cache is public for pull access."
  type        = bool
  default     = false
}

variable "attic_cache_priority" {
  description = "Priority configured on the Attic cache. Lower numbers have higher priority; cache.nixos.org uses 40."
  type        = number
  default     = 41
}

variable "attic_ci_token_validity" {
  description = "Validity period used when minting the Attic CI read-write token. Accepts humantime values such as 30d, 3 months, or 1y."
  type        = string
  default     = "1y"
}

variable "attic_pull_token_validity" {
  description = "Validity period used when minting the shared Attic pull-only token for developer systems. Accepts humantime values such as 30d, 3 months, or 1y."
  type        = string
  default     = "1y"
}

variable "crowdsec_enabled" {
  description = "Whether to bootstrap CrowdSec as containerized services on the runner host."
  type        = bool
  default     = true
}

variable "crowdsec_lapi_port" {
  description = "CrowdSec local API port exposed on the runner host loopback interface."
  type        = number
  default     = 18080

  validation {
    condition     = var.crowdsec_lapi_port >= 1 && var.crowdsec_lapi_port <= 65535
    error_message = "crowdsec_lapi_port must be between 1 and 65535."
  }
}

variable "crowdsec_firewall_bouncer_enabled" {
  description = "Whether to run the CrowdSec firewall bouncer container with NET_ADMIN capabilities."
  type        = bool
  default     = true
}

variable "admin_cidrs" {
  description = "Additional CIDR blocks allowed to SSH to the runner. Use this for local operator IPs; GitHub Actions ranges are controlled separately."
  type        = list(string)
  default     = []
}

variable "github_actions_ssh_ingress_enabled" {
  description = "Whether to enforce GitHub Actions plus local-admin SSH source filtering on the NixOS host. Enable it only on images that include the required packet-filter tooling."
  type        = bool
  default     = false
}

variable "ssh_authorized_keys" {
  description = "SSH public keys placed on the runner instance and imported to Hetzner."
  type        = list(string)
  default     = []
}

variable "vault_addr" {
  description = "Vault address for optional boot-time secret retrieval."
  type        = string
  default     = null
}

variable "vault_namespace" {
  description = "Vault namespace for HCP Vault."
  type        = string
  default     = "admin"
}

variable "vault_runner_secret_mount" {
  description = "Vault KV v2 mount name containing the GitHub bootstrap secret."
  type        = string
  default     = "mcp-kv"
}

variable "vault_runner_secret_name" {
  description = "Vault secret name containing GitHub API token for minting runner registration token."
  type        = string
  default     = "github/runner-bootstrap"
}

variable "vault_runner_secret_key" {
  description = "Field inside the Vault secret that stores the GitHub API token."
  type        = string
  default     = "GITHUB_TOKEN"
}

variable "attic_vault_secret_mount" {
  description = "Vault KV v2 mount name containing the Attic signing secret and where bootstrap metadata is written back."
  type        = string
  default     = "mcp-kv"
}

variable "attic_vault_secret_name" {
  description = "Vault secret name containing the Attic server signing secret. Bootstrap patches the same secret with pull and CI tokens, the public key, and the published endpoints."
  type        = string
  default     = "github/runner-attic"
}

variable "attic_vault_secret_key" {
  description = "Field inside the Vault secret that stores the base64-encoded RSA PKCS#1 PEM private key used by ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64."
  type        = string
  default     = "ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64"
}

variable "vault_bootstrap_token" {
  description = "Vault token injected into first-boot bootstrap when registration_mode is vault-token. Prefer short TTL token."
  type        = string
  sensitive   = true
  default     = null
}

variable "vault_auth_mount" {
  description = "Vault auth mount used for AppRole login when the runner host should avoid a static bootstrap token."
  type        = string
  default     = null
}

variable "vault_admin_automation_role_id" {
  description = "Vault AppRole role_id used by the runner host to mint a fresh client token at runtime."
  type        = string
  sensitive   = true
  default     = null
}

variable "vault_admin_automation_secret_id" {
  description = "Vault AppRole secret_id used by the runner host to mint a fresh client token at runtime."
  type        = string
  sensitive   = true
  default     = null
}

variable "enable_vault_bootstrap_policy" {
  description = "Whether Terraform should create a policy for reading the runner bootstrap secret."
  type        = bool
  default     = false
}
