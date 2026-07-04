terraform {
  # Minimum OpenTofu version — ensures we have support for the features we use
  required_version = ">= 1.6"

  required_providers {
    # Hetzner Cloud provider — used to manage all Hetzner resources (servers,
    # networks, firewalls, SSH keys)
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.49"
    }
  }

  # Remote state backend using Hetzner Object Storage (S3-compatible).
  # Storing state remotely means multiple machines can run tofu commands
  # without stepping on each other, and state is not lost if the local
  # machine is wiped.
  backend "s3" {
    bucket = "gihc-tofu-state"
    key    = "platform/terraform.tfstate"

    # Hetzner Object Storage S3-compatible endpoint (Helsinki region)
    endpoints = {
      s3 = "https://hel1.your-objectstorage.com"
    }

    region = "hel1"

    # Credentials are set via environment variables so they are never
    # committed to the repository:
    #   AWS_ACCESS_KEY_ID
    #   AWS_SECRET_ACCESS_KEY

    # These options disable AWS-specific validation that does not apply to
    # Hetzner Object Storage
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    use_path_style              = true
  }
}

provider "hcloud" {
  # The Hetzner API token is read from the HCLOUD_TOKEN environment variable.
  # It is set automatically by direnv via tofu/.envrc (which is gitignored).
  #
  # IMPORTANT: Hetzner Cloud does not support specifying a project directly in
  # the provider configuration. Resources are created in whichever project the
  # API token belongs to. The token used here must belong to the "GIHC" project
  # in the Hetzner Cloud Console — using a token from a different project will
  # silently create resources in the wrong project.
  #
  # To generate a token for the correct project:
  #   Hetzner Cloud Console → GIHC project → Security → API Tokens → Generate API Token
  #
  # Note: TF_VAR_hcloud_token does NOT work with this provider — use HCLOUD_TOKEN.
}
