locals {
  runner_name_override  = var.runner_name == null ? null : trimspace(var.runner_name)
  effective_runner_name = coalesce(local.runner_name_override, random_pet.runner_name[0].id)
  runner_labels         = distinct(concat(["hetzner", "arm64", "cache"], var.runner_labels))
  runner_url            = format("https://github.com/%s/%s", var.github_owner, var.github_repository)
  attic_public_endpoint = format("https://%s", var.attic_domain)
  tunnel_name           = coalesce(var.cloudflare_tunnel_name, local.effective_runner_name)
  bucket_name           = coalesce(var.r2_bucket_name, format("attic-%s", random_id.attic_bucket_suffix[0].hex))
  server_ssh_keys        = length(var.hcloud_existing_ssh_key_names) > 0 ? var.hcloud_existing_ssh_key_names : [for key in hcloud_ssh_key.runner : key.id]
  attic_env_file_content = join("\n", [
    format("ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=%s", base64encode(tls_private_key.attic_signing[0].private_key_pem)),
  ])
  cloudflare_tunnel_credentials_json = jsonencode({
    AccountTag   = var.cloudflare_account_id
    TunnelSecret = random_id.cloudflare_tunnel_secret[0].b64_std
    TunnelID     = cloudflare_zero_trust_tunnel_cloudflared.attic[0].id
  })
  generated_host_config_json = jsonencode({
    runner = {
      group  = var.github_runner_group
      labels = local.runner_labels
      name   = local.effective_runner_name
      url    = local.runner_url
    }
    ssh = {
      authorizedKeys = var.ssh_authorized_keys
    }
    attic = {
      cacheName      = var.attic_cache_name
      cachePriority  = var.attic_cache_priority
      domain         = var.attic_domain
      localPort      = var.attic_local_port
      public         = var.attic_cache_public
      publicEndpoint = local.attic_public_endpoint
      r2 = {
        accessKeyId     = cloudflare_account_token.attic_r2[0].id
        accountId       = var.cloudflare_account_id
        bucket          = cloudflare_r2_bucket.attic[0].id
        secretAccessKey = sha256(cloudflare_account_token.attic_r2[0].value)
      }
    }
    cloudflareTunnel = {
      id = cloudflare_zero_trust_tunnel_cloudflared.attic[0].id
    }
  })
  install_trigger = sha256(jsonencode({
    generated_host_config = local.generated_host_config_json
    attic_env             = sha256(local.attic_env_file_content)
    tunnel_credentials    = sha256(local.cloudflare_tunnel_credentials_json)
    host_nix              = filesha256("${path.module}/nixos/host.nix")
    disko_nix             = filesha256("${path.module}/nixos/disko.nix")
    flake_nix             = filesha256("${path.module}/flake.nix")
  }))
}

resource "random_pet" "runner_name" {
  count = var.runner_enabled && local.runner_name_override == null ? 1 : 0

  prefix    = "github-runner"
  separator = "-"
  length    = 2
}

resource "random_id" "attic_bucket_suffix" {
  count = var.runner_enabled && var.r2_bucket_name == null ? 1 : 0

  byte_length = 4
}

resource "random_id" "cloudflare_tunnel_secret" {
  count = var.runner_enabled ? 1 : 0

  byte_length = 32
}

resource "tls_private_key" "attic_signing" {
  count = var.runner_enabled ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 2048
}

data "cloudflare_account_api_token_permission_groups_list" "r2_write" {
  count = var.runner_enabled ? 1 : 0

  account_id = var.cloudflare_account_id
  name       = "Workers R2 Storage Write"
}

resource "hcloud_ssh_key" "runner" {
  for_each = var.runner_enabled && length(var.hcloud_existing_ssh_key_names) == 0 ? { for idx, key in var.ssh_authorized_keys : idx => key } : {}

  name       = "${local.effective_runner_name}-${each.key}"
  public_key = each.value
}

