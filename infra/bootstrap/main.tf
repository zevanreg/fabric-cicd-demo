terraform {
  required_version = ">= 1.8, < 2.0"

  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.10"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.9"
    }
  }
}

provider "azuread" {}

provider "azurerm" {
  features {}
  subscription_id     = var.subscription_id
  storage_use_azuread = true
}

data "azurerm_client_config" "current" {}

resource "azuread_application_registration" "deployment" {
  display_name = var.deployment_application_display_name
}

resource "azuread_service_principal" "deployment" {
  client_id = azuread_application_registration.deployment.client_id
}

resource "azuread_application_federated_identity_credential" "github_environment" {
  for_each = var.github_environments

  application_id = azuread_application_registration.deployment.id
  display_name   = "github-${each.key}"
  description    = "GitHub Actions deployment from the ${each.key} environment."
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_repository}:environment:${each.key}"
}

resource "azurerm_role_assignment" "deployment_contributor" {
  scope                            = "/subscriptions/${var.subscription_id}"
  role_definition_name             = "Contributor"
  principal_id                     = azuread_service_principal.deployment.object_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

resource "azurerm_resource_group" "state" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_storage_account" "state" {
  name                            = var.storage_account_name
  resource_group_name             = azurerm_resource_group.state.name
  location                        = azurerm_resource_group.state.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = false
  allow_nested_items_to_be_public = false
  tags                            = var.tags

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_storage_container" "state" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_role_assignment" "state_operator" {
  scope                = azurerm_storage_account.state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "state_deployment" {
  scope                            = azurerm_storage_account.state.id
  role_definition_name             = "Storage Blob Data Contributor"
  principal_id                     = azuread_service_principal.deployment.object_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}
