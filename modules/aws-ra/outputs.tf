output "account_id" {
  value = local.account_id
}

output "trust_anchor_arn" {
  description = "Roles Anywhere trust anchor ARN (regional). Feeds the Teleport integration's trust_anchor_arn."
  value       = aws_rolesanywhere_trust_anchor.this.arn
}

output "profile_sync_role_arn" {
  description = "Profile-sync IAM role ARN (created here or referenced). Feeds profile_sync_config.role_arn."
  value       = local.profile_sync_role_arn
}

output "sync_profile_arn" {
  description = "Roles Anywhere sync profile ARN (regional). Feeds profile_sync_config.profile_arn."
  value       = aws_rolesanywhere_profile.sync.arn
}

output "target_role_arns" {
  description = "Map of access level => target IAM role ARN (created or referenced). For wiring Teleport roles' aws_role_arns."
  value       = local.target_role_arns
}

output "target_profile_arns" {
  description = "Map of access level => Roles Anywhere target profile ARN (synced into Teleport as apps)."
  value       = { for k, p in aws_rolesanywhere_profile.target : k => p.arn }
}

# Shaped exactly like one entry of the teleport-integrations module's accounts
# map, so a per-account/region caller can feed it straight through.
output "integration_input" {
  description = "Object for the teleport-integrations accounts map: trust_anchor_arn, profile_arn, role_arn."
  value = {
    trust_anchor_arn = aws_rolesanywhere_trust_anchor.this.arn
    profile_arn      = aws_rolesanywhere_profile.sync.arn
    role_arn         = local.profile_sync_role_arn
  }
}
