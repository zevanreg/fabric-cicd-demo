resource "azurerm_resource_group" "fabric" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_fabric_capacity" "this" {
  name                   = var.capacity_name
  resource_group_name    = azurerm_resource_group.fabric.name
  location               = azurerm_resource_group.fabric.location
  administration_members = distinct(concat(var.capacity_admins, [var.deployment_service_principal_object_id]))
  tags                   = var.tags

  sku {
    name = var.capacity_sku
    tier = "Fabric"
  }
}

# The Fabric capacity UUID differs from the ARM resource ID, so look it up in Fabric by name.
data "fabric_capacity" "this" {
  display_name = azurerm_fabric_capacity.this.name
  depends_on   = [azurerm_fabric_capacity.this]

  lifecycle {
    postcondition {
      condition     = self.state == "Active"
      error_message = "Fabric capacity is not Active. Resume it before managing workspaces."
    }
  }
}

resource "fabric_workspace" "this" {
  for_each = var.environments

  display_name = "${var.workspace_prefix}-${each.key}"
  description  = "Date demo ${each.key} workspace. Managed by Terraform."
  capacity_id  = data.fabric_capacity.this.id
}

data "azuread_users" "workspace_access" {
  user_principal_names = var.workspace_access_user_principal_names
}

locals {
  workspace_access_assignments = {
    for assignment in setproduct(var.environments, data.azuread_users.workspace_access.users) :
    "${assignment[0]}:${lower(assignment[1].user_principal_name)}" => {
      environment = assignment[0]
      principal = {
        id   = assignment[1].object_id
        type = "User"
      }
    }
  }
}

resource "fabric_workspace_role_assignment" "workspace_access" {
  for_each = local.workspace_access_assignments

  workspace_id = fabric_workspace.this[each.value.environment].id
  principal    = each.value.principal
  role         = each.value.environment == "developer1" ? "Admin" : "Viewer"
}
