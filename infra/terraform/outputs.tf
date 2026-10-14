output "capacity_resource_id" {
  description = "Azure resource ID of the Fabric capacity."
  value       = azurerm_fabric_capacity.this.id
}

output "fabric_capacity_id" {
  description = "Fabric capacity UUID, distinct from its Azure resource ID."
  value       = data.fabric_capacity.this.id
}

output "deployment_application_client_id" {
  description = "AZURE_CLIENT_ID for the repository's GitHub environments."
  value       = var.deployment_application_client_id
}

output "deployment_service_principal_object_id" {
  description = "Object ID of the service principal granted Contributor on every managed Fabric workspace."
  value       = var.deployment_service_principal_object_id
}

output "workspace_ids" {
  description = "FABRIC_WORKSPACE_ID per GitHub environment in the repository."
  value       = { for environment, workspace in fabric_workspace.this : environment => workspace.id }
}
