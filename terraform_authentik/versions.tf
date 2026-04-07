terraform {
  required_version = "~> 1.14.6"

  required_providers {
    authentik = {
      source  = "goauthentik/authentik"
      version = "~> 2025.12.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2.0"
    }
  }

  backend "s3" {
    endpoints = {
      s3 = "https://fsn1.your-objectstorage.com"
    }

    skip_credentials_validation = true
    skip_metadata_api_check     = true
    use_path_style              = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    region                      = "eu-central"
  }
}
