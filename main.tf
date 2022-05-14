terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.6.0"
    }
  }
}

# Azurerm Provider configuration
provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy = true
    }
  }
}

variable "location" {
  default = "centralus"
  # can be one of : australiacentral,australiacentral2,australiaeast,australiasoutheast,brazilsouth,brazilsoutheast,brazilus,canadacentral,canadaeast,centralindia,centralus,centraluseuap,eastasia,eastus,eastus2,eastus2euap,francecentral,francesouth,germanynorth,germanywestcentral,japaneast,japanwest,jioindiacentral,jioindiawest,koreacentral,koreasouth,northcentralus,northeurope,norwayeast,norwaywest,qatarcentral,southafricanorth,southafricawest,southcentralus,southeastasia,southindia,swedencentral,swedensouth,switzerlandnorth,switzerlandwest,uaecentral,uaenorth,uksouth,ukwest,westcentralus,westeurope,westindia,westus,westus2,westus3,israelcentral,italynorth,polandcentral,taiwannorth,taiwannorthwest
  # but must be a location where AppService service is available
}

variable "container-image-name" {
  description = "Name of the Docker's image to be extracted, pushed to the remote repository and run on by the App Service container."
  type     = string
  #nullable = false # For Terraform >=v1.1 only
}

variable "container-file-name" {
  description = "Path and name of the application's Docker image to be used for the App Service container (eg: 'my-image.tar'). "
  type     = string
  #nullable = false # For Terraform >=v1.1 only
}

variable "application-prefix" {
  description = "The solution name to be applied as prefix for all resource creation. Pref in [a-z0-9-] format (eg: 'my-app')."
  type     = string
  #nullable = false # For Terraform >=v1.1 only
}

variable "container-image-tag" {
  default = "node"
}

variable "container-image-tag-slot" {
  default = "latest"
}

variable "container-registry-name" {
  description = "The name of the Azure Container Registry"
  type     = string
  #nullable = false # For Terraform >=v1.1 only
}

data "azurerm_client_config" "current" {}

#### Resource Group ####
resource "azurerm_resource_group" "resource-group" {
  name     = "${var.application-prefix}-rg"
  location = var.location
}

#### UAI (for encryption) ####
resource "azurerm_user_assigned_identity" "uai" {
  resource_group_name = azurerm_resource_group.resource-group.name
  location            = azurerm_resource_group.resource-group.location
  name                = "registry-uai"

  depends_on = [azurerm_resource_group.resource-group]
}

#### Key Vault (for registry encryption) ####

resource "azurerm_key_vault" "key-vault" {
  name                        = "${var.application-prefix}-keyvault-4"
  location                    = azurerm_resource_group.resource-group.location
  resource_group_name         = azurerm_resource_group.resource-group.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = true
  #  enable_rbac_authorization   = true

  depends_on = [azurerm_resource_group.resource-group]

  sku_name = "premium"

  # Adding TAG's to your Azure resources
  tags = {
    ProjectName = var.application-prefix
    Env         = "dev"
  }
}

resource "azurerm_key_vault_access_policy" "keyvault-policy-uai" {
  key_vault_id = azurerm_key_vault.key-vault.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_user_assigned_identity.uai.principal_id

  key_permissions = [
    "Backup",
    "Create",
    "Decrypt",
    "Delete",
    "Encrypt",
    "Get",
    "Import",
    "List",
    "Purge",
    "Recover",
    "Restore",
    "Sign",
    "UnwrapKey",
    "Update",
    "Verify",
    "WrapKey",
  ]

  secret_permissions = [
    "Get",
    "Set",
  ]

  storage_permissions = [
    "Get",
    "Set",
  ]
}

resource "azurerm_key_vault_access_policy" "keyvault-policy-tenant" {
  key_vault_id = azurerm_key_vault.key-vault.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  key_permissions = [
    "Backup",
    "Create",
    "Decrypt",
    "Delete",
    "Encrypt",
    "Get",
    "Import",
    "List",
    "Purge",
    "Recover",
    "Restore",
    "Sign",
    "UnwrapKey",
    "Update",
    "Verify",
    "WrapKey",
  ]

  secret_permissions = [
    "Get",
    "Set",
  ]

  storage_permissions = [
    "Get",
    "Set",
  ]
}

#### Key Vault Registry Key ####
resource "azurerm_key_vault_key" "generated-registry-key" {
  name         = "registry-key"
  key_vault_id = azurerm_key_vault.key-vault.id

  depends_on = [
    azurerm_resource_group.resource-group, azurerm_key_vault.key-vault,
    azurerm_key_vault_access_policy.keyvault-policy-tenant, azurerm_key_vault_access_policy.keyvault-policy-uai
  ]

  key_type = "RSA"
  key_size = 2048

  key_opts = [
    "decrypt",
    "encrypt",
    "sign",
    "unwrapKey",
    "verify",
    "wrapKey",
  ]
}

#### Container Registry ####
module "container-registry" {
  source  = "kumarvna/container-registry/azurerm"
  version = "1.0.0"

