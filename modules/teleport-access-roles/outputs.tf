output "role_names" {
  description = "Map of tier => Teleport role name."
  value       = { for k, r in teleport_role.access : k => r.metadata.name }
}
