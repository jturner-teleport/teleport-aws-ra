terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  account_id            = coalesce(var.account_id, data.aws_caller_identity.current.account_id)
  sync_role_name        = coalesce(var.profile_sync_role_name, "${var.name_prefix}-profile-sync")
  profile_sync_role_arn = var.create_profile_sync_role ? aws_iam_role.profile_sync[0].arn : var.profile_sync_role_arn

  # Effective ARN per access level: the role we create, or the existing role
  # referenced by name (deterministic ARN).
  target_role_arns = {
    for k, r in var.target_roles :
    k => var.create_target_roles ? aws_iam_role.target[k].arn : "arn:aws:iam::${local.account_id}:role/${r.name}"
  }

  # Flattened (role_key, managed_policy_arn) pairs for attachment when creating.
  target_managed_attachments = {
    for pair in flatten([
      for k, cfg in var.target_roles : [
        for arn in cfg.managed_policy_arns : { key = "${k}::${arn}", role_key = k, arn = arn }
      ]
    ]) : pair.key => { role_key = pair.role_key, arn = pair.arn }
  }
}

# ---------------------------------------------------------------------------
# Trust anchor (regional): tells AWS to trust certificates issued by the
# Teleport CA. One per account/region.
# ---------------------------------------------------------------------------
resource "aws_rolesanywhere_trust_anchor" "this" {
  name    = "${var.name_prefix}-trust-anchor"
  enabled = true

  source {
    source_type = "CERTIFICATE_BUNDLE"
    source_data {
      x509_certificate_data = var.teleport_ca_pem
    }
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------
# RA assume-role trust policy, shared by the profile-sync role and any target
# roles created here. Scoped with aws:SourceAccount to THIS account, so it
# trusts the trust anchor in every region of the account.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "ra_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession", "sts:SetSourceIdentity"]
    principals {
      type        = "Service"
      identifiers = ["rolesanywhere.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

data "aws_iam_policy_document" "profile_sync" {
  statement {
    effect = "Allow"
    actions = [
      "rolesanywhere:ListProfiles",
      "rolesanywhere:GetProfile",
      "rolesanywhere:ListTagsForResource",
      "iam:GetRole",
      "iam:ListRoles",
    ]
    resources = ["*"]
  }
}

# ---------------------------------------------------------------------------
# Profile-sync role. Teleport assumes this (via Roles Anywhere) to list the
# account's profiles and import them as Teleport apps. Created here by default;
# set create_profile_sync_role = false to share one account-global role.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "profile_sync" {
  count              = var.create_profile_sync_role ? 1 : 0
  name               = local.sync_role_name
  assume_role_policy = data.aws_iam_policy_document.ra_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "profile_sync" {
  count  = var.create_profile_sync_role ? 1 : 0
  name   = "profile-sync"
  role   = aws_iam_role.profile_sync[0].id
  policy = data.aws_iam_policy_document.profile_sync.json
}

resource "aws_iam_role_policy_attachment" "profile_sync_extra" {
  for_each   = var.create_profile_sync_role ? toset(var.profile_sync_managed_policy_arns) : toset([])
  role       = aws_iam_role.profile_sync[0].name
  policy_arn = each.value
}

# ---------------------------------------------------------------------------
# Target roles — created only when create_target_roles = true (e.g. a test
# account that doesn't have them yet). They get the same RA trust policy, so
# they're usable by Roles Anywhere immediately (no separate trust step). When
# false, the roles are referenced by name and these create nothing.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "target" {
  for_each             = var.create_target_roles ? var.target_roles : {}
  name                 = each.value.name
  assume_role_policy   = data.aws_iam_policy_document.ra_assume.json
  max_session_duration = each.value.max_session_seconds
  tags                 = var.tags
}

resource "aws_iam_role_policy_attachment" "target_managed" {
  for_each   = var.create_target_roles ? local.target_managed_attachments : {}
  role       = aws_iam_role.target[each.value.role_key].name
  policy_arn = each.value.arn
}

resource "aws_iam_role_policy" "target_inline" {
  for_each = var.create_target_roles ? { for k, v in var.target_roles : k => v if v.inline_policy_json != null } : {}
  name     = "inline"
  role     = aws_iam_role.target[each.key].id
  policy   = each.value.inline_policy_json
}

# ---------------------------------------------------------------------------
# Sync profile (regional): the profile Teleport authenticates *as* to run the
# sync. NOT surfaced as an app. Scoped to the profile-sync role above.
# ---------------------------------------------------------------------------
resource "aws_rolesanywhere_profile" "sync" {
  name                     = "${var.name_prefix}-profile-sync"
  enabled                  = true
  role_arns                = [local.profile_sync_role_arn]
  accept_role_session_name = false
  tags                     = var.tags

  lifecycle {
    precondition {
      condition     = var.create_profile_sync_role || var.profile_sync_role_arn != null
      error_message = "Set profile_sync_role_arn when create_profile_sync_role = false."
    }
  }
}

# ---------------------------------------------------------------------------
# Target profiles (regional): one Roles Anywhere profile per access role. The
# access-level tag (the map key) is imported by Teleport as the aws/access-level
# app label, giving a stable label to scope Teleport roles on.
# ---------------------------------------------------------------------------
resource "aws_rolesanywhere_profile" "target" {
  for_each                 = local.target_role_arns
  name                     = "${var.name_prefix}-${each.key}"
  enabled                  = true
  role_arns                = [each.value]
  accept_role_session_name = var.accept_role_session_name
  tags                     = merge(var.tags, { "access-level" = each.key })
}
