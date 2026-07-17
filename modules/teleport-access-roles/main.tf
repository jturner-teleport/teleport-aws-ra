terraform {
  required_providers {
    teleport = {
      source  = "terraform.releases.teleport.dev/gravitational/teleport"
      version = ">= 18.0"
    }
  }
}

# Cluster-global Teleport access roles — one per access tier. Each matches the
# apps synced from Roles Anywhere by their aws/access-level label (set from the
# target profile's access-level tag) and allows assuming the matching AWS role.
#
# aws_role_arns uses a wildcard account (arn:aws:iam::*:role/<name>) by default so
# a single role covers every account; pin account_ids to restrict it. This relies
# on the IAM role name being identical across accounts.

locals {
  account_scope = length(var.account_ids) > 0 ? var.account_ids : ["*"]

  # Tiers that are access-requested rather than auto-granted → get a requester role.
  request_tiers = { for tier, r in var.access_roles : tier => r if r.access == "request" }

  # SAML connector attributes_to_roles: each tier's Okta group maps to the role a
  # matching user should receive — the direct access role for "direct" tiers, or
  # the requester role for "request" tiers. Only tiers with an okta_group set are
  # emitted. This is an OUTPUT to merge into your teleport_saml_connector; the
  # connector itself is intentionally not managed here (it's auth-critical).
  attributes_to_roles = [
    for tier, r in var.access_roles : {
      name  = "groups"
      value = r.okta_group
      roles = [r.access == "request" ? "${var.role_name_prefix}-request-${tier}" : "${var.role_name_prefix}-${tier}"]
    }
    if r.okta_group != ""
  ]
}

resource "teleport_role" "access" {
  for_each = var.access_roles
  version  = var.role_version

  metadata = {
    name        = "${var.role_name_prefix}-${each.key}"
    description = coalesce(each.value.description, "AWS ${each.value.aws_role_name} access via Roles Anywhere")
    labels      = var.labels
  }

  spec = {
    allow = {
      app_labels = {
        "aws/access-level" = [coalesce(each.value.access_level_label, each.key)]
      }
      aws_role_arns = [
        for account_id in local.account_scope :
        "arn:aws:iam::${account_id}:role/${each.value.aws_role_name}"
      ]
    }
  }
}

# Requester role per "request" tier: grants no access itself, only the ability to
# request the matching direct access role above. Users mapped here (via their Okta
# group) get just-in-time access on approval instead of a standing grant.
resource "teleport_role" "request" {
  for_each = local.request_tiers
  version  = var.role_version

  metadata = {
    name        = "${var.role_name_prefix}-request-${each.key}"
    description = "Request ${var.role_name_prefix}-${each.key} (AWS ${each.value.aws_role_name}) via access request"
    labels      = var.labels
  }

  spec = {
    allow = {
      request = {
        # Reference the direct role by resource so it's created first.
        roles = [teleport_role.access[each.key].metadata.name]
      }
    }
  }
}
