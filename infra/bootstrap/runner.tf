locals {
  runner_bootstrap_script = templatefile("${path.module}/runner-bootstrap.ps1.tftpl", {
    runner_version = var.github_runner_version
    runner_sha256  = var.github_runner_sha256
  })
  runner_bootstrap_command = "powershell.exe -NoLogo -NonInteractive -ExecutionPolicy Bypass -Command \"$script = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('${base64encode(local.runner_bootstrap_script)}')); & ([ScriptBlock]::Create($script))\""
  runner_admin_password    = "Zz9!${random_password.runner_admin.result}"
}

resource "random_password" "runner_admin" {
  length           = 28
  lower            = false
  upper            = false
  numeric          = true
  special          = true
  override_special = "!#$%&*()-_=+[]{}:?"
  min_numeric      = 14
  min_special      = 14
}

resource "azurerm_network_interface" "runner" {
  name                = "${var.runner_vm_name}-nic"
  resource_group_name = azurerm_resource_group.state.name
  location            = azurerm_resource_group.state.location
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.runner.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_windows_virtual_machine" "runner" {
  name                  = var.runner_vm_name
  computer_name         = "fabricrunner"
  resource_group_name   = azurerm_resource_group.state.name
  location              = azurerm_resource_group.state.location
  size                  = var.runner_vm_size
  admin_username        = var.runner_admin_username
  admin_password        = local.runner_admin_password
  network_interface_ids = [azurerm_network_interface.runner.id]
  tags                  = var.tags

  os_disk {
    name                 = "${var.runner_vm_name}-os"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-azure-edition"
    version   = "latest"
  }

  boot_diagnostics {}

  depends_on = [
    azurerm_subnet_nat_gateway_association.runner,
    azurerm_subnet_network_security_group_association.runner,
  ]
}

resource "azurerm_virtual_machine_extension" "runner_bootstrap" {
  name                       = "bootstrap-actions-runner"
  virtual_machine_id         = azurerm_windows_virtual_machine.runner.id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true

  settings = jsonencode({
    commandToExecute = local.runner_bootstrap_command
  })
}
