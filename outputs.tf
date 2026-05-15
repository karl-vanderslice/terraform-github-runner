output "github_repository_full_name" {
  description = "GitHub repository wired to the runner."
  value       = var.runner_enabled ? "${var.github_owner}/${var.github_repository}" : null
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

output "attic_endpoint" {
  description = "Published Attic endpoint."
  value       = var.runner_enabled ? local.attic_public_endpoint : null
}

output "attic_cache_name" {
  description = "Attic cache name created during bootstrap."
  value       = var.runner_enabled ? var.attic_cache_name : null
}

output "attic_r2_bucket_name" {
  description = "Cloudflare R2 bucket that stores Attic objects."
  value       = var.runner_enabled ? cloudflare_r2_bucket.attic[0].id : null
}

output "cloudflare_tunnel_id" {
  description = "Cloudflare Tunnel UUID used for attic.vslice.net ingress."
  value       = var.runner_enabled ? cloudflare_zero_trust_tunnel_cloudflared.attic[0].id : null
}
