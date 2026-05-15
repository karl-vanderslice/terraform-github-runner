terraform {
  required_version = ">= 1.10.0"

  backend "remote" {}

  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.11"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.9"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }

    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.47"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "github" {
  owner = coalesce(var.github_owner, "")
  token = coalesce(var.github_runner_token, "")
}

provider "cloudflare" {
  api_token = coalesce(var.cloudflare_api_token, "")
}

provider "hcloud" {
  token = coalesce(var.hcloud_token, "")
}
