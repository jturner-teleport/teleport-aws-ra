# Reusing existing IAM roles with Teleport (Roles Anywhere)

Most accounts already have the IAM roles used for human access (e.g. `ReadOnly`,
`PowerUser`, `Admin`, `User`) — typically created for Okta SAML federation. The
goal is to let Teleport grant access to **those same roles** via AWS IAM Roles
Anywhere (RA), rather than creating a parallel set of roles. One canonical set of
roles means no permission drift between an "Okta copy" and a "Teleport copy".

This is the approach we're standardizing on. It requires exactly one change to
each reused role: **add a Roles Anywhere trust statement** to the role's trust
policy.

## Why a change is needed at all

A role can only be assumed by Roles Anywhere if its trust policy (the
assume-role policy) allows the service principal `rolesanywhere.amazonaws.com`.
The existing roles trust the SAML provider (`sts:AssumeRoleWithSAML`), **not** RA,
so RA cannot assume them as-is.

A trust policy can hold multiple statements, so we **add** an RA statement
alongside the existing SAML one. Okta access is unaffected — both paths work
against the same role.

## The statement to add

For each reused role, add this statement (keep the existing SAML statement):

```json
{
  "Sid": "TeleportRolesAnywhere",
  "Effect": "Allow",
  "Principal": { "Service": "rolesanywhere.amazonaws.com" },
  "Action": [
    "sts:AssumeRole",
    "sts:TagSession",
    "sts:SetSourceIdentity"
  ],
  "Condition": {
    "StringEquals": { "aws:SourceAccount": "<ACCOUNT_ID>" }
  }
}
```

Why each piece:

- **The three `sts:*` actions** are exactly what Roles Anywhere requires to issue
  a session (per the AWS Roles Anywhere trust model).
- **`aws:SourceAccount == <ACCOUNT_ID>`** scopes the trust to RA activity
  originating from a trust anchor **in this same account**. AWS sets
  `aws:SourceArn` / `aws:SourceAccount` from the trust anchor used in the
  `CreateSession` call, and AWS explicitly recommends one of these conditions to
  prevent the confused-deputy problem.
- Using **`SourceAccount` (the account) instead of a specific trust-anchor ARN**
  means the one statement covers **every region's** trust anchor in the account.
  Since RA trust anchors are regional, accounts that span `us-east-1`,
  `us-west-2`, `eu-west-1`, etc. would otherwise need a separate statement per
  region. `SourceAccount` keeps it to a single statement per role.

### Optional: tighten to specific trust anchors

To restrict to RA anchors only (rather than any RA source in the account), use an
ARN condition instead. Use `ArnLike` (not `ArnEquals`) because the value
contains a wildcard:

```json
"ArnLike": { "aws:SourceArn": "arn:aws:rolesanywhere:*:<ACCOUNT_ID>:trust-anchor/*" }
```

This still covers all regions while excluding non-anchor sources. `SourceAccount`
is the simpler default and is sufficient for most cases.

## Full trust policy example (SAML + RA together)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "OktaSAML",
      "Effect": "Allow",
      "Principal": { "Federated": "arn:aws:iam::<ACCOUNT_ID>:saml-provider/Okta" },
      "Action": "sts:AssumeRoleWithSAML",
      "Condition": { "StringEquals": { "SAML:aud": "https://signin.aws.amazon.com/saml" } }
    },
    {
      "Sid": "TeleportRolesAnywhere",
      "Effect": "Allow",
      "Principal": { "Service": "rolesanywhere.amazonaws.com" },
      "Action": ["sts:AssumeRole", "sts:TagSession", "sts:SetSourceIdentity"],
      "Condition": { "StringEquals": { "aws:SourceAccount": "<ACCOUNT_ID>" } }
    }
  ]
}
```

(The SAML statement above is illustrative — keep whatever your account actually
has and append the RA statement.)

## How to apply it — ownership matters

The trust policy is a single document on the role (`aws_iam_role`'s
`assume_role_policy`). There is **no** separate "append a trust statement"
resource, so whoever owns the role's definition must include **both** statements.
Pick the path that matches how these roles are managed:

### 1. Roles are IaC-managed (recommended)

The team/module that owns the roles adds the RA statement to the trust policy. In
Terraform, build the document by combining the existing policy with the RA
statement:

```hcl
data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "role_trust" {
  # Existing SAML/Okta trust document for this role:
  source_policy_documents = [data.aws_iam_policy_document.okta_saml.json]

  statement {
    sid     = "TeleportRolesAnywhere"
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession", "sts:SetSourceIdentity"]
    principals {
      type        = "Service"
      identifiers = ["rolesanywhere.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

# ...assigned to the role's assume_role_policy by whoever manages the role.
```

### 2. Roles are NOT IaC-managed

Apply once with the CLI. `update-assume-role-policy` **replaces the entire
document**, so the file must include the existing SAML statement plus the new RA
statement (i.e. the full example above):

```sh
aws iam update-assume-role-policy --role-name ReadOnly \
  --policy-document file://readonly-trust.json
```

> ⚠️ Drift warning: this is a full replacement. If an account-baseline / landing-
> zone process also manages these roles, it can overwrite the RA statement on its
> next run. Coordinate with whoever owns that process so the RA statement is part
> of the canonical role definition, not a manual patch.

## What this repo's modules do and don't do

- The `aws-ra` module **references** the existing roles by ARN
  (`arn:aws:iam::<account>:role/<RoleName>`) in the Roles Anywhere **target
  profiles**. It does **not** create or modify those roles.
- Adding the RA trust statement is a **prerequisite** handled by the role owners
  per the section above — it is intentionally out of scope for these modules so we
  don't fight whatever already manages the roles.
- The only IAM role this repo creates is the small **profile-sync** role Teleport
  assumes (via RA) to list an account's profiles. That role is RA-specific and
  unrelated to the reused access roles.

This also assumes role **names are consistent across accounts** (e.g. `ReadOnly`
is `ReadOnly` everywhere). Consistent names keep the referenced ARNs deterministic
and let a single Teleport role match every account with a wildcard
(`arn:aws:iam::*:role/ReadOnly`).

## Verify it works

After adding the statement and creating the RA resources in the account/region:

1. The trust anchor + target profile exist (created by the `aws-ra` module).
2. The role shows **both** statements:
   `aws iam get-role --role-name ReadOnly --query 'Role.AssumeRolePolicyDocument'`
3. Teleport syncs the profile to an app (~5 min) and
   `tsh apps login <app> --aws-role ReadOnly` succeeds.

If sync works but assumption fails, it's almost always the RA trust statement
missing or an `aws:SourceAccount` value that doesn't match the account.

## References

- [AWS — IAM Roles Anywhere trust model](https://docs.aws.amazon.com/rolesanywhere/latest/userguide/trust-model.html)
- [Teleport — AWS Console and CLI access with Roles Anywhere](https://goteleport.com/docs/enroll-resources/application-access/cloud-apis/aws-console-roles-anywhere/)