  resource_group_name = azurerm_resource_group.resource-group.name
  #create_resource_group = true
  location            = var.location
  depends_on          = [azurerm_key_vault.key-vault, azurerm_key_vault_key.generated-registry-key]

  # Azure Container Registry configuration
  # The `Classic` SKU is Deprecated and will no longer be available for new resources
  container_registry_config = {
    name          = var.container-registry-name
    admin_enabled = true
    sku           = "Premium"
  }

  identity_ids = [azurerm_user_assigned_identity.uai.id]

  encryption = {
    key_vault_key_id   = azurerm_key_vault_key.generated-registry-key.id
    identity_client_id = azurerm_user_assigned_identity.uai.client_id
  }

  # Set a retention policy with care--deleted image data is UNRECOVERABLE.
  # A retention policy for untagged manifests is currently a preview feature of Premium container registries
  # The retention policy applies only to untagged manifests with timestamps after the policy is enabled. Default is `7` days.
  retention_policy = {
    days    = 10
    enabled = true
  }

  # (Optional) To enable Azure Monitoring for Azure MySQL database
  # (Optional) Specify `storage_account_name` to save monitoring logs to storage.
  #log_analytics_workspace_name = "loganalytics-we-sharedtest2" # TODO

  # Adding TAG's to your Azure resources
  tags = {
    ProjectName = var.application-prefix
    Env         = "dev"
  }
}

#### Push Devops image ####
resource "null_resource" "docker_push" {
  depends_on = [module.container-registry]

  triggers = {
    #always_run = timestamp() # Uncomment to push new image (temp fix)
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
        az acr login -n ${var.container-registry-name}
        docker image load --input ${var.container-file-name}
        docker image tag ${var.container-image-name}:latest ${var.container-registry-name}.azurecr.io/${var.container-image-name}:latest
        docker push ${var.container-registry-name}.azurecr.io/${var.container-image-name}:latest
        echo "Docker image '${var.container-image-name}:latest' from file '${var.container-file-name}' successfully uploaded to ACR repository '${var.container-registry-name}.azurecr.io'"
      EOT
  }
}

locals {
  env_variables = {
    DOCKER_REGISTRY_SERVER_URL      = "https://${var.container-registry-name}.azurecr.io"
    DOCKER_REGISTRY_SERVER_USERNAME = module.container-registry.container_registry_admin_username
    DOCKER_REGISTRY_SERVER_PASSWORD = module.container-registry.container_registry_admin_password
    WEBSITES_PORT                   = 8000
  }
}

##### App Service Plan #####
resource "azurerm_service_plan" "app-service-plan" {
  name                = "${var.application-prefix}-app-service-plan"
  location            = azurerm_resource_group.resource-group.location
  resource_group_name = azurerm_resource_group.resource-group.name
  os_type             = "Linux"
  sku_name            = "S1"

  depends_on = [azurerm_resource_group.resource-group]
}

##### App Service #####
resource "azurerm_linux_web_app" "app-service" {
  name                = "${var.application-prefix}-app-service"
  location            = azurerm_resource_group.resource-group.location
  resource_group_name = azurerm_resource_group.resource-group.name
  service_plan_id     = azurerm_service_plan.app-service-plan.id

  depends_on = [azurerm_service_plan.app-service-plan, null_resource.docker_push]

  site_config {
    always_on = "true"

    application_stack {
      docker_image     = "${var.container-registry-name}.azurecr.io/${var.container-image-name}"
      docker_image_tag = var.container-image-tag
    }

    #health_check_path = "/health" # health check required in order that internal app service plan loadbalancer do not loadbalance on instance down # TODO
  }

  identity {
    type         = "SystemAssigned, UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.uai.id]
  }

  app_settings = local.env_variables

  # Adding TAG's to your Azure resources
  tags = {
    ProjectName = var.application-prefix
    Env         = "dev"
  }
}

#### Staging for 0 downtime ####
resource "azurerm_linux_web_app_slot" "app-service-staging" {
  name           = "${var.application-prefix}-app-service-staging-slot"
  app_service_id = azurerm_linux_web_app.app-service.id

  depends_on = [azurerm_linux_web_app.app-service]

  site_config {
    always_on = "true"

    application_stack {
      docker_image     = "${var.container-registry-name}.azurecr.io/${var.container-image-name}"
      docker_image_tag = var.container-image-tag-slot
    }

    #health_check_path = "/health" # health check required in order that internal app service plan loadbalancer do not loadbalance on instance down # TODO
  }

  identity {
    type         = "SystemAssigned, UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.uai.id]
  }

  app_settings = local.env_variables

  # Adding TAG's to your Azure resources
  tags = {
    ProjectName = var.application-prefix
    Env         = "dev"
  }
}

#### Monitoring ####
resource "azurerm_application_insights" "app-insights" {
  name                = "${var.application-prefix}-insights"
  location            = azurerm_resource_group.resource-group.location
  resource_group_name = azurerm_resource_group.resource-group.name

  depends_on = [azurerm_resource_group.resource-group]

  application_type   = "other" # Depends on the application
  disable_ip_masking = true
  retention_in_days  = 730
}


output "app_service_default_hostname" {
  value = "https://${azurerm_linux_web_app.app-service.default_hostname}"
}
