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
