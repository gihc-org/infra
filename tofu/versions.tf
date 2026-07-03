terraform {
  required_version = ">= 1.6"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.49"
    }
  }

  backend "s3" {
    bucket = "platform-tofu-state"
    key    = "platform/terraform.tfstate"

    endpoints = {
      s3 = "https://fsn1.your-objectstorage.com"
    }

    region = "fsn1"

    # Credentials sættes via miljøvariabler:
    #   AWS_ACCESS_KEY_ID
    #   AWS_SECRET_ACCESS_KEY

    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    force_path_style            = true
  }
}

provider "hcloud" {
  # Token læses fra HCLOUD_TOKEN miljøvariablen
}
