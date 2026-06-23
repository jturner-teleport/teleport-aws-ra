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

# One account/region: the AWS Roles Anywhere resources plus the matching Teleport
# integration, wired together in-state. This is the unit a Terragrunt
# ara-region unit points at (one instance per account/region).

locals {
  filters = coalesce(var.profile_name_filters, ["${var.name_prefix}-*"])
}

module "aws_ra" {
  source = "../aws-ra"

  name_prefix                      = var.name_prefix
  teleport_ca_pem                  = var.teleport_ca_pem
  account_id                       = var.account_id
  create_target_roles              = var.create_target_roles
  target_roles                     = var.target_roles
  accept_role_session_name         = var.accept_role_session_name
  create_profile_sync_role         = var.create_profile_sync_role
  profile_sync_role_name           = var.profile_sync_role_name
  profile_sync_role_arn            = var.profile_sync_role_arn
  profile_sync_managed_policy_arns = var.profile_sync_managed_policy_arns
  tags                             = var.tags
}

module "teleport" {
  source      = "../teleport-integrations"
  name_prefix = var.integration_name_prefix

  accounts = {
    # Non-deterministic ARNs (trust anchor, sync profile) come straight from the
    # aws-ra module outputs in-state — no cross-state dependency needed.
    (var.integration_key) = merge(module.aws_ra.integration_input, {
      sync_enabled         = var.sync_enabled
      profile_name_filters = local.filters
      description          = var.integration_description
      labels               = merge({ region = var.region }, var.labels)
      # accept_role_session_name here describes the SYNC profile, which is
      # always false; the teleport-integrations default (false) is correct.
    })
  }
}
