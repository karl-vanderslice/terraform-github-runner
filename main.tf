locals {
  github_owner_effective = coalesce(var.github_owner, "")
  target_repositories    = distinct(compact(concat(var.github_repository == null ? [] : [var.github_repository], var.github_repositories)))
  repository_suffix      = length(local.target_repositories) > 0 ? local.target_repositories[0] : local.github_owner_effective
  effective_runner_name  = coalesce(var.runner_name, "${local.repository_suffix}-hetzner-arm")
  runner_arch            = "arm64"
  runner_labels          = distinct(concat(["hetzner", "arm64", "build", "cache"], var.runner_labels))
  runner_url             = var.registration_scope == "organization" ? "https://github.com/${local.github_owner_effective}" : "https://github.com/${local.github_owner_effective}/${local.repository_suffix}"
  attic_default_port     = (var.attic_endpoint_scheme == "http" && var.attic_port == 80) || (var.attic_endpoint_scheme == "https" && var.attic_port == 443)
  attic_hostport         = local.attic_default_port ? var.attic_domain : format("%s:%d", var.attic_domain, var.attic_port)
  attic_endpoint         = format("%s://%s/", var.attic_endpoint_scheme, local.attic_hostport)

  bootstrap_registration_token = var.registration_mode == "github-provider" && var.registration_scope == "organization" ? data.github_actions_organization_registration_token.organization[0].token : null
  repository_registration_tokens = var.registration_mode == "github-provider" && var.registration_scope == "repository" ? {
    for repo, token_data in data.github_actions_registration_token.repository : repo => token_data.token
  } : {}
}

provider "cloudflare" {
  api_token = coalesce(var.cloudflare_api_token, "")
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
    for_each = var.admin_cidrs

    content {
      direction  = "in"
      protocol   = "tcp"
      port       = "22"
      source_ips = [rule.value]
    }
  }

  dynamic "rule" {
    for_each = var.attic_enabled ? [var.attic_port] : []

    content {
      direction  = "in"
      protocol   = "tcp"
      port       = tostring(rule.value)
      source_ips = var.attic_ingress_cidrs
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
    runner_url                = local.runner_url
    runner_name               = local.effective_runner_name
    runner_group              = var.github_runner_group
    runner_labels_csv         = join(",", local.runner_labels)
    runner_image_family       = var.runner_image_family
    registration_mode         = var.registration_mode
    registration_tokens_json  = jsonencode(local.repository_registration_tokens)
    registration_token        = coalesce(local.bootstrap_registration_token, "unused")
    actions_runner_version    = var.actions_runner_version
    actions_runner_arch       = local.runner_arch
    vault_version             = "1.18.3"
    vault_addr                = var.vault_addr == null ? "" : var.vault_addr
    vault_namespace           = var.vault_namespace
    vault_bootstrap_token     = var.vault_bootstrap_token == null ? "" : var.vault_bootstrap_token
    vault_runner_secret_mount = var.vault_runner_secret_mount
    vault_runner_secret_name  = var.vault_runner_secret_name
    vault_runner_secret_key   = var.vault_runner_secret_key
    registration_scope        = var.registration_scope
    github_owner              = var.github_owner
    github_repository         = var.github_repository == null ? "" : var.github_repository
    github_repositories_csv   = join(",", local.target_repositories)
    cache_volume_name         = hcloud_volume.cache[0].name
    workspace_volume_name     = var.workspace_volume_size_gb > 0 ? hcloud_volume.workspace[0].name : ""
    workspace_mount_path      = var.workspace_mount_path
    attic_enabled             = var.attic_enabled
    attic_domain              = var.attic_domain
    attic_endpoint            = local.attic_endpoint
    attic_port                = var.attic_port
    attic_cache_name          = var.attic_cache_name
    attic_cache_public        = var.attic_cache_public
    attic_cache_priority      = var.attic_cache_priority
    attic_ci_token_validity   = var.attic_ci_token_validity
    attic_pull_token_validity = var.attic_pull_token_validity
    attic_vault_secret_mount  = var.attic_vault_secret_mount
    attic_vault_secret_name   = var.attic_vault_secret_name
    attic_vault_secret_key    = var.attic_vault_secret_key
    crowdsec_enabled          = var.crowdsec_enabled
    crowdsec_lapi_port        = var.crowdsec_lapi_port
    crowdsec_firewall_bouncer_enabled = var.crowdsec_firewall_bouncer_enabled
  })

  lifecycle {
    ignore_changes = [user_data]

    precondition {
      condition     = !(var.registration_scope == "repository" && length(local.target_repositories) == 0)
      error_message = "At least one repository must be configured in github_repository or github_repositories when registration_scope is repository."
    }

    precondition {
      condition     = !(length(var.admin_cidrs) > 0 && length(var.ssh_authorized_keys) == 0)
      error_message = "ssh_authorized_keys must include at least one key when admin_cidrs allows SSH ingress."
    }

    precondition {
      condition     = !(var.registration_mode == "vault-token" && var.vault_addr == null)
      error_message = "vault_addr must be set when registration_mode is vault-token."
    }

    precondition {
      condition     = !(var.registration_mode == "vault-token" && var.vault_bootstrap_token == null)
      error_message = "vault_bootstrap_token must be set when registration_mode is vault-token."
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
      condition     = !(var.attic_enabled && var.vault_bootstrap_token == null)
      error_message = "vault_bootstrap_token must be set when attic_enabled is true."
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
