# Shared config included by every generated unit: remote state + the Teleport
# provider (identical for all units). The AWS provider is generated per-unit in
# units/ara-region/terragrunt.hcl because it needs the unit's region + account.
#
# Values below come from env vars so nothing secret is committed. Set:
#   TG_STATE_BUCKET, TG_STATE_REGION, TG_STATE_LOCK_TABLE  (remote state)
#   TELEPORT_ADDR                                          (proxy address)
# and place the provider identity file + CA bundle at the repo root (see README).

locals {
  teleport_addr     = get_env("TELEPORT_ADDR", "teleport.example.com:443")
  teleport_identity = "${get_repo_root()}/identity"

  # State backend: S3 when TG_STATE_BUCKET is set; otherwise local state files
  # (handy for a first test without provisioning a bucket/lock table).
  state_bucket     = get_env("TG_STATE_BUCKET", "")
  state_region     = get_env("TG_STATE_REGION", "us-east-1")
  state_lock_table = get_env("TG_STATE_LOCK_TABLE", "terraform-locks")
  use_local_state  = local.state_bucket == ""
}

remote_state {
  backend = local.use_local_state ? "local" : "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = local.use_local_state ? {
    path = "${get_terragrunt_dir()}/terraform.tfstate"
    } : {
    bucket         = local.state_bucket
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = local.state_region
    encrypt        = true
    dynamodb_table = local.state_lock_table
  }
}

generate "provider_teleport" {
  path      = "provider_teleport.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "teleport" {
      addr               = "${local.teleport_addr}"
      identity_file_path = "${local.teleport_identity}"
    }
  EOF
}
