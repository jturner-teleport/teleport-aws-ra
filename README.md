# Teleport AWS Roles Anywhere — multi-account Terraform

Provisions, per AWS account, the AWS IAM Roles Anywhere resources and the
matching Teleport `aws-ra` integration. With profile sync enabled, Teleport
auto-creates an AWS app per Roles Anywhere profile — you don't author apps.

## Layout

- `modules/aws-account/` — AWS-side resources for **one** account: trust anchor,
  profile-sync role + profile, and target IAM roles. Called once per account
  because Terraform can't `for_each` over provider configurations.
- `modules/teleport-integrations/` — Teleport-side, **one** provider,
  `for_each` over a map of accounts → one `teleport_integration` each.
- `example/` — wires both together for two accounts (`prod`, `staging`).

## How it fits together

```
aws-account (prod)    ─┐  trust_anchor_arn
aws-account (staging) ─┤  profile_arn        ──►  teleport-integrations
aws-account (...)     ─┘  role_arn                (for_each → N integrations)
                                                          │
                                          Teleport profile sync (~5 min)
                                                          ▼
                                          one AWS app per RA profile
```

## Prerequisites

1. Export the Teleport CA bundle once and drop it next to the example:
   ```
   tctl auth export --type awsra > example/teleport-awsra-ca.pem
   ```
   This is the only out-of-band step — the Teleport provider has no
   CA-export data source.
2. A Teleport identity file for the provider (tbot / MachineID).
3. AWS credentials that can assume an admin role in each target account.

## Usage walkthrough

### Step 0 — one-time prep (independent of account count)

1. Export the Teleport CA bundle (one cert, reused by every account's trust anchor):
   ```
   tctl auth export --type awsra > example/teleport-awsra-ca.pem
   ```
2. Get a Teleport identity for the provider (tbot / MachineID), e.g.:
   ```
   tsh login --proxy=example.teleport.sh:443
   tctl bots add terraform --roles=terraform-provider --format=json   # produces the identity file
   ```
3. Have AWS credentials in your shell that can `sts:AssumeRole` into a
   `TerraformAdmin` role in each target account.

### Step 1 — declare each account (two places)

Terraform can't loop over providers, so an account lives in two spots. To add
account `dev` (`333333333333`):

`example/providers.tf` — one aliased provider:
```hcl
provider "aws" {
  alias  = "dev"
  region = "us-east-1"
  assume_role { role_arn = "arn:aws:iam::333333333333:role/TerraformAdmin" }
}
```

`example/main.tf` — one AWS module call (the IAM roles users get in that account):
```hcl
module "aws_dev" {
  source          = "../modules/aws-account"
  providers       = { aws = aws.dev }       # binds this call to the dev account
  name_prefix     = "teleport"
  teleport_ca_pem = local.teleport_ca_pem
  target_roles = {
    readonly = { managed_policy_arns = ["arn:aws:iam::aws:policy/ReadOnlyAccess"] }
  }
}
```

### Step 2 — the data flow (no ARNs copied by hand)

`aws-account` emits an `integration_input` object shaped for the Teleport module:
```
module.aws_dev.integration_input = {
  trust_anchor_arn = "arn:aws:rolesanywhere:...:trust-anchor/abc"
  profile_arn      = "arn:aws:rolesanywhere:...:profile/def"
  role_arn         = "arn:aws:iam::333...:role/teleport-profile-sync"
}
```

`merge()` it with your Teleport-side preferences into the `accounts` map:
```hcl
module "teleport_integrations" {
  source = "../modules/teleport-integrations"
  accounts = {
    dev = merge(module.aws_dev.integration_input, {
      profile_name_filters = ["teleport-*"]   # only sync RA profiles named teleport-*
      labels               = { env = "dev" }
    })
  }
}
```

The map key (`dev`) becomes the integration name `aws-ra-dev`, and `for_each`
turns N entries into N integrations. Referencing `module.aws_dev.integration_input`
also creates the dependency edge, so Terraform always builds the AWS trust
anchor/profile before the integration that points at it — no manual ordering.

### Step 3 — apply

```
cd example
tofu init
tofu plan      # expect N aws-account modules + N integrations
tofu apply     # both sides, in the right order, in one run
```

### Step 4 — apps appear automatically

With `sync_enabled = true`, Teleport polls each account's Roles Anywhere
profiles ~every 5 min and creates one AWS app per matching profile:
```
tsh apps ls
tctl get apps
```

### Step 5 — grant users access (outside this module)

The module creates the roles + integration, not the RBAC. In a Teleport role:
```yaml
spec:
  allow:
    app_labels:
      'teleport.dev/aws-roles-anywhere-profile-arn': '*'   # or scope by env label
    aws_role_arns:
      - 'arn:aws:iam::333333333333:role/teleport-readonly'  # from the target_role_arns output
```
Then: `tsh apps login <app> --aws-role readonly`.

### What goes where

| You decide | Where it lives |
|---|---|
| Which accounts exist + how to auth into each | `providers.tf` (aliased provider per account) |
| What IAM roles users get per account | `aws-account` module call → `target_roles` |
| Which profiles sync + integration labels/filters | `accounts` map in the Teleport module |
| ARNs connecting AWS ↔ Teleport | automatic via `integration_input` |
| Who can use the apps | Teleport roles (outside this module) |

## Adding an account

1. Add an aliased `provider "aws"` block in `example/providers.tf`.
2. Add a `module "aws_<name>"` call in `example/main.tf` with that provider.
3. Add an entry to the `accounts` map passed to `teleport_integrations`.

## Granting access

Profiles sync in as apps labelled with
`teleport.dev/aws-roles-anywhere-profile-arn`. Grant access in a Teleport role
via `app_labels` plus `aws_role_arns` listing the target role ARNs (see the
`target_role_arns` output).

## Notes / verify before applying

- Validated with `tofu validate` (OpenTofu 1.12.2); provider versions resolved
  and pinned in the `.terraform.lock.hcl` files: Teleport `18.8.3`, AWS `6.50.0`.
  The `>= 5.0` constraint allowed AWS 6.x — tighten to `~> 5.0` if you need 5.x.
- The profile-sync IAM policy is a reasonable starting set
  (`rolesanywhere:ListProfiles/GetProfile/ListTagsForResource`, `iam:GetRole/ListRoles`);
  tighten or expand against current Teleport docs for your version.
- `validate`-level confidence only — not `plan`/`apply`'d against a live
  cluster or real AWS accounts.
