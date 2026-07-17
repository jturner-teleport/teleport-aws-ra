# `live/` — Terragrunt Stacks for many accounts

Scales the modules to many AWS accounts/regions without one bespoke config per
account. An **inventory** drives a **generator** that writes **stack files**;
Terragrunt expands those into one small unit (one state) per account/region and
applies them with `run --all`.

```
inventory.yaml ──▶ scripts/generate-stacks.py ──▶ live/<env>/terragrunt.stack.hcl
                                                          │  terragrunt stack generate
                                                          ▼
                                   .terragrunt-stack/<account>/<region>/  (one unit each)
                                                          │  references
                                                          ▼
                          units/ara-region/  ──▶  modules/ara-region (aws-ra + teleport)
```

## Why a generator (and not a `for_each`)

Terragrunt units don't yet support `for_each`/`count`
([terragrunt#4504](https://github.com/gruntwork-io/terragrunt/issues/4504)), so
units can't be looped in HCL. `scripts/generate-stacks.py` emits the explicit
`unit` blocks from `inventory.yaml` instead. The generated
`live/<env>/terragrunt.stack.hcl` files **are committed** so the diff is
reviewable; never edit them by hand.

## Layout

| Path | What it is |
|---|---|
| `inventory.yaml` | Source of truth: accounts, regions, role names per environment |
| `scripts/generate-stacks.py` | Reads the inventory, writes the stack files |
| `root.hcl` | Shared config every unit includes: remote state + Teleport provider |
| `<env>/terragrunt.stack.hcl` | Generated `unit` blocks (one per account/region) |
| `teleport/access-roles/` | Cluster-global unit: the Teleport access roles (one per tier) |
| `../units/ara-region/` | Unit template: AWS provider gen + inputs from `values` |
| `../modules/ara-region/` | The Terraform each unit runs (`aws-ra` + `teleport-integrations`) |
| `../modules/teleport-access-roles/` | The Teleport roles the access-roles unit runs |

## One-time prerequisites

- Place the Teleport CA bundle and provider identity at the **repo root**:
  - `teleport-awsra-ca.pem` (`tctl auth export --type awsra > teleport-awsra-ca.pem`)
  - `identity` (`tctl auth sign --user=terraform --out=identity --format=file`)
- Export environment (kept out of committed files):
  ```sh
  export TELEPORT_ADDR="yourtenant.teleport.sh:443"
  # State backend: set these for S3 state; leave TG_STATE_BUCKET unset to use
  # local state files (fine for a first test).
  export TG_STATE_BUCKET="…"  TG_STATE_REGION="us-east-1"  TG_STATE_LOCK_TABLE="…"
  ```
- **AWS auth, per account (set in `inventory.yaml`):**
  - `aws_profile: <name>` → static keys via a named profile. Put the keys in a
    gitignored `live/.aws-credentials` and point at it:
    `export AWS_SHARED_CREDENTIALS_FILE="$(pwd)/live/.aws-credentials"`.
  - `deployer_role_arn: <arn>` → base credentials in your shell that can
    `sts:AssumeRole` into that role (the `tec-deployer-role` model). The base
    identity in your shell must be one the deployer role's trust policy allows —
    if the assume fails with `AccessDenied`, check both the role name and that
    the credentials running terragrunt match a trusted principal.
- For accounts in **reference** mode (`create_roles: false`), the access roles
  must already exist and trust Roles Anywhere — see
  [../docs/reusing-existing-iam-roles.md](../docs/reusing-existing-iam-roles.md).
  Accounts in **create** mode (`create_roles: true`, e.g. test accounts) make the
  roles themselves, so this prerequisite doesn't apply to them.

## Workflow

```sh
# 1. Edit the inventory (add/remove accounts, regions, roles)
$EDITOR live/inventory.yaml

# 2. Regenerate the stack files, and commit both
python3 live/scripts/generate-stacks.py

# 3. Apply an environment (expands units, then runs them in parallel)
cd live/test
terragrunt stack generate         # materialize .terragrunt-stack/
terragrunt run --all plan         # review
terragrunt run --all apply

# 4. Apply the cluster-global Teleport access roles once (one per tier)
cd live/teleport/access-roles
terragrunt apply

# 5. Merge the Okta group -> role mapping into your SAML connector (by hand)
terragrunt output -json attributes_to_roles
tctl get saml/okta > okta.yaml     # paste under spec.attributes_to_roles
tctl create -f okta.yaml
```

The access roles are cluster-wide (not per account/region), so they live outside
the env stacks and are applied once. They read the tiers from `inventory.yaml` and
default to wildcard `aws_role_arns` covering all accounts; set `account_ids` in
that unit to pin them for the proof.

Each tier's `okta_group` / `access` fields (in `inventory.defaults.roles`) drive
SSO access: `access: direct` auto-grants the role to members of that Okta group;
`access: request` creates a `aws-request-<tier>` role so members can request it
just-in-time. The `attributes_to_roles` output is the Okta-group→role mapping to
paste into the connector — the connector itself is **not** Terraform-managed
(auth-critical). See `../modules/teleport-access-roles/README.md`.

To add accounts at scale, you only edit `inventory.yaml` and re-run the
generator — the unit template and modules don't change.

## Design notes

- **One profile-sync IAM role per account/region**, name region-suffixed
  (`teleport-profile-sync-<region>`) because IAM roles are global. This keeps
  units independent (no cross-unit dependency) so `run --all` parallelizes.
- **Create vs. reference roles** is per-account/env via `create_roles` in the
  inventory. Test accounts (`true`) create the roles with the RA trust policy
  baked in; production (`false`) references existing roles by name.
- **Role names are assumed identical across accounts**; the generator builds
  `arn:aws:iam::<account_id>:role/<name>` from `defaults.roles`. Per-account
  `roles:` / `regions:` / `create_roles:` overrides are supported in the inventory.
- **Non-deterministic ARNs stay in-state:** the trust anchor and sync-profile
  ARNs feed the Teleport integration within the same unit, so there's no
  cross-state `dependency` to wire.

## Status

Config resolution is verified (`terragrunt stack generate` + `terragrunt render`
produce correct providers, inputs, and state keys). Not yet `run --all apply`'d
against live accounts + cluster — that's the next phase.
