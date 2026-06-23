output "account_id" {
  value = module.aws_ra.account_id
}

output "integration_name" {
  description = "Name of the Teleport integration created for this account/region."
  value       = module.teleport.integration_names[var.integration_key]
}

output "trust_anchor_arn" {
  value = module.aws_ra.trust_anchor_arn
}

output "target_role_arns" {
  description = "Map of access level => target IAM role ARN (created or referenced)."
  value       = module.aws_ra.target_role_arns
}

output "target_profile_arns" {
  description = "Map of access level => Roles Anywhere target profile ARN."
  value       = module.aws_ra.target_profile_arns
}
