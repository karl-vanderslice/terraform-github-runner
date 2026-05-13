locals {
  github_owner_effective   = coalesce(var.github_owner, "")
  target_repositories      = distinct(compact(concat(var.github_repository == null ? [] : [var.github_repository], var.github_repositories)))
  repository_suffix        = length(local.target_repositories) > 0 ? local.target_repositories[0] : local.github_owner_effective
  runner_name_override     = var.runner_name == null ? null : (length(trimspace(var.runner_name)) > 0 ? trimspace(var.runner_name) : null)
  effective_runner_name    = coalesce(local.runner_name_override, random_pet.runner_name[0].id)
  server_arch              = startswith(var.hcloud_server_type, "ca") ? "arm64" : "x64"
  runner_arch              = local.server_arch
  runner_labels            = distinct(concat(["hetzner", local.server_arch, "build", "cache"], var.runner_labels))
  runner_url               = var.registration_scope == "organization" ? "https://github.com/${local.github_owner_effective}" : "https://github.com/${local.github_owner_effective}/${local.repository_suffix}"
  attic_https_enabled      = var.attic_enabled && var.attic_endpoint_scheme == "https"
  attic_origin_tls_enabled = local.attic_https_enabled && var.cloudflare_attic_proxied && var.attic_tls_mode == "cloudflare-origin-ca"
  attic_default_port       = (var.attic_endpoint_scheme == "http" && var.attic_port == 80) || (var.attic_endpoint_scheme == "https" && var.attic_port == 443)
  attic_hostport           = local.attic_default_port ? var.attic_domain : format("%s:%d", var.attic_domain, var.attic_port)
  attic_endpoint           = format("%s://%s/", var.attic_endpoint_scheme, local.attic_hostport)
  effective_ssh_edge_cidrs = var.github_actions_ssh_ingress_enabled ? ["0.0.0.0/0", "::/0"] : var.admin_cidrs
  effective_attic_ingress_cidrs = length(var.attic_ingress_cidrs) > 0 ? var.attic_ingress_cidrs : concat(
    try(data.cloudflare_ip_ranges.cloudflare[0].ipv4_cidrs, []),
    try(data.cloudflare_ip_ranges.cloudflare[0].ipv6_cidrs, []),
  )
  effective_attic_ingress_ports = var.attic_enabled ? toset(compact([
    tostring(var.attic_port),
    var.cloudflare_attic_proxied && var.attic_port != 80 ? "80" : null,
  ])) : toset([])

  bootstrap_registration_token = var.registration_mode == "github-provider" && var.registration_scope == "organization" ? data.github_actions_organization_registration_token.organization[0].token : null
  repository_registration_tokens = var.registration_mode == "github-provider" && var.registration_scope == "repository" ? {
    for repo, token_data in data.github_actions_registration_token.repository : repo => token_data.token
  } : {}
  vault_bootstrap_token_set             = var.vault_bootstrap_token != null && length(trimspace(var.vault_bootstrap_token)) > 0
  vault_auth_mount_set                  = var.vault_auth_mount != null && length(trimspace(var.vault_auth_mount)) > 0
  vault_admin_automation_role_id_set    = var.vault_admin_automation_role_id != null && length(trimspace(var.vault_admin_automation_role_id)) > 0
  vault_admin_automation_secret_id_set  = var.vault_admin_automation_secret_id != null && length(trimspace(var.vault_admin_automation_secret_id)) > 0
  vault_approle_enabled                 = local.vault_auth_mount_set && local.vault_admin_automation_role_id_set && local.vault_admin_automation_secret_id_set
  vault_approle_partially_configured    = (local.vault_auth_mount_set || local.vault_admin_automation_role_id_set || local.vault_admin_automation_secret_id_set) && !local.vault_approle_enabled
}

