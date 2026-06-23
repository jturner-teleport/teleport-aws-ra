# `teleport-access-roles` module

Creates the **cluster-global** Teleport roles that grant users access to the AWS
apps synced from Roles Anywhere — one role per access tier (ReadOnly, PowerUser,
Admin, …). Single Teleport provider; **not** per account.

Each role:
- matches apps by the **`aws/access-level`** label (set from each target profile's
  `access-level` tag by the `aws-ra` module), and
- allows assuming the AWS role via **`aws_role_arns`**.

## Why ~3 roles, not 3 × N accounts

`aws_role_arns` defaults to a **wildcard account** — `arn:aws:iam::*:role/ReadOnly`
— so one `aws-readonly` role grants ReadOnly across every account, keyed off the
label. That's how 3 tiers cover hundreds of accounts without enumerating ARNs.
It relies on the IAM role **name being identical across accounts**.

Set `account_ids` to pin the ARNs to specific accounts instead (e.g. for the
proof, or if you don't want a wildcard):

```hcl
account_ids = ["111111111111", "222222222222"]   # → explicit ARNs per account
```

## Usage

```hcl
module "teleport_access_roles" {
  source = "../../modules/teleport-access-roles"

  access_roles = {
    readonly  = { aws_role_name = "ReadOnly" }
    poweruser = { aws_role_name = "PowerUser" }
    admin     = { aws_role_name = "Admin" }
  }
  # account_ids = [...]   # optional; default is a wildcard across all accounts
}
```

Then a user with the `aws-readonly` role can `tsh apps login <app> --aws-role ReadOnly`.

## Notes

- `aws_role_arns` supports glob wildcards per the Teleport role reference, but the
  wildcard-account behavior for RA-synced apps is worth confirming against your
  cluster version — pin `account_ids` for the first proof if in doubt.
- Role version defaults to `v7` (override with `role_version`).
- Validate-level only — not yet applied against a live cluster.
