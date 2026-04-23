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
  description = "Runner name override. Leave null to derive from repository name."
  type        = string
  default     = null
}

variable "runner_labels" {
  description = "Additional labels applied to the runner."
  type        = list(string)
  default     = []
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

variable "hcloud_volume_size_gb" {
  description = "Persistent volume size for build/cache data in GB."
  type        = number
  default     = 100

  validation {
    condition     = var.hcloud_volume_size_gb >= 10
    error_message = "hcloud_volume_size_gb must be >= 10."
  }
}

variable "admin_cidrs" {
  description = "CIDR blocks allowed to SSH to the runner. Leave empty to disable inbound SSH."
  type        = list(string)
  default     = []
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

variable "vault_bootstrap_token" {
  description = "Vault token injected into cloud-init when registration_mode is vault-token. Prefer short TTL token."
  type        = string
  sensitive   = true
  default     = null
}

variable "enable_vault_bootstrap_policy" {
  description = "Whether Terraform should create a policy for reading the runner bootstrap secret."
  type        = bool
  default     = false
}
