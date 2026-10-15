mock_provider "azurerm" {}

mock_provider "fabric" {
  mock_data "fabric_capacity" {
    defaults = {
      id    = "11111111-1111-4111-8111-111111111111"
      state = "Active"
    }
  }
}

run "bootstrapped_workspace_contributor" {
  command = plan

  variables {
    subscription_id                        = "22222222-2222-4222-8222-222222222222"
    deployment_application_client_id       = "33333333-3333-4333-8333-333333333333"
    deployment_service_principal_object_id = "44444444-4444-4444-8444-444444444444"
    capacity_admins                        = ["admin@example.com"]
    workspace_prefix                       = "fabric-cicd-demo"
    environments                           = ["developer1", "dev", "test", "prod"]
  }

  assert {
    condition = (
      toset(keys(fabric_workspace.this)) == var.environments &&
      toset(keys(fabric_workspace_role_assignment.deployment_contributor)) == var.environments &&
      toset(azurerm_fabric_capacity.this.administration_members) == toset(concat(var.capacity_admins, [var.deployment_service_principal_object_id])) &&
      alltrue([
        for environment, workspace in fabric_workspace.this :
        workspace.display_name == "${var.workspace_prefix}-${environment}"
      ]) &&
      alltrue([
        for assignment in fabric_workspace_role_assignment.deployment_contributor :
        assignment.principal.id == var.deployment_service_principal_object_id &&
        assignment.principal.type == "ServicePrincipal" &&
        assignment.role == "Contributor"
      ])
    )
    error_message = "The bootstrapped service principal must administer the capacity and have Contributor on every environment workspace."
  }

  assert {
    condition = (
      output.deployment_application_client_id == var.deployment_application_client_id &&
      output.deployment_service_principal_object_id == var.deployment_service_principal_object_id
    )
    error_message = "Identity outputs must refer to bootstrap inputs, not a newly managed application."
  }
}
