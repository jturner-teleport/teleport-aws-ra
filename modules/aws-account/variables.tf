variable "name_prefix" {
  description = "Prefix for the AWS resources created in this account (trust anchor, sync role, profile)."
  type        = string
  default     = "teleport"
}

variable "teleport_ca_pem" {
  description = <<-EOT
    PEM-encoded Teleport AWS Roles Anywhere CA certificate bundle.
    Obtain it once from your cluster with:

        tctl auth export --type awsra > teleport-awsra-ca.pem

    and pass it in, e.g. file("$${path.root}/teleport-awsra-ca.pem").
  EOT
  type        = string
}

variable "profile_sync_managed_policy_arns" {
  description = "Optional extra managed policy ARNs to attach to the profile-sync role."
  type        = list(string)
  default     = []
}

variable "target_roles" {
  description = <<-EOT
    IAM roles that Teleport users will assume in this account, keyed by a short name.
    Each role gets the Roles Anywhere trust policy attached automatically.
  EOT
  type = map(object({
    managed_policy_arns = optional(list(string), [])
    # Inline policy JSON, if you want a custom permission set instead of (or in addition to) managed policies.
    inline_policy_json  = optional(string, null)
    max_session_seconds = optional(number, 3600)
  }))
  default = {}
}

variable "tags" {
  description = "Tags applied to all AWS resources created by this module."
  type        = map(string)
  default     = {}
}
