# Reusable unit template: one AWS account/region of Roles Anywhere + its Teleport
# integration. Instantiated by `unit` blocks in a live/<env>/terragrunt.stack.hcl,
# which supply the per-instance `values` (account, region, deployer role, role ARNs).

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}//modules/ara-region"
}

# The target IAM roles are global and created once per account (in the first
# region's unit). When this unit only references those roles, wait for the
# creator unit so the roles exist before this region's RA profiles point at
# them. An empty path (the creator unit, or accounts that reference existing
# roles) imposes no ordering, keeping `run --all` parallel across accounts.
dependencies {
  paths = values.roles_unit_path != "" ? [values.roles_unit_path] : []
}

# AWS provider for this unit's account + region. Two auth modes per account
# (set in inventory.yaml): aws_profile → use that named profile (static keys via
# a credentials file); otherwise assume_role into the deployer role. Neither the
# keys nor the role ARN end up committed (this file is generated under
# .terragrunt-stack/, which is gitignored).
generate "provider_aws" {
  path      = "provider_aws.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "aws" {
      region              = "${values.region}"
      allowed_account_ids = ["${values.account_id}"]
      ${values.aws_profile != "" ? "profile = \"${values.aws_profile}\"" : "assume_role { role_arn = \"${values.deployer_role_arn}\" }"}
    }
  EOF
}

inputs = {
  name_prefix         = "teleport"
  account_id          = values.account_id
  region              = values.region
  integration_key     = values.unit_name
  create_target_roles = values.create_target_roles
  target_roles        = values.target_roles

  teleport_ca_pem = file("${get_repo_root()}/teleport-awsra-ca.pem")

  # One profile-sync IAM role per account/region. IAM roles are global, so the
  # name is region-suffixed to avoid collisions; this keeps units independent
  # (no cross-unit dependency) for parallel `run --all`.
  profile_sync_role_name = "teleport-profile-sync-${values.region}"

  labels = { account = values.account_name }
}
