variable "name_prefix" {
  description = "Prefix for the AWS Roles Anywhere resources in this account/region."
  type        = string
  default     = "teleport"
}

variable "teleport_ca_pem" {
  description = "PEM-encoded Teleport AWS Roles Anywhere CA bundle."
  type        = string
}

variable "account_id" {
  description = "Account ID for the aws:SourceAccount trust condition. Defaults to the caller's account."
  type        = string
  default     = null
}

variable "region" {
  description = "AWS region for this unit (used for the integration label only; the provider sets the actual region)."
  type        = string
  default     = null
}

variable "create_target_roles" {
  description = "Create the target IAM roles here (test accounts) vs. reference existing ones. Passed to aws-ra."
  type        = bool
  default     = false
}

variable "target_roles" {
  description = "Roles to expose, keyed by access level: { name, managed_policy_arns?, inline_policy_json?, max_session_seconds? }. Passed to aws-ra."
  type = map(object({
    name                = string
    managed_policy_arns = optional(list(string), [])
    inline_policy_json  = optional(string, null)
    max_session_seconds = optional(number, 3600)
  }))
  default = {}
}

variable "accept_role_session_name" {
  description = "Whether target profiles accept a role session name (lets Teleport stamp the username)."
  type        = bool
  default     = true
}

# --- Profile-sync role (pass-through to aws-ra) --------------------------------
variable "create_profile_sync_role" {
  type    = bool
  default = true
}

variable "profile_sync_role_name" {
  type    = string
  default = null
}

variable "profile_sync_role_arn" {
  type    = string
  default = null
}

variable "profile_sync_managed_policy_arns" {
  type    = list(string)
  default = []
}

# --- Teleport integration ------------------------------------------------------
variable "integration_key" {
  description = "Unique key for this integration (e.g. \"test-1-us-east-1\"). Becomes part of the integration name."
  type        = string
}

variable "integration_name_prefix" {
  description = "Prefix for the integration name. Final name is <prefix>-<integration_key>."
  type        = string
  default     = "aws-ra"
}

variable "integration_description" {
  type    = string
  default = "AWS Roles Anywhere integration"
}

variable "sync_enabled" {
  type    = bool
  default = true
}

variable "profile_name_filters" {
  description = "Profile name filters for sync. Defaults to \"<name_prefix>-*\" so only this module's profiles are synced."
  type        = list(string)
  default     = null
}

variable "labels" {
  description = "Extra labels on the Teleport integration (merged with the region label)."
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags applied to all AWS resources."
  type        = map(string)
  default     = {}
}
