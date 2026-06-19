output "account_id" {
  value = local.account_id
}

output "trust_anchor_arn" {
  description = "Feed this into the Teleport integration's spec.aws_ra.trust_anchor_arn."
  value       = aws_rolesanywhere_trust_anchor.this.arn
}

output "profile_sync_arn" {
  description = "Feed this into spec.aws_ra.profile_sync_config.profile_arn."
  value       = aws_rolesanywhere_profile.sync.arn
}

output "profile_sync_role_arn" {
  description = "Feed this into spec.aws_ra.profile_sync_config.role_arn."
  value       = aws_iam_role.profile_sync.arn
}

output "target_role_arns" {
  description = "Map of target role key => ARN, for granting access in Teleport roles."
  value       = { for k, r in aws_iam_role.target : k => r.arn }
}

output "target_profile_arns" {
  description = "Map of target role key => Roles Anywhere access profile ARN (synced into Teleport as apps)."
  value       = { for k, p in aws_rolesanywhere_profile.target : k => p.arn }
}

# Convenience: an object shaped exactly like the teleport-integrations module
# expects per account, so the root can just collect these.
output "integration_input" {
  value = {
    trust_anchor_arn = aws_rolesanywhere_trust_anchor.this.arn
    profile_arn      = aws_rolesanywhere_profile.sync.arn
    role_arn         = aws_iam_role.profile_sync.arn
  }
}
