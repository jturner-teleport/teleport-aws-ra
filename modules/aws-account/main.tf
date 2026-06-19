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
  account_id = data.aws_caller_identity.current.account_id
}

# ---------------------------------------------------------------------------
# Trust anchor: tells AWS to trust certificates issued by the Teleport CA.
# One per account.
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
# Profile-sync IAM role. Teleport assumes this (via Roles Anywhere) to list
# the account's profiles and import them as Teleport apps.
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
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_rolesanywhere_trust_anchor.this.arn]
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

resource "aws_iam_role" "profile_sync" {
  name               = "${var.name_prefix}-profile-sync"
  assume_role_policy = data.aws_iam_policy_document.ra_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "profile_sync" {
  name   = "profile-sync"
  role   = aws_iam_role.profile_sync.id
  policy = data.aws_iam_policy_document.profile_sync.json
}

resource "aws_iam_role_policy_attachment" "profile_sync_extra" {
  for_each   = toset(var.profile_sync_managed_policy_arns)
  role       = aws_iam_role.profile_sync.name
  policy_arn = each.value
}

# ---------------------------------------------------------------------------
# Target roles users will actually assume. Same Roles Anywhere trust policy.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "target" {
  for_each             = var.target_roles
  name                 = "${var.name_prefix}-${each.key}"
  assume_role_policy   = data.aws_iam_policy_document.ra_assume.json
  max_session_duration = each.value.max_session_seconds
  tags                 = var.tags
}

resource "aws_iam_role_policy_attachment" "target_managed" {
  for_each = merge([
    for role_key, cfg in var.target_roles : {
      for arn in cfg.managed_policy_arns : "${role_key}::${arn}" => {
        role = role_key
        arn  = arn
      }
    }
  ]...)

  role       = aws_iam_role.target[each.value.role].name
  policy_arn = each.value.arn
}

resource "aws_iam_role_policy" "target_inline" {
  for_each = { for k, v in var.target_roles : k => v if v.inline_policy_json != null }
  name     = "inline"
  role     = aws_iam_role.target[each.key].id
  policy   = each.value.inline_policy_json
}

# ---------------------------------------------------------------------------
# Profile-sync profile: the profile Teleport authenticates *as* in order to
# run the sync. Its session policy is scoped to the sync role above.
# ---------------------------------------------------------------------------
resource "aws_rolesanywhere_profile" "sync" {
  name                     = "${var.name_prefix}-profile-sync"
  enabled                  = true
  role_arns                = [aws_iam_role.profile_sync.arn]
  accept_role_session_name = false
  tags                     = var.tags
}

# ---------------------------------------------------------------------------
# Access profiles: one Roles Anywhere profile per target role. Teleport's
# profile sync imports each of these as an AWS app (the sync profile above is
# NOT surfaced as an app), and the role listed here becomes assumable through
# it. Names share the prefix so they match the integration's profile_name_filters.
# accept_role_session_name = true lets Teleport stamp the username as the role
# session name for audit.
# ---------------------------------------------------------------------------
resource "aws_rolesanywhere_profile" "target" {
  for_each                 = var.target_roles
  name                     = "${var.name_prefix}-${each.key}"
  enabled                  = true
  role_arns                = [aws_iam_role.target[each.key].arn]
  accept_role_session_name = true
  # access-level tag: the role key (readonly/admin/...). If Teleport imports RA
  # profile tags as app labels, this gives a stable label to scope Teleport
  # roles on (vs. the generated profile ARN).
  tags = merge(var.tags, { "access-level" = each.key })
}
