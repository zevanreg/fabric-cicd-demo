mock_provider "azurerm" {}

mock_provider "azuread" {
  mock_data "azuread_users" {
    defaults = {
      users = [{
        object_id           = "55555555-5555-4555-8555-555555555555"
        user_principal_name = "admin@example.com"
      }]
    }
  }
}

mock_provider "fabric" {
  mock_data "fabric_capacity" {
    defaults = {
      id    = "11111111-1111-4111-8111-111111111111"
      state = "Active"
    }
  }
}

run "bootstrapped_workspace_management" {
  command = plan

  variables {
    subscription_id                        = "22222222-2222-4222-8222-222222222222"
    deployment_application_client_id       = "33333333-3333-4333-8333-333333333333"
    deployment_service_principal_object_id = "44444444-4444-4444-8444-444444444444"
    capacity_admins                        = ["admin@example.com"]
    workspace_prefix                       = "fabric-cicd-demo"
    workspace_access_user_principal_names  = ["admin@example.com"]
    environments                           = ["developer1", "dev", "test", "prod"]
  }

  assert {
    condition = (
      toset(keys(fabric_workspace.this)) == var.environments &&
      length(fabric_workspace_role_assignment.workspace_access) == length(var.environments) * length(var.workspace_access_user_principal_names) &&
      toset(azurerm_fabric_capacity.this.administration_members) == toset(concat(var.capacity_admins, [var.deployment_service_principal_object_id])) &&
      alltrue([
        for environment, workspace in fabric_workspace.this :
        workspace.display_name == "${var.workspace_prefix}-${environment}"
      ]) &&
      alltrue([
        for key, assignment in fabric_workspace_role_assignment.workspace_access :
        assignment.principal.id == "55555555-5555-4555-8555-555555555555" &&
        assignment.principal.type == "User" &&
        assignment.role == (contains(["developer1", "dev"], split(":", key)[0]) ? "Admin" : "Viewer")
      ])
    )
    error_message = "The deployment principal must administer the capacity, every environment must have a workspace, and configured principals must receive Admin on developer1 and dev, and Viewer elsewhere."
  }

  assert {
    condition = (
      output.deployment_application_client_id == var.deployment_application_client_id &&
      output.deployment_service_principal_object_id == var.deployment_service_principal_object_id
    )
    error_message = "Identity outputs must refer to bootstrap inputs, not a newly managed application."
  }
}
