locals {
  github_owner_effective = coalesce(var.github_owner, "")
  target_repositories    = distinct(compact(concat(var.github_repository == null ? [] : [var.github_repository], var.github_repositories)))
  repository_suffix      = length(local.target_repositories) > 0 ? local.target_repositories[0] : local.github_owner_effective
  effective_runner_name  = coalesce(var.runner_name, "${local.repository_suffix}-hetzner-arm")
  runner_arch            = "arm64"
  runner_labels          = distinct(concat(["hetzner", "arm64", "build", "cache"], var.runner_labels))
  runner_url             = var.registration_scope == "organization" ? "https://github.com/${local.github_owner_effective}" : "https://github.com/${local.github_owner_effective}/${local.repository_suffix}"

  bootstrap_registration_token = var.registration_mode == "github-provider" && var.registration_scope == "organization" ? data.github_actions_organization_registration_token.organization[0].token : null
  repository_registration_tokens = var.registration_mode == "github-provider" && var.registration_scope == "repository" ? {
    for repo, token_data in data.github_actions_registration_token.repository : repo => token_data.token
  } : {}
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
  }
}

resource "hcloud_volume_attachment" "cache" {
  count = var.runner_enabled ? 1 : 0

  server_id = hcloud_server.runner[0].id
  volume_id = hcloud_volume.cache[0].id
  automount = true
}

resource "vault_policy" "runner_bootstrap" {
  count = var.enable_vault_bootstrap_policy ? 1 : 0

  name = "github-runner-bootstrap"

  policy = <<-EOT
    path "${var.vault_runner_secret_mount}/data/${var.vault_runner_secret_name}" {
      capabilities = ["read"]
    }
  EOT
}
