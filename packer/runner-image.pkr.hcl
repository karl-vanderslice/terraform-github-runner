packer {
  required_plugins {
    oracle = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/oracle"
    }
    ansible = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/ansible"
    }
  }
}

variable "availability_domain" {
  type = string
}

variable "compartment_ocid" {
  type = string
}

variable "fingerprint" {
  type = string
}

variable "private_key_path" {
  type = string
}

variable "region" {
  type    = string
  default = "us-ashburn-1"
}

variable "shape" {
  type    = string
  default = "VM.Standard.A1.Flex"
}

variable "subnet_ocid" {
  type = string
}

variable "tenancy_ocid" {
  type = string
}

variable "user_ocid" {
  type = string
}

source "oracle-oci" "runner" {
  availability_domain = var.availability_domain
  compartment_ocid    = var.compartment_ocid
  region              = var.region
  shape               = var.shape
  subnet_ocid         = var.subnet_ocid

  base_image_filter {
    filters = {
      operating_system         = "Canonical Ubuntu"
      operating_system_version = "24.04"
    }
  }

  image_name = "gha-runner-base-{{ isotime \"20060102-1504\" }}"

  # OCI API auth
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
}

build {
  name    = "oci-runner-base"
  sources = ["source.oracle-oci.runner"]

  provisioner "ansible" {
    playbook_file = "ansible/runner-image.yml"
  }
}
