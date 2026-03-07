terraform {
  required_version = "~> 1.14.6"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.57"
    }
  }
  backend "s3" {
    bucket = "tf-state-bucket"
    key    = "terraform.tfstate"
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
