resource "azurerm_virtual_network" "runner" {
  name                = var.virtual_network_name
  resource_group_name = azurerm_resource_group.state.name
  location            = azurerm_resource_group.state.location
  address_space       = [var.virtual_network_address_space]
  tags                = var.tags
}

resource "azurerm_network_security_group" "runner" {
  name                = "${var.runner_vm_name}-nsg"
  resource_group_name = azurerm_resource_group.state.name
  location            = azurerm_resource_group.state.location
  tags                = var.tags

  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_public_ip" "runner_egress" {
  name                = "${var.runner_vm_name}-egress-pip"
  resource_group_name = azurerm_resource_group.state.name
  location            = azurerm_resource_group.state.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_nat_gateway" "runner" {
  name                    = "${var.runner_vm_name}-nat"
  resource_group_name     = azurerm_resource_group.state.name
  location                = azurerm_resource_group.state.location
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10
  tags                    = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "runner" {
  nat_gateway_id       = azurerm_nat_gateway.runner.id
  public_ip_address_id = azurerm_public_ip.runner_egress.id
}

resource "azurerm_subnet" "runner" {
  name                 = "snet-runner"
  resource_group_name  = azurerm_resource_group.state.name
  virtual_network_name = azurerm_virtual_network.runner.name
  address_prefixes     = [var.runner_subnet_address_prefix]
}

resource "azurerm_subnet_network_security_group_association" "runner" {
  subnet_id                 = azurerm_subnet.runner.id
  network_security_group_id = azurerm_network_security_group.runner.id
}

resource "azurerm_subnet_nat_gateway_association" "runner" {
  subnet_id      = azurerm_subnet.runner.id
  nat_gateway_id = azurerm_nat_gateway.runner.id
}

resource "azurerm_subnet" "private_endpoints" {
  name                              = "snet-private-endpoints"
  resource_group_name               = azurerm_resource_group.state.name
  virtual_network_name              = azurerm_virtual_network.runner.name
  address_prefixes                  = [var.private_endpoint_subnet_address_prefix]
  private_endpoint_network_policies = "Disabled"
}

resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.state.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  name                 = "${var.virtual_network_name}-blob"
  private_dns_zone_id  = azurerm_private_dns_zone.blob.id
  virtual_network_id   = azurerm_virtual_network.runner.id
  registration_enabled = false
  tags                 = var.tags
}

resource "azurerm_private_endpoint" "state_blob" {
  name                = "${azurerm_storage_account.state.name}-blob-pe"
  resource_group_name = azurerm_resource_group.state.name
  location            = azurerm_resource_group.state.location
  subnet_id           = azurerm_subnet.private_endpoints.id
  tags                = var.tags

  private_service_connection {
    name                           = "${azurerm_storage_account.state.name}-blob"
    private_connection_resource_id = azurerm_storage_account.state.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "blob"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob.id]
  }
}
