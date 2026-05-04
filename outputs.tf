output "github_repository_full_name" {
  description = "GitHub repository wired to the runner when registration_scope is repository."
  value       = var.registration_scope == "repository" ? "${var.github_owner}/${var.github_repository}" : null
}

output "registration_mode" {
  description = "Runner registration strategy selected for the current configuration."
  value       = var.registration_mode
}

output "registration_scope" {
  description = "Runner registration scope selected for the current configuration."
  value       = var.registration_scope
}

output "runner_server_id" {
  description = "Hetzner server ID for the runner when enabled."
  value       = var.runner_enabled ? hcloud_server.runner[0].id : null
}

output "runner_ipv4" {
  description = "Public IPv4 address for the runner when enabled."
  value       = var.runner_enabled ? hcloud_server.runner[0].ipv4_address : null
}

output "runner_ipv6" {
  description = "Public IPv6 network for the runner when enabled."
  value       = var.runner_enabled ? hcloud_server.runner[0].ipv6_address : null
}

output "cache_volume_id" {
  description = "Hetzner volume ID used for build/cache persistence."
  value       = var.runner_enabled ? hcloud_volume.cache[0].id : null
}

output "workspace_volume_id" {
  description = "Hetzner volume ID used for optional workspace and Attic persistence."
  value       = var.runner_enabled && var.workspace_volume_size_gb > 0 ? hcloud_volume.workspace[0].id : null
}

output "workspace_mount_path" {
  description = "Host path used for the optional workspace volume bind mount."
  value       = var.workspace_mount_path
}

output "attic_enabled" {
  description = "Whether Attic bootstrap is enabled for the runner host."
  value       = var.attic_enabled
}

output "attic_endpoint" {
  description = "Published Attic endpoint when bootstrap is enabled."
  value       = var.attic_enabled ? local.attic_endpoint : null
}

output "attic_cache_name" {
  description = "Attic cache name created during bootstrap."
  value       = var.attic_enabled ? var.attic_cache_name : null
}

output "vault_runner_secret_path" {
  description = "Vault secret path the runner reads in vault-token mode."
  value       = "${var.vault_runner_secret_mount}/data/${var.vault_runner_secret_name}"
}

output "attic_vault_secret_path" {
  description = "Vault secret path Attic bootstrap reads and patches."
  value       = "${var.attic_vault_secret_mount}/data/${var.attic_vault_secret_name}"
}
