resource "azurerm_resource_group" "fabric" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_fabric_capacity" "this" {
  name                   = var.capacity_name
  resource_group_name    = azurerm_resource_group.fabric.name
  location               = azurerm_resource_group.fabric.location
  administration_members = var.capacity_admins
  tags                   = var.tags

  sku {
    name = var.capacity_sku
    tier = "Fabric"
  }
}

# The Fabric capacity UUID differs from the ARM resource ID, so look it up in Fabric by name.
data "fabric_capacity" "this" {
  display_name = azurerm_fabric_capacity.this.name

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

resource "fabric_workspace_role_assignment" "deployment_contributor" {
  for_each = fabric_workspace.this

  workspace_id = each.value.id
  principal = {
    id   = var.deployment_service_principal_object_id
    type = "ServicePrincipal"
  }
  role = "Contributor"
}
