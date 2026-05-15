variable "runner_enabled" {
  description = "Whether to provision the Hetzner runner, Attic cache, and Cloudflare tunnel stack."
  type        = bool
  default     = false
}

variable "github_owner" {
  description = "GitHub owner for the repository that should use the runner."
  type        = string
  default     = ""

  validation {
    condition     = !var.runner_enabled || length(trimspace(var.github_owner)) > 0
    error_message = "github_owner must be set when runner_enabled is true."
  }
}

variable "github_repository" {
  description = "GitHub repository name that should use the runner."
  type        = string
  default     = ""

  validation {
    condition     = !var.runner_enabled || length(trimspace(var.github_repository)) > 0
    error_message = "github_repository must be set when runner_enabled is true."
  }
}

variable "github_runner_group" {
  description = "Optional GitHub runner group name. Use the default group by leaving this empty."
  type        = string
  default     = ""
}

variable "runner_name" {
  description = "Runner name override. Leave null to keep the persistent random pet-name."
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

variable "github_runner_token" {
  description = "GitHub personal access token used both by the GitHub provider and by the host-side ephemeral runner service."
  type        = string
  sensitive   = true
  default     = null

  validation {
    condition     = !var.runner_enabled || (var.github_runner_token != null && length(trimspace(var.github_runner_token)) > 0)
    error_message = "github_runner_token must be set when runner_enabled is true."
  }
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
  description = "Cloudflare API token used to manage the tunnel, DNS record, R2 bucket, and R2 account token."
  type        = string
  sensitive   = true
  default     = null

  validation {
    condition     = !var.runner_enabled || (var.cloudflare_api_token != null && length(trimspace(var.cloudflare_api_token)) > 0)
    error_message = "cloudflare_api_token must be set when runner_enabled is true."
  }
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID that owns the R2 bucket and Zero Trust tunnel."
  type        = string
  default     = null

  validation {
    condition     = !var.runner_enabled || (var.cloudflare_account_id != null && length(trimspace(var.cloudflare_account_id)) > 0)
    error_message = "cloudflare_account_id must be set when runner_enabled is true."
  }
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID that owns attic_domain."
  type        = string
  default     = null

  validation {
    condition     = !var.runner_enabled || (var.cloudflare_zone_id != null && length(trimspace(var.cloudflare_zone_id)) > 0)
    error_message = "cloudflare_zone_id must be set when runner_enabled is true."
  }
}

variable "hcloud_location" {
  description = "Hetzner location for the runner server."
  type        = string
  default     = "nbg1"
}

variable "hcloud_server_type" {
  description = "Hetzner ARM server type. CAX11 is the requested baseline for this stack."
  type        = string
  default     = "cax11"
}

variable "hcloud_image" {
  description = "Hetzner image to use for the bootstrap host before nixos-anywhere replaces it."
  type        = string
  default     = "ubuntu-24.04"
}

variable "attic_domain" {
  description = "Canonical DNS name for the public Attic cache endpoint."
  type        = string
  default     = "attic.vslice.net"

  validation {
    condition     = !var.runner_enabled || length(trimspace(var.attic_domain)) > 0
    error_message = "attic_domain must be set when runner_enabled is true."
  }
}

variable "attic_local_port" {
  description = "Loopback port used by atticd and by the runner for Attic pushes."
  type        = number
  default     = 8080

  validation {
    condition     = var.attic_local_port >= 1 && var.attic_local_port <= 65535
    error_message = "attic_local_port must be between 1 and 65535."
  }
}

variable "attic_cache_name" {
  description = "Attic cache name created on first boot."
  type        = string
  default     = "github-actions"
}

variable "attic_cache_public" {
  description = "Whether the Attic cache is public for pull access."
  type        = bool
  default     = true
}

variable "attic_cache_priority" {
  description = "Priority configured on the Attic cache. Lower numbers have higher priority; cache.nixos.org uses 40."
  type        = number
  default     = 41
}

variable "cloudflare_tunnel_name" {
  description = "Optional name override for the Cloudflare Tunnel object."
  type        = string
  default     = null
}

variable "r2_bucket_name" {
  description = "Optional R2 bucket name override. Leave null to let Terraform generate an internal bucket name."
  type        = string
  default     = null
}

variable "r2_location" {
  description = "Cloudflare R2 preferred bucket location."
  type        = string
  default     = "wnam"
}

variable "r2_storage_class" {
  description = "Cloudflare R2 storage class used for new objects."
  type        = string
  default     = "Standard"
}

variable "install_disk_device" {
  description = "Optional explicit install disk path for nixos-anywhere. Leave null to auto-detect the first disk on the bootstrap host."
  type        = string
  default     = null
}

variable "admin_cidrs" {
  description = "CIDR blocks allowed to SSH to the bootstrap and NixOS host."
  type        = list(string)
  default     = []
}

variable "ssh_authorized_keys" {
  description = "SSH public keys placed on the bootstrap and NixOS host."
  type        = list(string)
  default     = []

  validation {
    condition     = !var.runner_enabled || length(var.ssh_authorized_keys) > 0
    error_message = "ssh_authorized_keys must include at least one key when runner_enabled is true."
  }
}

variable "hcloud_existing_ssh_key_names" {
  description = "Existing Hetzner SSH key names to reuse instead of creating new account-level keys."
  type        = list(string)
  default     = []
}

variable "ssh_private_key_path" {
  description = "Local private key path used by Terraform provisioners and nixos-anywhere to reach the host."
  type        = string
  default     = null

  validation {
    condition     = !var.runner_enabled || (var.ssh_private_key_path != null && fileexists(pathexpand(var.ssh_private_key_path)))
    error_message = "ssh_private_key_path must point at an existing local private key when runner_enabled is true."
  }
}
