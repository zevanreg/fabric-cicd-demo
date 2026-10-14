output "storage_account_id" {
  description = "Storage account resource ID; grant additional Terraform operators Blob Data Contributor at this scope."
  value       = azurerm_storage_account.state.id
}

output "deployment_application_client_id" {
  description = "Repository-level AZURE_CLIENT_ID for GitHub Actions."
  value       = azuread_application_registration.deployment.client_id
}

output "deployment_service_principal_object_id" {
  description = "Object ID of the shared deployment service principal; used for Fabric Contributor assignments."
  value       = azuread_service_principal.deployment.object_id
}

output "deployment_tenant_id" {
  description = "Repository-level AZURE_TENANT_ID for GitHub Actions."
  value       = data.azurerm_client_config.current.tenant_id
}

output "deployment_config" {
  description = "Non-secret JSON variable handoff for terraform/deployment.auto.tfvars.json."
  value = jsonencode({
    deployment_application_client_id       = azuread_application_registration.deployment.client_id
    deployment_service_principal_object_id = azuread_service_principal.deployment.object_id
    environments                           = var.environments
  })
}

output "backend_config" {
  description = "Non-secret backend HCL for terraform/backend.hcl."
  value       = <<-EOT
    resource_group_name  = "${azurerm_resource_group.state.name}"
    storage_account_name = "${azurerm_storage_account.state.name}"
    container_name       = "${azurerm_storage_container.state.name}"
    key                  = "fabric-infrastructure.tfstate"
    subscription_id      = "${var.subscription_id}"
    tenant_id            = "${data.azurerm_client_config.current.tenant_id}"
  EOT
}
