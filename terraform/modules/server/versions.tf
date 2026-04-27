terraform {
  required_providers {
    hcloud = {
      source = "hetznercloud/hcloud"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
