# Teleport AWS Roles Anywhere — Terraform / Terragrunt

Give Teleport users access to AWS accounts via **AWS IAM Roles Anywhere (RA)**.
For each AWS account/region this provisions the RA resources (trust anchor, sync
profile, target profiles) and a matching Teleport `aws-ra` integration. With
profile sync enabled, **Teleport auto-creates one AWS app per RA profile** (~every
5 min) — you don't author apps by hand.

It supports both:
- **Creating** the access roles (handy for fresh/test accounts), or
- **Referencing** roles your accounts already have (e.g. the roles used for Okta
  SAML) — see [docs/reusing-existing-iam-roles.md](docs/reusing-existing-iam-roles.md).

---

## Which path should I use?

| Path | Use when | Lives in |
|---|---|---|
| **A. Quick demo** | A few accounts, one `apply`, kick the tires | [`example/`](example/) |
| **B. Scale (Terragrunt Stacks)** | Many accounts × regions, driven by an inventory | [`live/`](live/) |

Both use the same building-block modules. **Path B is the one to use for real
multi-account rollouts** — start there unless you just want a quick demo.

---

## Repository layout

```
modules/
  aws-ra/                 AWS RA resources for ONE account/region (create OR reference roles)
  teleport-integrations/  ONE Teleport provider → one teleport_integration per account
  ara-region/             Thin composite: aws-ra + teleport-integrations (what each unit runs)
  teleport-access-roles/  Cluster-global Teleport roles (one per access tier)
  aws-account/            Legacy: creates roles, single-region trust (used by example/ demo)
units/
  ara-region/             Terragrunt unit template (generates the AWS provider, reads values)
live/
  inventory.yaml          Source of truth: accounts, regions, roles per environment
  scripts/generate-stacks.py   Generates the stack files from the inventory
  root.hcl                Shared: remote state + Teleport provider (included by every unit)
  <env>/terragrunt.stack.hcl   Generated unit blocks (one per account/region) — committed
  teleport/access-roles/  Cluster-global Teleport access-roles unit
example/                  Quick-demo root wiring two accounts in a single apply
docs/                     Longer-form docs (e.g. reusing existing IAM roles)
```

---

## Path B — Many accounts at scale (Terragrunt Stacks)

### How it works

```
inventory.yaml ──▶ scripts/generate-stacks.py ──▶ live/<env>/terragrunt.stack.hcl
                                                         │  terragrunt stack generate
                                                         ▼
                                  .terragrunt-stack/<account>/<region>/  (one unit/state each)
                                                         │  units/ara-region → modules/ara-region
                                                         ▼
                              AWS RA resources + Teleport integration, per account/region
```

You edit **one YAML file** and re-run the generator; adding accounts never means
hand-writing config. (Terragrunt units don't support `for_each` yet, so a small
generator emits the explicit `unit` blocks — the generated stack files are
committed so the diff is reviewable.)

### Prerequisites

1. **Tools:** `terragrunt` (≥ v0.78 for Stacks), `terraform`/`tofu`, `python3` + `pyyaml`.
2. **Teleport CA bundle** at the repo root:
   ```sh
   tctl auth export --type awsra > teleport-awsra-ca.pem
   ```
3. **Teleport provider identity** at the repo root (its role must be able to manage
   `integration` and `role` resources — see `example/teleport-setup.example.yaml`):
   ```sh
   tctl auth sign --user=terraform --out=identity --format=file --ttl=10h
   ```
4. **AWS auth per account** — chosen in `inventory.yaml` (see Step 1).

> `identity`, `*.pem`, `live/.aws-credentials`, state files, and `.terragrunt-stack/`
> are all gitignored.

### Step 1 — set environment + credentials

```sh
export TELEPORT_ADDR="yourtenant.teleport.sh:443"

# State backend: set these for S3 state, OR leave TG_STATE_BUCKET unset to use
# local state files (fine for a first run).
export TG_STATE_BUCKET="my-tfstate"  TG_STATE_REGION="us-east-1"  TG_STATE_LOCK_TABLE="tf-locks"
```

