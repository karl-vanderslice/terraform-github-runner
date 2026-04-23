terraform {
  required_version = ">= 1.6.0"

  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.11"
    }

    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.47"
    }

    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.9"
    }
  }
}

provider "github" {
  owner = coalesce(var.github_owner, "")
}

provider "hcloud" {
  token = coalesce(var.hcloud_token, "")
}

provider "vault" {
  address   = coalesce(var.vault_addr, "")
  namespace = var.vault_namespace
}
