terraform {
  required_providers {
    teleport = {
      source = "terraform.releases.teleport.dev/gravitational/teleport"
      # Pin to your cluster's major version, e.g. "~> 18.0".
      version = ">= 18.0"
    }
  }
}

# One integration per account. Single Teleport provider, for_each over accounts —
# this is the "pass many accounts into one module" piece.
resource "teleport_integration" "aws_ra" {
  for_each = var.accounts

  version  = "v1"
  sub_kind = "aws-ra"

  metadata = {
    name        = "${var.name_prefix}-${each.key}"
    description = each.value.description
    labels      = each.value.labels
  }

  spec = {
    aws_ra = {
      trust_anchor_arn = each.value.trust_anchor_arn
      profile_sync_config = {
        enabled                           = each.value.sync_enabled
        profile_arn                       = each.value.profile_arn
        role_arn                          = each.value.role_arn
        profile_accepts_role_session_name = each.value.accept_role_session_name
        profile_name_filters              = each.value.profile_name_filters
      }
    }
  }
}
