variable "subscription_id" {
  description = "Azure subscription for state storage and deployments. The shared deployment identity receives Contributor at this scope."
  type        = string
}

variable "deployment_application_display_name" {
  description = "Display name for the shared Entra application used by GitHub Actions for Azure provisioning and Fabric item deployment."
  type        = string
  default     = "fabric-cicd-demo-deploy"

  validation {
    condition     = length(trimspace(var.deployment_application_display_name)) > 0
    error_message = "deployment_application_display_name must not be empty."
  }
}

variable "github_repository" {
  description = "GitHub monorepo (infrastructure and workloads) allowed to use the shared application's OIDC credentials, in owner/repository format."
  type        = string

  validation {
    condition     = can(regex("^[^/:[:space:]]+/[^/:[:space:]]+$", var.github_repository))
    error_message = "github_repository must use the owner/repository format."
  }
}

variable "github_owner_id" {
  description = "Immutable numeric GitHub organization or user ID that owns the repository."
  type        = string

  validation {
    condition     = can(regex("^[1-9][0-9]*$", var.github_owner_id))
    error_message = "github_owner_id must be a positive numeric GitHub owner ID."
  }
}

variable "github_repository_id" {
  description = "Immutable numeric GitHub repository ID."
  type        = string

  validation {
    condition     = can(regex("^[1-9][0-9]*$", var.github_repository_id))
    error_message = "github_repository_id must be a positive numeric GitHub repository ID."
  }
}

variable "environments" {
  description = "Fabric workspace keys passed to the main configuration."
  type        = set(string)
  default     = ["developer1", "dev", "test", "prod"]

  validation {
    condition     = length(var.environments) > 0 && length(var.environments) <= 10
    error_message = "Specify 1-10 Fabric workspace environments."
  }

  validation {
    condition     = alltrue([for environment in var.environments : can(regex("^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$", environment))])
    error_message = "Environment names must be 1-80 letters, digits, dots, underscores or hyphens, starting with a letter or digit."
  }
}

variable "github_environments" {
  description = "GitHub environments trusted to run CI/CD workflows. Developer-only workspaces do not need OIDC credentials."
  type        = set(string)
  default     = ["dev", "test", "prod"]

  validation {
    condition     = length(var.github_environments) > 0 && length(var.github_environments) <= 19
    error_message = "Specify 1-19 GitHub environments, leaving one Entra federated credential for main-branch infrastructure deployment."
  }

  validation {
    condition     = alltrue([for environment in var.github_environments : can(regex("^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$", environment))])
    error_message = "GitHub environment names must be 1-80 letters, digits, dots, underscores or hyphens, starting with a letter or digit."
  }
}

check "github_environments_have_workspaces" {
  assert {
    condition     = length(setsubtract(var.github_environments, var.environments)) == 0
    error_message = "Every GitHub environment must have a matching Fabric workspace environment."
  }
}

variable "resource_group_name" {
  description = "Dedicated resource group for Terraform state, separate from Fabric resources."
  type        = string
  default     = "rg-fabric-cicd-demo"
}

variable "location" {
  description = "Azure region for Terraform state storage."
  type        = string
  default     = "swedencentral"
}

variable "storage_account_name" {
  description = "Globally unique Terraform state storage account name: 3-24 lowercase letters and digits."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "storage_account_name must be 3-24 lowercase letters and digits."
  }
}

variable "virtual_network_name" {
  description = "Name of the VNet containing the private runner and storage private endpoint."
  type        = string
  default     = "vnet-fabric-cicd-demo-runner"
}

variable "virtual_network_address_space" {
  description = "Address space for the runner VNet."
  type        = string
  default     = "10.42.0.0/16"
}

variable "runner_subnet_address_prefix" {
  description = "Address prefix for the self-hosted runner subnet."
  type        = string
  default     = "10.42.1.0/24"
}

variable "private_endpoint_subnet_address_prefix" {
  description = "Address prefix for the storage private endpoint subnet."
  type        = string
  default     = "10.42.2.0/24"
}

variable "runner_vm_name" {
  description = "Name of the private Windows VM that hosts the infrastructure runner."
  type        = string
  default     = "vm-fabric-infra-runner"

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9-]{0,63}$", var.runner_vm_name))
    error_message = "runner_vm_name must be 1-64 letters, digits, or hyphens."
  }
}

variable "runner_vm_size" {
  description = "Azure VM size for the infrastructure runner."
  type        = string
  default     = "Standard_D2s_v5"
}

variable "runner_admin_username" {
  description = "Administrative username retained for Azure VM recovery operations."
  type        = string
  default     = "runneradmin"

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9._-]{0,19}$", var.runner_admin_username))
    error_message = "runner_admin_username must be a valid Windows username up to 20 characters."
  }
}

variable "github_runner_version" {
  description = "Pinned GitHub Actions runner version installed on the VM."
  type        = string
  default     = "2.338.0"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.github_runner_version))
    error_message = "github_runner_version must use numeric semantic version syntax."
  }
}

variable "github_runner_sha256" {
  description = "SHA-256 checksum for the pinned Windows x64 GitHub Actions runner archive."
  type        = string
  default     = "f48e0750a21812bca5f82de5f7f5aeae71abee647fab5a582f1742d07eba455f"

  validation {
    condition     = can(regex("^[0-9a-f]{64}$", var.github_runner_sha256))
    error_message = "github_runner_sha256 must be a lowercase SHA-256 checksum."
  }
}

variable "tags" {
  description = "Tags applied to Terraform state resources."
  type        = map(string)
  default = {
    workload = "fabric-cicd-demo"
    purpose  = "terraform-state"
  }
}
