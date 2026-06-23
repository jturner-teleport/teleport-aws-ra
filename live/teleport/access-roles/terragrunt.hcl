# Cluster-global Teleport access roles (one per tier). Single Teleport provider,
# applied once for the whole cluster — so this is a standalone unit, not part of a
# per-account stack. Tiers are read from inventory.yaml so role names live in one
# place. Apply with `terragrunt apply` here, or include it in a top-level run --all.

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}//modules/teleport-access-roles"
}

locals {
  inventory = yamldecode(file("${get_repo_root()}/live/inventory.yaml"))
  roles     = local.inventory.defaults.roles # { readonly = { name = "ReadOnly", ... }, ... }
}

inputs = {
  # tier => { aws_role_name } from the inventory's role definitions
  access_roles = {
    for tier, spec in local.roles : tier => { aws_role_name = spec.name }
  }

  # Default: wildcard ARNs across all accounts (scales to many accounts). To pin
  # the proof to specific accounts instead, uncomment:
  # account_ids = ["111111111111", "222222222222"]
}
