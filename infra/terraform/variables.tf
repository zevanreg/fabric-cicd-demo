variable "subscription_id" {
  description = "Azure subscription that hosts the Fabric capacity."
  type        = string
}

variable "deployment_application_client_id" {
  description = "Client ID of the deployment application created by bootstrap."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.deployment_application_client_id))
    error_message = "deployment_application_client_id must be a UUID from bootstrap."
  }
}

variable "deployment_service_principal_object_id" {
  description = "Object ID (not client ID) of the bootstrap deployment service principal granted Fabric workspace Contributor."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.deployment_service_principal_object_id))
    error_message = "deployment_service_principal_object_id must be a UUID from bootstrap."
  }
}

variable "environments" {
  description = "Workspace keys, matching the GitHub environments configured by bootstrap."
  type        = set(string)
  default     = ["developer1", "dev", "test", "prod"]

  validation {
    condition     = length(var.environments) > 0 && length(var.environments) <= 10
    error_message = "Specify 1-10 environments matching bootstrap."
  }

  validation {
    condition     = alltrue([for environment in var.environments : can(regex("^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$", environment))])
    error_message = "Environment names must be 1-80 letters, digits, dots, underscores or hyphens, starting with a letter or digit."
  }
}

variable "location" {
  description = "Azure region for the resource group and Fabric capacity."
  type        = string
  default     = "swedencentral"
}

variable "resource_group_name" {
  description = "Resource group that holds the Fabric capacity."
  type        = string
  default     = "rg-fabric-cicd-demo-workload"
}

variable "capacity_name" {
  description = "Fabric capacity name: 3-63 lowercase letters and digits, starting with a letter."
  type        = string
  default     = "fccicddemoswedencentral1"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{2,62}$", var.capacity_name))
    error_message = "capacity_name must be 3-63 lowercase letters and digits, starting with a letter."
  }
}

variable "capacity_sku" {
  description = "Fabric capacity SKU. F2 is the smallest size and is sufficient for the demo."
  type        = string
  default     = "F2"

  validation {
    condition     = contains(["F2", "F4", "F8", "F16", "F32", "F64", "F128", "F256", "F512", "F1024", "F2048"], var.capacity_sku)
    error_message = "capacity_sku must be one of F2-F2048."
  }
}

variable "capacity_admins" {
  description = "Capacity administrators: Entra user UPNs or service principal object IDs. Must include the identity running Terraform."
  type        = list(string)

  validation {
    condition     = length(var.capacity_admins) > 0
    error_message = "At least one capacity administrator is required."
  }
}

variable "workspace_prefix" {
  description = "Stable prefix for workspace names, including the separate developer1 feature-development workspace."
  type        = string
  default     = "fabric-cicd-demo"

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9._-]{0,199}$", var.workspace_prefix))
    error_message = "workspace_prefix must be 1-200 letters, digits, dots, underscores or hyphens."
  }
}

variable "tags" {
  description = "Tags applied to the resource group and capacity."
  type        = map(string)
  default = {
    workload = "fabric-cicd-demo"
  }
}