resource "random_pet" "runner_name" {
  count = var.runner_enabled && local.runner_name_override == null ? 1 : 0

  prefix    = "github-runner"
  separator = "-"
  length    = 2
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

data "cloudflare_ip_ranges" "cloudflare" {
  count = var.attic_enabled ? 1 : 0
}

resource "tls_private_key" "attic_origin" {
  count = local.attic_origin_tls_enabled ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "attic_origin" {
  count = local.attic_origin_tls_enabled ? 1 : 0

  private_key_pem = tls_private_key.attic_origin[0].private_key_pem
  dns_names       = [var.attic_domain]

  subject {
    common_name = var.attic_domain
  }
}

resource "cloudflare_origin_ca_certificate" "attic" {
  count = local.attic_origin_tls_enabled ? 1 : 0

  csr                = tls_cert_request.attic_origin[0].cert_request_pem
  hostnames          = [var.attic_domain]
  request_type       = "origin-rsa"
  requested_validity = 5475
}

data "github_actions_organization_registration_token" "organization" {
  count = var.runner_enabled && var.registration_mode == "github-provider" && var.registration_scope == "organization" ? 1 : 0
}

data "github_actions_registration_token" "repository" {
  for_each = var.runner_enabled && var.registration_mode == "github-provider" && var.registration_scope == "repository" ? toset(local.target_repositories) : toset([])

  repository = each.value
}

resource "hcloud_ssh_key" "runner" {
  for_each = var.runner_enabled ? { for idx, key in var.ssh_authorized_keys : idx => key } : {}

  name       = "${local.effective_runner_name}-${each.key}"
  public_key = each.value
}

resource "hcloud_firewall" "runner" {
  count = var.runner_enabled ? 1 : 0

  name = "${local.effective_runner_name}-fw"

  dynamic "rule" {
    for_each = length(local.effective_ssh_edge_cidrs) > 0 ? [local.effective_ssh_edge_cidrs] : []

    content {
      direction  = "in"
      protocol   = "tcp"
      port       = "22"
      source_ips = rule.value
    }
  }

  dynamic "rule" {
    for_each = local.effective_attic_ingress_ports

    content {
      direction  = "in"
      protocol   = "tcp"
      port       = tostring(rule.value)
      source_ips = local.effective_attic_ingress_cidrs
    }
  }

  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "1-65535"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction       = "out"
    protocol        = "udp"
    port            = "1-65535"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction       = "out"
    protocol        = "icmp"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }
}

resource "hcloud_volume" "cache" {
  count = var.runner_enabled ? 1 : 0

  name     = "${local.effective_runner_name}-cache"
  size     = var.hcloud_volume_size_gb
  location = var.hcloud_location
  format   = "ext4"
}

resource "hcloud_volume" "workspace" {
  count = var.runner_enabled && var.workspace_volume_size_gb > 0 ? 1 : 0

  name     = "${local.effective_runner_name}-workspace"
  size     = var.workspace_volume_size_gb
  location = var.hcloud_location
  format   = "ext4"
}

resource "hcloud_server" "runner" {
  count = var.runner_enabled ? 1 : 0

  name        = local.effective_runner_name
  location    = var.hcloud_location
  server_type = var.hcloud_server_type
  image       = var.hcloud_image

  delete_protection = false

  ssh_keys = [for key in hcloud_ssh_key.runner : key.id]

  firewall_ids = [hcloud_firewall.runner[0].id]

  labels = {
    managed_by = "terraform"
    workload   = "github-runner"
    provider   = "hetzner"
    role       = "build-cache"
  }

  user_data = templatefile("${path.module}/templates/runner-cloud-init.yaml.tftpl", {
    runner_url                        = local.runner_url
    runner_name                       = local.effective_runner_name
    runner_group                      = var.github_runner_group
    runner_labels_csv                 = join(",", local.runner_labels)
    runner_ephemeral                  = var.runner_ephemeral
    runner_image_family               = var.runner_image_family
    registration_mode                 = var.registration_mode
    registration_tokens_json          = jsonencode(local.repository_registration_tokens)
    registration_token                = coalesce(local.bootstrap_registration_token, "unused")
    actions_runner_version            = var.actions_runner_version
    actions_runner_arch               = local.runner_arch
    vault_version                     = "1.18.3"
    vault_addr                        = var.vault_addr == null ? "" : var.vault_addr
    vault_namespace                   = var.vault_namespace
    vault_bootstrap_token             = var.vault_bootstrap_token == null ? "" : var.vault_bootstrap_token
    vault_auth_mount                  = var.vault_auth_mount == null ? "" : var.vault_auth_mount
    vault_admin_automation_role_id    = var.vault_admin_automation_role_id == null ? "" : var.vault_admin_automation_role_id
    vault_admin_automation_secret_id  = var.vault_admin_automation_secret_id == null ? "" : var.vault_admin_automation_secret_id
    vault_runner_secret_mount         = var.vault_runner_secret_mount
    vault_runner_secret_name          = var.vault_runner_secret_name
    vault_runner_secret_key           = var.vault_runner_secret_key
    registration_scope                = var.registration_scope
    github_owner                      = var.github_owner
    github_repository                 = var.github_repository == null ? "" : var.github_repository
    github_repositories_csv           = join(",", local.target_repositories)
    admin_cidrs_json                  = jsonencode(var.admin_cidrs)
    github_actions_ssh_ingress_enabled = var.github_actions_ssh_ingress_enabled
    cache_volume_id                   = hcloud_volume.cache[0].id
    cache_volume_name                 = hcloud_volume.cache[0].name
    workspace_volume_id               = var.workspace_volume_size_gb > 0 ? hcloud_volume.workspace[0].id : ""
    workspace_volume_name             = var.workspace_volume_size_gb > 0 ? hcloud_volume.workspace[0].name : ""
    workspace_mount_path              = var.workspace_mount_path
    attic_enabled                     = var.attic_enabled
    attic_domain                      = var.attic_domain
    attic_endpoint_scheme             = var.attic_endpoint_scheme
    attic_endpoint                    = local.attic_endpoint
    attic_origin_tls_enabled          = local.attic_origin_tls_enabled
    attic_origin_tls_certificate      = local.attic_origin_tls_enabled ? cloudflare_origin_ca_certificate.attic[0].certificate : ""
    attic_origin_tls_private_key      = local.attic_origin_tls_enabled ? tls_private_key.attic_origin[0].private_key_pem : ""
    attic_port                        = var.attic_port
    attic_internal_port               = var.attic_internal_port
    attic_cache_name                  = var.attic_cache_name
    attic_cache_public                = var.attic_cache_public
    attic_cache_priority              = var.attic_cache_priority
    attic_ci_token_validity           = var.attic_ci_token_validity
    attic_pull_token_validity         = var.attic_pull_token_validity
    attic_vault_secret_mount          = var.attic_vault_secret_mount
    attic_vault_secret_name           = var.attic_vault_secret_name
    attic_vault_secret_key            = var.attic_vault_secret_key
    crowdsec_enabled                  = var.crowdsec_enabled
    crowdsec_lapi_port                = var.crowdsec_lapi_port
    crowdsec_firewall_bouncer_enabled = var.crowdsec_firewall_bouncer_enabled
  })

  lifecycle {
    ignore_changes = [user_data]

    precondition {
      condition     = !(var.registration_scope == "repository" && length(local.target_repositories) == 0)
      error_message = "At least one repository must be configured in github_repository or github_repositories when registration_scope is repository."
    }

    precondition {
      condition     = !(length(local.effective_ssh_edge_cidrs) > 0 && length(var.ssh_authorized_keys) == 0 && var.runner_image_family != "nixos")
      error_message = "ssh_authorized_keys must include at least one key when admin_cidrs allows SSH ingress unless the NixOS runner image already bakes in management keys."
    }

    precondition {
      condition     = !(var.github_actions_ssh_ingress_enabled && var.runner_image_family != "nixos")
      error_message = "github_actions_ssh_ingress_enabled currently requires runner_image_family = nixos so the host can enforce the large GitHub Actions CIDR set locally with nftables."
    }

    precondition {
      condition     = !(var.registration_mode == "vault-token" && var.vault_addr == null)
      error_message = "vault_addr must be set when registration_mode is vault-token."
    }

    precondition {
      condition     = !local.vault_approle_partially_configured
      error_message = "vault_auth_mount, vault_admin_automation_role_id, and vault_admin_automation_secret_id must be set together when using AppRole bootstrap."
    }

    precondition {
      condition     = !(var.registration_mode == "vault-token" && !(local.vault_bootstrap_token_set || local.vault_approle_enabled))
      error_message = "vault-token mode requires either vault_bootstrap_token or a complete AppRole configuration."
    }

    precondition {
      condition     = !(var.runner_ephemeral && var.registration_mode != "vault-token")
      error_message = "runner_ephemeral requires registration_mode = vault-token so the host can mint a fresh registration token for every runner restart."
    }

    precondition {
      condition     = !(var.attic_enabled && var.runner_image_family != "nixos")
      error_message = "attic_enabled requires runner_image_family = nixos so the host image provides atticd and atticadm."
    }

    precondition {
      condition     = !(var.attic_enabled && var.workspace_volume_size_gb == 0)
      error_message = "attic_enabled requires workspace_volume_size_gb > 0 for durable Attic storage."
    }

    precondition {
      condition     = !(var.attic_enabled && var.vault_addr == null)
      error_message = "vault_addr must be set when attic_enabled is true."
    }

    precondition {
      condition     = !(var.attic_enabled && !(local.vault_bootstrap_token_set || local.vault_approle_enabled))
      error_message = "attic_enabled requires either vault_bootstrap_token or a complete AppRole configuration."
    }

    precondition {
      condition     = !(var.attic_enabled && var.crowdsec_enabled && var.crowdsec_lapi_port == var.attic_internal_port)
      error_message = "crowdsec_lapi_port must differ from attic_internal_port when CrowdSec and Attic are enabled together."
    }

    precondition {
      condition     = !(var.attic_enabled && length(local.effective_attic_ingress_cidrs) == 0)
      error_message = "Attic ingress must resolve to at least one CIDR when attic_enabled is true."
    }

    precondition {
      condition     = !(var.attic_enabled && var.cloudflare_attic_proxied && var.attic_endpoint_scheme != "https")
      error_message = "Cloudflare-proxied Attic ingress requires attic_endpoint_scheme = https so the origin can serve TLS explicitly."
    }

    precondition {
      condition     = !(var.attic_enabled && var.attic_tls_mode == "cloudflare-origin-ca" && !var.cloudflare_attic_proxied)
      error_message = "attic_tls_mode = cloudflare-origin-ca requires cloudflare_attic_proxied = true."
    }
  }
}

resource "hcloud_volume_attachment" "cache" {
  count = var.runner_enabled ? 1 : 0

  server_id = hcloud_server.runner[0].id
  volume_id = hcloud_volume.cache[0].id
  automount = true
}

resource "hcloud_volume_attachment" "workspace" {
  count = var.runner_enabled && var.workspace_volume_size_gb > 0 ? 1 : 0

  server_id = hcloud_server.runner[0].id
  volume_id = hcloud_volume.workspace[0].id
  automount = true
}

resource "cloudflare_dns_record" "attic" {
  count = var.attic_enabled && var.cloudflare_attic_dns_enabled ? 1 : 0

  zone_id = var.cloudflare_zone_id
  name    = var.attic_domain
  type    = "A"
  ttl     = var.cloudflare_attic_ttl
  proxied = var.cloudflare_attic_proxied
  content = hcloud_server.runner[0].ipv4_address
}

resource "vault_policy" "runner_bootstrap" {
  count = var.enable_vault_bootstrap_policy ? 1 : 0

  name = "github-runner-bootstrap"

  policy = <<-EOT
    path "${var.vault_runner_secret_mount}/data/${var.vault_runner_secret_name}" {
      capabilities = ["read"]
    }

    path "${var.attic_vault_secret_mount}/data/${var.attic_vault_secret_name}" {
      capabilities = ["read", "create", "update", "patch"]
    }
  EOT
}
