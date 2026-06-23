variable "name_prefix" {
  description = "Prefix for the Roles Anywhere resources (trust anchor, sync profile, target profiles) and the default profile-sync role name."
  type        = string
  default     = "teleport"
}

variable "teleport_ca_pem" {
  description = <<-EOT
    PEM-encoded Teleport AWS Roles Anywhere CA bundle. Obtain once with:

        tctl auth export --type awsra > teleport-awsra-ca.pem
  EOT
  type        = string
}

variable "account_id" {
  description = "Account ID used in the aws:SourceAccount trust condition. Defaults to the caller's account."
  type        = string
  default     = null
}

variable "create_target_roles" {
  description = <<-EOT
    Create the target IAM roles here (with the Roles Anywhere trust policy), vs.
    reference roles that already exist. Use true for test accounts that don't have
    the roles yet; false (the default) to reference existing roles — which must
    already trust rolesanywhere.amazonaws.com (see docs/reusing-existing-iam-roles.md).
  EOT
  type        = bool
  default     = false
}

variable "target_roles" {
  description = <<-EOT
    Roles to expose through Roles Anywhere, keyed by access level (readonly/poweruser/...).
    One Roles Anywhere target profile is created per entry.

    `name` is the IAM role name (e.g. "ReadOnly"). When create_target_roles = true the
    role is created with that name, the RA trust policy, and the given policies. When
    false, the role is referenced as arn:aws:iam::<account_id>:role/<name> and the
    policy fields are ignored.
  EOT
  type = map(object({
    name                = string
    managed_policy_arns = optional(list(string), [])
    inline_policy_json  = optional(string, null)
    max_session_seconds = optional(number, 3600)
  }))
  default = {}
}

variable "accept_role_session_name" {
  description = "Whether target profiles accept a role session name (lets Teleport stamp the username for audit)."
  type        = bool
  default     = true
}

# --- Profile-sync role: create here, or reference an account-global one --------
variable "create_profile_sync_role" {
  description = "Create the RA profile-sync IAM role here. Set false to reference an account-global one via profile_sync_role_arn (e.g. created once per account, shared across regions)."
  type        = bool
  default     = true
}

variable "profile_sync_role_name" {
  description = "Name for the profile-sync role when created. Defaults to \"<name_prefix>-profile-sync\". Must be unique within the account (IAM roles are global)."
  type        = string
  default     = null
}

variable "profile_sync_role_arn" {
  description = "ARN of an existing profile-sync role to reference when create_profile_sync_role = false."
  type        = string
  default     = null
}

variable "profile_sync_managed_policy_arns" {
  description = "Optional extra managed policy ARNs to attach to the profile-sync role."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to all AWS resources created by this module."
  type        = map(string)
  default     = {}
}
