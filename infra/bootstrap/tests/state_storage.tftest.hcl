variables {
  subscription_id      = "33333333-3333-4333-8333-333333333333"
  storage_account_name = "fabricstatetest123"
  resource_group_name  = "rg-fabric-date-tfstate"
  github_repository    = "example/fabric-cicd-demo"
  environments         = ["developer1", "dev", "test", "prod"]
  github_environments  = ["dev", "test", "prod"]
}

mock_provider "azuread" {
  mock_resource "azuread_application_registration" {
    defaults = {
      id        = "/applications/44444444-4444-4444-8444-444444444444"
      client_id = "55555555-5555-4555-8555-555555555555"
    }
  }

  mock_resource "azuread_service_principal" {
    defaults = {
      object_id = "66666666-6666-4666-8666-666666666666"
    }
  }
}

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      object_id = "11111111-1111-4111-8111-111111111111"
      tenant_id = "22222222-2222-4222-8222-222222222222"
    }
  }

  mock_resource "azurerm_storage_account" {
    defaults = {
      id = "/subscriptions/33333333-3333-4333-8333-333333333333/resourceGroups/rg-fabric-date-tfstate/providers/Microsoft.Storage/storageAccounts/fabricstatetest123"
    }
  }
}

run "state_storage" {
  command = apply

  assert {
    condition = (
      azurerm_storage_account.state.shared_access_key_enabled == false &&
      azurerm_storage_account.state.allow_nested_items_to_be_public == false &&
      azurerm_storage_account.state.min_tls_version == "TLS1_2" &&
      azurerm_storage_container.state.container_access_type == "private"
    )
    error_message = "State storage must require Entra authentication, disallow public blobs, and enforce TLS 1.2."
  }

  assert {
    condition = (
      azurerm_role_assignment.state_deployment.principal_id == azuread_service_principal.deployment.object_id &&
      azurerm_role_assignment.state_deployment.scope == azurerm_storage_account.state.id &&
      azurerm_role_assignment.state_deployment.role_definition_name == "Storage Blob Data Contributor" &&
      azurerm_role_assignment.deployment_contributor.principal_id == azuread_service_principal.deployment.object_id &&
      azurerm_role_assignment.deployment_contributor.scope == "/subscriptions/${var.subscription_id}" &&
      azurerm_role_assignment.deployment_contributor.role_definition_name == "Contributor"
    )
    error_message = "The bootstrapped deployment identity must have subscription Contributor and state Blob Data Contributor access."
  }

  assert {
    condition = (
      toset(keys(azuread_application_federated_identity_credential.github_environment)) == var.github_environments &&
      alltrue([
        for environment, credential in azuread_application_federated_identity_credential.github_environment :
        credential.subject == "repo:${var.github_repository}:environment:${environment}" &&
        credential.application_id == azuread_application_registration.deployment.id &&
        credential.issuer == "https://token.actions.githubusercontent.com" &&
        length(credential.audiences) == 1 && one(credential.audiences) == "api://AzureADTokenExchange"
      ])
    )
    error_message = "Every CI/CD environment must have an exact environment-scoped GitHub OIDC credential on the shared app."
  }

  assert {
    condition = (
      jsondecode(output.deployment_config).deployment_application_client_id == azuread_application_registration.deployment.client_id &&
      jsondecode(output.deployment_config).deployment_service_principal_object_id == azuread_service_principal.deployment.object_id &&
      toset(jsondecode(output.deployment_config).environments) == var.environments
    )
    error_message = "The main configuration must receive the bootstrapped application, service principal, and environment set."
  }

  assert {
    condition = (
      azurerm_storage_account.state.blob_properties[0].versioning_enabled &&
      azurerm_storage_account.state.blob_properties[0].delete_retention_policy[0].days == 30 &&
      azurerm_storage_account.state.blob_properties[0].container_delete_retention_policy[0].days == 30
    )
    error_message = "State storage must retain versions and allow recovery of deleted blobs and containers for 30 days."
  }

  assert {
    condition = (
      azurerm_role_assignment.state_operator.principal_id == data.azurerm_client_config.current.object_id &&
      azurerm_role_assignment.state_operator.role_definition_name == "Storage Blob Data Contributor"
    )
    error_message = "The bootstrap operator must receive Blob Data Contributor access."
  }

  assert {
    condition     = output.backend_config == <<-EOT
      resource_group_name  = "rg-fabric-date-tfstate"
      storage_account_name = "fabricstatetest123"
      container_name       = "tfstate"
      key                  = "fabric-infrastructure.tfstate"
      subscription_id      = "33333333-3333-4333-8333-333333333333"
      tenant_id            = "22222222-2222-4222-8222-222222222222"
    EOT
    error_message = "Backend configuration must identify the correct account, private container, state key, subscription, and tenant."
  }
}

run "reject_excess_credentials" {
  command = plan

  variables {
    environments        = [for index in range(21) : "env${index}"]
    github_environments = [for index in range(21) : "env${index}"]
  }

  expect_failures = [var.environments, var.github_environments]
}

run "reject_invalid_environment" {
  command = plan

  variables {
    environments = ["dev:invalid"]
  }

  expect_failures = [var.environments]
}

run "reject_unmanaged_github_environment" {
  command = plan

  variables {
    github_environments = ["dev", "preview"]
  }

  expect_failures = [check.github_environments_have_workspaces]
}