resource "hcloud_firewall" "runner" {
  count = var.runner_enabled ? 1 : 0

  name = "${local.effective_runner_name}-fw"

  dynamic "rule" {
    for_each = length(var.admin_cidrs) > 0 ? [var.admin_cidrs] : []

    content {
      direction  = "in"
      protocol   = "tcp"
      port       = "22"
      source_ips = rule.value
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

resource "hcloud_server" "runner" {
  count = var.runner_enabled ? 1 : 0

  name        = local.effective_runner_name
  location    = var.hcloud_location
  server_type = var.hcloud_server_type
  image       = var.hcloud_image

  delete_protection = false

  ssh_keys = local.server_ssh_keys

  firewall_ids = [hcloud_firewall.runner[0].id]

  labels = {
    managed_by = "terraform"
    workload   = "github-runner"
    provider   = "hetzner"
    role       = "build-cache"
  }

  user_data = <<-EOT
    #cloud-config
    package_update: false
  EOT

  lifecycle {
    precondition {
      condition     = length(var.github_owner) > 0 && length(var.github_repository) > 0
      error_message = "github_owner and github_repository must both be set when runner_enabled is true."
    }
  }
}

resource "cloudflare_r2_bucket" "attic" {
  count = var.runner_enabled ? 1 : 0

  account_id    = var.cloudflare_account_id
  location      = var.r2_location
  name          = local.bucket_name
  storage_class = var.r2_storage_class
}

resource "cloudflare_account_token" "attic_r2" {
  count = var.runner_enabled ? 1 : 0

  account_id = var.cloudflare_account_id
  name       = format("%s-r2", local.effective_runner_name)

  policies = [{
    effect = "allow"
    permission_groups = [{
      id = data.cloudflare_account_api_token_permission_groups_list.r2_write[0].result[0].id
    }]
    resources = jsonencode({
      "com.cloudflare.api.account.${var.cloudflare_account_id}" = "*"
    })
  }]
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "attic" {
  count = var.runner_enabled ? 1 : 0

  account_id    = var.cloudflare_account_id
  config_src    = "local"
  name          = local.tunnel_name
  tunnel_secret = random_id.cloudflare_tunnel_secret[0].b64_std
}

resource "cloudflare_dns_record" "attic" {
  count = var.runner_enabled ? 1 : 0

  zone_id = var.cloudflare_zone_id
  name    = var.attic_domain
  type    = "CNAME"
  ttl     = 1
  proxied = true
  content = format("%s.cfargotunnel.com", cloudflare_zero_trust_tunnel_cloudflared.attic[0].id)
}

resource "null_resource" "wait_for_ubuntu" {
  count = var.runner_enabled ? 1 : 0

  triggers = {
    ipv4      = hcloud_server.runner[0].ipv4_address
    server_id = hcloud_server.runner[0].id
  }

  connection {
    host        = hcloud_server.runner[0].ipv4_address
    private_key = file(pathexpand(var.ssh_private_key_path))
    type        = "ssh"
    user        = "root"
  }

  provisioner "remote-exec" {
    inline = [
      "cloud-init status --wait || true",
    ]
  }
}

resource "null_resource" "install_nixos" {
  count = var.runner_enabled ? 1 : 0

  depends_on = [
    cloudflare_account_token.attic_r2,
    cloudflare_dns_record.attic,
    cloudflare_r2_bucket.attic,
    cloudflare_zero_trust_tunnel_cloudflared.attic,
    hcloud_server.runner,
    null_resource.wait_for_ubuntu,
    tls_private_key.attic_signing,
  ]

  triggers = {
    install = local.install_trigger
    ipv4    = hcloud_server.runner[0].ipv4_address
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/nixos-anywhere-install.sh"

    environment = {
      ATTIC_ENV_FILE_CONTENT             = local.attic_env_file_content
      CLOUDFLARE_TUNNEL_CREDENTIALS_JSON = local.cloudflare_tunnel_credentials_json
      CLOUDFLARE_TUNNEL_ID               = cloudflare_zero_trust_tunnel_cloudflared.attic[0].id
      GENERATED_CONFIG_JSON              = local.generated_host_config_json
      GITHUB_RUNNER_TOKEN                = var.github_runner_token
      INSTALL_DISK_DEVICE                = var.install_disk_device != null ? var.install_disk_device : ""
      SSH_PRIVATE_KEY_PATH               = pathexpand(var.ssh_private_key_path)
      TARGET_HOST                        = hcloud_server.runner[0].ipv4_address
    }
  }
}
