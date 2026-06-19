output "integration_names" {
  description = "Map of account key => Teleport integration name."
  value       = { for k, i in teleport_integration.aws_ra : k => i.metadata.name }
}
