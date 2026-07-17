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
    readonly  = { aws_role_name = "ReadOnly",  okta_group = "eg-aws-readonly",  access = "direct" }
    poweruser = { aws_role_name = "PowerUser", okta_group = "eg-aws-poweruser", access = "request" }
    admin     = { aws_role_name = "Admin",     okta_group = "eg-aws-admin",     access = "request" }
  }
  # account_ids = [...]   # optional; default is a wildcard across all accounts
}
```

Then a user with the `aws-readonly` role can `tsh apps login <app> --aws-role ReadOnly`.

## Okta group → tier mapping (`okta_group` / `access`)

Per tier you can set:
- **`okta_group`** — the SAML `groups` value that should map to this tier.
- **`access`** — `direct` (auto-granted on login) or `request` (must be access-requested).

From these the module:
- creates the **direct** access role `<prefix>-<tier>` (always), and
- for `request` tiers, a **requester** role `<prefix>-request-<tier>` whose only
  grant is `allow.request.roles = [<prefix>-<tier>]` (JIT access via approval), and
- emits an **`attributes_to_roles`** output — the Okta-group→role mapping to paste
  into your SAML connector (direct tiers → the access role; request tiers → the
  requester role).

The connector itself is **not** managed here (it's auth-critical). Apply this
module, read the mapping, and merge it into your connector:

```sh
terragrunt output -json attributes_to_roles      # from live/teleport/access-roles
tctl get saml/okta > okta.yaml                    # paste under spec.attributes_to_roles
tctl create -f okta.yaml
```

Result: members of the readonly group get read-only automatically; members of the
power/admin groups see those tiers as **requestable** and get them on approval.

## Notes

- `aws_role_arns` supports glob wildcards per the Teleport role reference, but the
  wildcard-account behavior for RA-synced apps is worth confirming against your
  cluster version — pin `account_ids` for the first proof if in doubt.
- Role version defaults to `v7` (override with `role_version`).
- Validate-level only — not yet applied against a live cluster.
