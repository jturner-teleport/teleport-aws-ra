output "role_names" {
  description = "Map of tier => Teleport role name."
  value       = { for k, r in teleport_role.access : k => r.metadata.name }
}

output "request_role_names" {
  description = "Map of tier => requester Teleport role name (only for request tiers)."
  value       = { for k, r in teleport_role.request : k => r.metadata.name }
}

output "attributes_to_roles" {
  description = <<-EOT
    SAML connector attributes_to_roles mappings (Okta group => Teleport role),
    one per tier that has an okta_group set. Merge into your existing connector:
    `tctl get saml/okta > c.yaml`, paste these under spec.attributes_to_roles,
    then `tctl create -f c.yaml`. Direct tiers map the group to the access role;
    request tiers map it to the requester role.
  EOT
  value       = local.attributes_to_roles
}