Each account picks one AWS auth mode in `inventory.yaml`:

- **Static keys (named profile):** put the keys in a gitignored `live/.aws-credentials`
  and point at it:
  ```sh
  export AWS_SHARED_CREDENTIALS_FILE="$(pwd)/live/.aws-credentials"
  ```
  ```ini
  # live/.aws-credentials
  [teleport-acct1]
  aws_access_key_id = AKIA...
  aws_secret_access_key = ...
  ```
- **Assume-role:** have base credentials in your shell that can `sts:AssumeRole`
  into each account's deployer role.

### Step 2 — edit the inventory

`live/inventory.yaml` is the single source of truth:

```yaml
defaults:
  regions: [us-east-1, us-west-2]
  create_roles: false          # false = reference existing roles; true = create them
  roles:                       # access_level => IAM role name (+ policies for creation)
    readonly:  { name: ReadOnly,  managed_policy_arns: ["arn:aws:iam::aws:policy/ReadOnlyAccess"] }
    poweruser: { name: PowerUser, managed_policy_arns: ["arn:aws:iam::aws:policy/PowerUserAccess"] }
    admin:     { name: Admin,     managed_policy_arns: ["arn:aws:iam::aws:policy/AdministratorAccess"] }

environments:
  test:
    create_roles: true         # test accounts don't have the roles yet → create them
    accounts:
      - { name: acct1, account_id: "111111111111", aws_profile: teleport-acct1 }     # static keys
  prod:
    accounts:
      - { name: prod1, account_id: "222222222222",
          deployer_role_arn: "arn:aws:iam::222222222222:role/tec-deployer-role",     # assume-role
          regions: [us-east-1, us-west-2, eu-west-1] }                                # per-account override
```

- `create_roles`, `regions`, `roles` resolve **account → environment → defaults**.
- `aws_profile` (static keys) **or** `deployer_role_arn` (assume-role) per account.

### Step 3 — generate the stack files

```sh
python3 live/scripts/generate-stacks.py     # writes live/<env>/terragrunt.stack.hcl
git add live/inventory.yaml live/*/terragrunt.stack.hcl   # commit both
```

### Step 4 — apply AWS + integrations for an environment

```sh
cd live/test
terragrunt stack generate          # materialize .terragrunt-stack/ (one unit per account/region)
terragrunt run --all plan          # review
terragrunt run --all apply         # creates RA resources + the Teleport integration per unit
```

Within ~5 min, Teleport syncs the profiles and the apps appear:
```sh
tsh apps ls
tctl get apps
```

### Step 5 — apply the cluster-global Teleport access roles (once)

These are the RBAC roles that actually let users in — one per tier, applied once
for the whole cluster (not per account). They read the tiers from the inventory:

```sh
cd live/teleport/access-roles
terragrunt apply
```

By default each role uses a **wildcard** `aws_role_arns` (`arn:aws:iam::*:role/ReadOnly`)
so one role grants that tier across every account (relies on consistent role
names). Set `account_ids` in that unit to pin to specific accounts instead.

### Step 6 — map SSO (Okta) groups to tiers (direct vs. request)

Each tier in `inventory.defaults.roles` can set two fields that control **who**
gets it and **how**:

```yaml
roles:
  readonly:  { name: ReadOnly,  okta_group: eg-aws-readonly,  access: direct }   # auto-granted
  poweruser: { name: PowerUser, okta_group: eg-aws-poweruser, access: request }  # requestable
  admin:     { name: Admin,     okta_group: eg-aws-admin,     access: request }
```

- `access: direct` → members of `okta_group` get the role automatically on login.
- `access: request` → members can **request** it (JIT); the module makes a
  `aws-request-<tier>` role for that.

