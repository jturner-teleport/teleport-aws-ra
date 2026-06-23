# `aws-ra` module

AWS-side Roles Anywhere resources for **one account/region**. The access roles
can be **created here** (handy for test accounts that don't have them yet) or
**referenced** (production, where the roles already exist for Okta SAML). It
creates:

- a Roles Anywhere **trust anchor** (regional) from the Teleport CA bundle,
- the **profile-sync** IAM role + Roles Anywhere sync profile Teleport uses to
  discover profiles (the sync role can be created here or referenced),
- one Roles Anywhere **target profile** per entry in `target_roles`,
- optionally, the **target IAM roles** themselves (`create_target_roles = true`).

## Create vs. reference target roles

`target_roles` is keyed by access level; `name` is the IAM role name.

- `create_target_roles = true` — creates each role with that name, the Roles
  Anywhere trust policy, and the listed `managed_policy_arns` / `inline_policy_json`.
  The roles are usable by RA immediately (no separate trust step).
- `create_target_roles = false` (default) — references the role as
  `arn:aws:iam::<account_id>:role/<name>`; the policy fields are ignored. The role
  must already trust `rolesanywhere.amazonaws.com`
  ([../../docs/reusing-existing-iam-roles.md](../../docs/reusing-existing-iam-roles.md)).

Either way the trust condition is `aws:SourceAccount`, so it works across all
regions in the account. (The older `aws-account` module only creates roles and
pins the trust to a single regional anchor; it remains for the simple demo.)

## Usage — create roles (test account)

```hcl
module "aws_ra" {
  source              = "../../modules/aws-ra"
  name_prefix         = "teleport"
  teleport_ca_pem     = file("${path.root}/teleport-awsra-ca.pem")
  create_target_roles = true

  target_roles = {
    readonly  = { name = "ReadOnly", managed_policy_arns = ["arn:aws:iam::aws:policy/ReadOnlyAccess"] }
    poweruser = { name = "PowerUser", managed_policy_arns = ["arn:aws:iam::aws:policy/PowerUserAccess"] }
    admin     = { name = "Admin", managed_policy_arns = ["arn:aws:iam::aws:policy/AdministratorAccess"] }
  }
}
```

## Usage — reference existing roles (production)

```hcl
module "aws_ra" {
  source          = "../../modules/aws-ra"
  teleport_ca_pem = file("${path.root}/teleport-awsra-ca.pem")
  # create_target_roles = false (default)

  target_roles = {
    readonly  = { name = "ReadOnly" }
    poweruser = { name = "PowerUser" }
    admin     = { name = "Admin" }
  }
}
```

Feed `module.aws_ra.integration_input` into the `teleport-integrations` module's
`accounts` map to create the matching integration.

## Multi-region: share one profile-sync role per account

The profile-sync IAM role is account-global, so create it once (one region) and
reference it from the others to avoid name collisions:

```hcl
# us-east-1 (home): creates the sync role
module "aws_ra_use1" {
  source   = "../../modules/aws-ra"
  # create_profile_sync_role = true (default)
  ...
}

# us-west-2: references the same global sync role
module "aws_ra_usw2" {
  source                   = "../../modules/aws-ra"
  create_profile_sync_role = false
  profile_sync_role_arn    = "arn:aws:iam::111111111111:role/teleport-profile-sync"
  ...
}
```

The sync role's `aws:SourceAccount` trust condition already covers every region's
trust anchor in the account, so one role works for all of them.

## Validation status

`tofu validate`-level only — not yet `plan`/`apply`'d against real accounts.
