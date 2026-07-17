variable "role_name_prefix" {
  description = "Prefix for each Teleport role name. Final name is <prefix>-<tier>, e.g. aws-readonly."
  type        = string
  default     = "aws"
}

variable "role_version" {
  description = "Teleport role resource version (v3–v8)."
  type        = string
  default     = "v7"
}

variable "access_roles" {
  description = <<-EOT
    Teleport access roles to create, keyed by tier (readonly/poweruser/admin/...).
    One teleport_role per entry: it matches apps labelled aws/access-level=<tier>
    and allows assuming the AWS role <aws_role_name> in the scoped accounts.
  EOT
  type = map(object({
    aws_role_name      = string           # IAM role name → aws_role_arns
    access_level_label = optional(string) # aws/access-level value to match; defaults to the map key
    description        = optional(string)
    okta_group         = optional(string, "")        # SAML "groups" value that maps to this tier (blank = no mapping emitted)
    access             = optional(string, "direct")  # "direct" = auto-granted, or "request" = must be access-requested
  }))
  validation {
    condition     = alltrue([for r in var.access_roles : contains(["direct", "request"], r.access)])
    error_message = "access must be either \"direct\" or \"request\"."
  }
}

variable "account_ids" {
  description = <<-EOT
    AWS account IDs to scope aws_role_arns to. Empty (default) uses a wildcard
    (arn:aws:iam::*:role/<name>) covering every account — the scalable option for
    hundreds of accounts. Set explicit IDs to pin the proof to known accounts.
  EOT
  type        = list(string)
  default     = []
}

variable "labels" {
  description = "Labels applied to each Teleport role's metadata."
  type        = map(string)
  default     = {}
}
