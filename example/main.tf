locals {
  teleport_ca_pem = file("${path.module}/teleport-awsra-ca.pem")

  # ── single source of truth for every account ──
  # Region + how to auth still live in providers.tf (provider configs can't be
  # looped); everything else about an account is here.
  accounts = {
    prod = {
      name_prefix          = "teleport"
      profile_name_filters = ["teleport-*"]
      labels               = { env = "prod" }
      target_roles = {
        readonly = { managed_policy_arns = ["arn:aws:iam::aws:policy/ReadOnlyAccess"] }
        admin    = { managed_policy_arns = ["arn:aws:iam::aws:policy/AdministratorAccess"] }
      }
    }
    staging = {
      name_prefix          = "teleport"
      profile_name_filters = ["teleport-*"]
      labels               = { env = "staging" }
      target_roles = {
        readonly = { managed_policy_arns = ["arn:aws:iam::aws:policy/ReadOnlyAccess"] }
      }
    }
  }
}

# --- AWS side: one thin module call per account, each bound to its provider --
# The block can't be for_each'd (distinct provider per instance), but the values
# all come from local.accounts, so adding an account = a provider block + this
# 5-line skeleton + a local.accounts entry.
module "aws_prod" {
  source          = "../modules/aws-account"
  providers       = { aws = aws.prod }
  teleport_ca_pem = local.teleport_ca_pem
  name_prefix     = local.accounts["prod"].name_prefix
  target_roles    = local.accounts["prod"].target_roles
}

module "aws_staging" {
  source          = "../modules/aws-account"
  providers       = { aws = aws.staging }
  teleport_ca_pem = local.teleport_ca_pem
  name_prefix     = local.accounts["staging"].name_prefix
  target_roles    = local.accounts["staging"].target_roles
}

# --- Teleport side: single module, for_each over all accounts --------------
# Merge each AWS module's outputs with that account's prefs from local.accounts.
module "teleport_integrations" {
  source = "../modules/teleport-integrations"

  accounts = {
    for k, m in { prod = module.aws_prod, staging = module.aws_staging } :
    k => merge(m.integration_input, {
      profile_name_filters = local.accounts[k].profile_name_filters
      labels               = local.accounts[k].labels
    })
  }
}

output "integrations" {
  value = module.teleport_integrations.integration_names
}

output "target_roles" {
  value = {
    prod    = module.aws_prod.target_role_arns
    staging = module.aws_staging.target_role_arns
  }
}

output "target_profiles" {
  value = {
    prod    = module.aws_prod.target_profile_arns
    staging = module.aws_staging.target_profile_arns
  }
}