Apply, then take the generated mapping and merge it into your SAML connector — the
connector is **not** managed by Terraform (it's auth-critical), so you paste the
output in by hand:

```sh
cd live/teleport/access-roles
terragrunt output -json attributes_to_roles     # Okta group -> Teleport role
tctl get saml/okta > okta.yaml                   # paste under spec.attributes_to_roles
tctl create -f okta.yaml
```

Result: readonly-group members get read-only automatically; power/admin-group
members see those tiers as requestable and get them on approval. See
[modules/teleport-access-roles/README.md](modules/teleport-access-roles/README.md).

### Adding accounts later

Edit `inventory.yaml` → `python3 live/scripts/generate-stacks.py` → commit →
`terragrunt run --all apply`. The unit template and modules don't change.

---

## Path A — Quick demo (`example/`)

A single root that wires two accounts in one `apply` using the legacy
`aws-account` module (which **creates** roles and pins trust to one region).

```sh
cd example
cp terraform.tfvars.example terraform.tfvars        # fill in teleport_addr + AWS creds
# put teleport-awsra-ca.pem + identity in example/
tofu init && tofu plan && tofu apply
```

`example/providers.tf` ships with static-key auth active and an assume-role
alternative commented out. See the comments in `example/*.tf` and
`example/TESTING.md`.

---

## Creating vs. reusing IAM roles

- **Create** (`create_roles: true`): the `aws-ra` module makes each role with the
  RA trust policy baked in — usable immediately, no extra steps.
- **Reference** (`create_roles: false`): the module points RA profiles at
  `arn:aws:iam::<account>:role/<name>`. Those roles **must already trust Roles
  Anywhere** — add one trust statement per role (it coexists with Okta/SAML).
  Full instructions: [docs/reusing-existing-iam-roles.md](docs/reusing-existing-iam-roles.md).

Either way the RA trust uses `aws:SourceAccount`, so one statement covers every
region in the account.

**Global roles vs. regional RA (multi-region accounts):** IAM roles are global;
RA resources (trust anchor, profiles) are regional. So when `create_roles: true`,
the generator creates the roles in only the account's **first** region and
**references** that same role from the other regions — those region units take a
Terragrunt dependency on the creator so the role exists before their RA profiles
point at it. The dependency is intra-account only, so `run --all` still
parallelizes across accounts. The single global role is trusted by the trust
anchor in every region (via `aws:SourceAccount`), so one role serves them all.

> **Alternative — dedicated per-account roles unit.** The default above creates
> the roles in the account's *first* region, so reordering/removing that region
> moves the roles (a destroy + recreate). If you expect to change region lists
> on accounts that *also* create their own roles, an alternative is a dedicated
> per-account "roles" unit (roles created once, region-agnostic; every regional
> unit then just references). It decouples role lifecycle from any region at the
> cost of one extra state per account plus a roles-only module path. Not wired up
> today — prod references pre-existing roles, so the coupling only affects the few
> create-roles test accounts. Add it if that lifecycle coupling ever bites.

## Granting users access

Teleport imports each RA profile's AWS tags as app labels prefixed with `aws/`.
The modules stamp an `access-level` tag on every target profile, so apps get an
`aws/access-level` label to scope on. The `teleport-access-roles` module builds
roles like:

```yaml
spec:
  allow:
    app_labels:
      'aws/access-level': 'readonly'
    aws_role_arns:
      - 'arn:aws:iam::*:role/ReadOnly'    # wildcard across accounts (or pin via account_ids)
```

Then: `tsh apps login <app> --aws-role ReadOnly`.

---

## Status & known issues

- **Modules:** all pass `terraform validate`. Terragrunt config resolves correctly
  (`terragrunt stack generate` + `terragrunt render`).
- **AWS side:** validated with a real `plan` against a test account
  (`Plan: 13 to add` — roles, trust anchor, sync + target profiles).
- **Teleport integration apply** requires the Teleport provider to reach your
  cluster's API endpoint (proxy address + a valid identity file).

## Troubleshooting

**Provider/cluster versions:** keep the Teleport provider on the same major as your
cluster (constraint is `>= 18.0`; pin tighter if needed).
