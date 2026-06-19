variable "accounts" {
  description = <<-EOT
    Map of account key => AWS Roles Anywhere wiring. One Teleport integration is
    created per entry. The ARNs typically come from the aws-account module's
    outputs. With profile sync enabled, Teleport auto-creates an AWS app per
    matching Roles Anywhere profile (~every 5 min) — you do not create apps here.
  EOT
  type = map(object({
    trust_anchor_arn = string
    profile_arn      = string
    role_arn         = string

    sync_enabled             = optional(bool, true)
    accept_role_session_name = optional(bool, false)
    # Glob (profile*) or regex (^profile.*$) filters; empty => sync all profiles.
    profile_name_filters = optional(list(string), [])

    description = optional(string, "AWS Roles Anywhere integration")
    labels      = optional(map(string), {})
  }))
}

variable "name_prefix" {
  description = "Prefix for each integration's metadata.name. Final name is <prefix>-<account key>."
  type        = string
  default     = "aws-ra"
}
