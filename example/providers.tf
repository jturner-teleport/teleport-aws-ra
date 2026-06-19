terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    teleport = {
      source  = "terraform.releases.teleport.dev/gravitational/teleport"
      version = ">= 18.0"
    }
  }
}

# --- Teleport provider (single) -------------------------------------------
# Auth via a tbot identity file or a short-lived `tsh`/MachineID identity.
provider "teleport" {
  addr               = var.teleport_addr # e.g. "example.teleport.sh:443"
  identity_file_path = var.teleport_identity_file
}

# --- AWS providers: ONE PER ACCOUNT ---------------------------------------
# Terraform can't for_each over provider configs, so each target account gets
# its own aliased provider. Pick ONE auth style per account:
#
#   A) Static keys (active below): a dedicated IAM user per account, keys passed
#      as sensitive vars. Independent accounts, no trust relationships needed.
#
#   B) Assume-role (commented alternative): run Terraform with base credentials
#      that can sts:AssumeRole into an admin role in each account (e.g. from an
#      org-management account). No per-account static keys to manage.
#      If you switch to B, you can drop the provider_*_key variables/tfvars.

# --- Option A: static keys (one IAM user per account) ---------------------
provider "aws" {
  alias      = "prod"
  region     = "us-east-1"
  access_key = var.provider_1_access_key
  secret_key = var.provider_1_secret_key
}

provider "aws" {
  alias      = "staging"
  region     = "us-east-1"
  access_key = var.provider_2_access_key
  secret_key = var.provider_2_secret_key
}

# --- Option B: assume-role (uncomment, and comment out Option A above) -----
# provider "aws" {
#   alias  = "prod"
#   region = "us-east-1"
#   assume_role {
#     role_arn = "arn:aws:iam::111111111111:role/TerraformAdmin"
#   }
# }
#
# provider "aws" {
#   alias  = "staging"
#   region = "us-east-1"
#   assume_role {
#     role_arn = "arn:aws:iam::222222222222:role/TerraformAdmin"
#   }
# }

# To add an account: add a provider block above and a module call in main.tf.
