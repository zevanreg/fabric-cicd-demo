terraform {
  required_version = ">= 1.8, < 2.0"

  backend "azurerm" {
    use_azuread_auth = true
    use_cli          = true
  }

  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.10"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.9"
    }
    fabric = {
      source  = "microsoft/fabric"
      version = "~> 1.14"
    }
  }
  # NOTE: azurerm does not publish Windows ARM64 builds.
  # On Windows ARM64, use WSL (`wsl terraform init`) or a remote backend on amd64.
}

# Providers authenticate with Azure CLI by default; Fabric role management requires a separate administrator identity.
provider "azuread" {}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

provider "fabric" {}
