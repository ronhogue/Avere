terraform {
  required_version = ">= 1.4.4"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.51.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~>2.36.0"
    }
  }
  backend "azurerm" {
    key = "5.render.manager"
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    virtual_machine {
      delete_os_disk_on_deletion     = true
      graceful_shutdown              = false
      skip_shutdown_and_force_delete = false
    }
  }
}

module "global" {
  source = "../0.global/module"
}

variable "resourceGroupName" {
  type = string
}

variable "virtualMachines" {
  type = list(object(
    {
      name = string
      machine = object(
        {
          size = string
          image = object(
            {
              id = string
              plan = object(
                {
                  publisher = string
                  product   = string
                  name      = string
                }
              )
            }
          )
        }
      )
      network = object(
        {
          enableAcceleratedNetworking = bool
        }
      )
      operatingSystem = object(
        {
          type = string
          disk = object(
            {
              storageType = string
              cachingType = string
            }
          )
        }
      )
      adminLogin = object(
        {
          userName            = string
          userPassword        = string
          sshPublicKey        = string
          disablePasswordAuth = bool
        }
      )
      customExtension = object(
        {
          enable   = bool
          name     = string
          fileName = string
          parameters = object(
            {
              qubeLicense = object(
                {
                  userName     = string
                  userPassword = string
                }
              )
              autoScale = object(
                {
                  enable                   = bool
                  fileName                 = string
                  scaleSetName             = string
                  resourceGroupName        = string
                  jobWaitThresholdSeconds  = number
                  detectionIntervalSeconds = number
                }
              )
              cycleCloud = object(
                {
                  enable             = bool
                  storageAccountName = string
                }
              )
            }
          )
        }
      )
      monitorExtension = object(
        {
          enable = bool
        }
      )
    }
  ))
}

variable "servicePassword" {
  type = string
}

variable "privateDns" {
  type = object(
    {
      aRecordName = string
      ttlSeconds  = number
    }
  )
}

variable "computeNetwork" {
  type = object(
    {
      name               = string
      subnetName         = string
      resourceGroupName  = string
      privateDnsZoneName = string
    }
  )
}

variable "computeGallery" {
  type = object(
    {
      name                  = string
      resourceGroupName     = string
      imageVersionIdDefault = string
    }
  )
}

data "azurerm_client_config" "provider" {}

data "azurerm_user_assigned_identity" "studio" {
  name                = module.global.managedIdentity.name
  resource_group_name = module.global.resourceGroupName
}

data "azurerm_key_vault" "studio" {
  count               = module.global.keyVault.name != "" ? 1 : 0
  name                = module.global.keyVault.name
  resource_group_name = module.global.resourceGroupName
}

data "azurerm_key_vault_secret" "admin_username" {
  count        = module.global.keyVault.name != "" ? 1 : 0
  name         = module.global.keyVault.secretName.adminUsername
  key_vault_id = data.azurerm_key_vault.studio[0].id
}

data "azurerm_key_vault_secret" "admin_password" {
  count        = module.global.keyVault.name != "" ? 1 : 0
  name         = module.global.keyVault.secretName.adminPassword
  key_vault_id = data.azurerm_key_vault.studio[0].id
}

data "azurerm_key_vault_secret" "service_password" {
  count        = module.global.keyVault.name != "" ? 1 : 0
  name         = module.global.keyVault.secretName.servicePassword
  key_vault_id = data.azurerm_key_vault.studio[0].id
}

data "azurerm_log_analytics_workspace" "monitor" {
  count               = module.global.monitorWorkspace.name != "" ? 1 : 0
  name                = module.global.monitorWorkspace.name
  resource_group_name = module.global.resourceGroupName
}

data "terraform_remote_state" "network" {
  backend = "azurerm"
  config = {
    resource_group_name  = module.global.resourceGroupName
    storage_account_name = module.global.rootStorage.accountName
    container_name       = module.global.rootStorage.containerName.terraform
    key                  = "1.network"
  }
}

data "terraform_remote_state" "image" {
  backend = "azurerm"
  config = {
    resource_group_name  = module.global.resourceGroupName
    storage_account_name = module.global.rootStorage.accountName
    container_name       = module.global.rootStorage.containerName.terraform
    key                  = "4.image.builder"
  }
}

data "azurerm_virtual_network" "compute" {
  name                = !local.stateExistsNetwork ? var.computeNetwork.name : data.terraform_remote_state.network.outputs.computeNetwork.name
  resource_group_name = !local.stateExistsNetwork ? var.computeNetwork.resourceGroupName : data.terraform_remote_state.network.outputs.resourceGroupName
}

data "azurerm_subnet" "farm" {
  name                 = !local.stateExistsNetwork ? var.computeNetwork.subnetName : data.terraform_remote_state.network.outputs.computeNetwork.subnets[data.terraform_remote_state.network.outputs.computeNetwork.subnetIndex.farm].name
  resource_group_name  = data.azurerm_virtual_network.compute.resource_group_name
  virtual_network_name = data.azurerm_virtual_network.compute.name
}

data "azurerm_private_dns_zone" "network" {
  name                = !local.stateExistsNetwork ? var.computeNetwork.privateDnsZoneName : data.terraform_remote_state.network.outputs.privateDns.zoneName
  resource_group_name = data.azurerm_virtual_network.compute.resource_group_name
}

locals {
  servicePassword        = var.servicePassword != "" ? var.servicePassword : data.azurerm_key_vault_secret.service_password[0].value
  stateExistsNetwork     = var.computeNetwork.name != "" ? false : try(length(data.terraform_remote_state.network.outputs) > 0, false)
  stateExistsImage       = var.computeGallery.name != "" ? false : try(length(data.terraform_remote_state.image.outputs) > 0, false)
  imageGalleryName       = !local.stateExistsImage ? var.computeGallery.name : try(data.terraform_remote_state.image.outputs.imageGallery.name, "")
  imageResourceGroupName = !local.stateExistsImage ? var.computeGallery.resourceGroupName : try(data.terraform_remote_state.image.outputs.resourceGroupName, "")
  imageVersionIdDefault  = !local.stateExistsImage ? var.computeGallery.imageVersionIdDefault : "/subscriptions/${data.azurerm_client_config.provider.subscription_id}/resourceGroups/${local.imageResourceGroupName}/providers/Microsoft.Compute/galleries/${local.imageGalleryName}/images/Linux/versions/0.0.0"
  virtualMachinesLinux = [
    for virtualMachine in var.virtualMachines : merge(virtualMachine, {
      machine = {
        size = virtualMachine.machine.size
        image = {
          id = virtualMachine.machine.image.id
          plan = {
            publisher = virtualMachine.machine.image.plan.publisher != "" ? virtualMachine.machine.image.plan.publisher : try(lower(data.terraform_remote_state.image.outputs.imageDefinitionsLinux[0].publisher), "")
            product   = virtualMachine.machine.image.plan.product != "" ? virtualMachine.machine.image.plan.product : try(lower(data.terraform_remote_state.image.outputs.imageDefinitionsLinux[0].offer), "")
            name      = virtualMachine.machine.image.plan.name != "" ? virtualMachine.machine.image.plan.name : try(lower(data.terraform_remote_state.image.outputs.imageDefinitionsLinux[0].sku), "")
          }
        }
      }
    }) if virtualMachine.name != "" && virtualMachine.operatingSystem.type == "Linux"
  ]
  virtualMachineNames = [
    for virtualMachine in var.virtualMachines : virtualMachine.name if virtualMachine.name != ""
  ]
}

resource "azurerm_resource_group" "scheduler" {
  name     = var.resourceGroupName
  location = module.global.regionName
}

resource "azurerm_role_assignment" "scheduler" {
  role_definition_name = "Virtual Machine Contributor" # https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#virtual-machine-contributor
  principal_id         = data.azurerm_user_assigned_identity.studio.principal_id
  scope                = "/subscriptions/${data.azurerm_client_config.provider.subscription_id}"
}

#########################################################################
# Virtual Machines (https://learn.microsoft.com/azure/virtual-machines) #
#########################################################################

resource "azurerm_network_interface" "scheduler" {
  for_each = {
    for virtualMachine in var.virtualMachines : virtualMachine.name => virtualMachine if virtualMachine.name != ""
  }
  name                = each.value.name
  resource_group_name = azurerm_resource_group.scheduler.name
  location            = azurerm_resource_group.scheduler.location
  ip_configuration {
    name                          = "ipConfig"
    subnet_id                     = data.azurerm_subnet.farm.id
    private_ip_address_allocation = "Dynamic"
  }
  enable_accelerated_networking = each.value.network.enableAcceleratedNetworking
}

resource "azurerm_linux_virtual_machine" "scheduler" {
  for_each = {
    for virtualMachine in local.virtualMachinesLinux : virtualMachine.name => virtualMachine
  }
  name                            = each.value.name
  resource_group_name             = azurerm_resource_group.scheduler.name
  location                        = azurerm_resource_group.scheduler.location
  source_image_id                 = each.value.machine.image.id
  size                            = each.value.machine.size
  admin_username                  = module.global.keyVault.name != "" ? data.azurerm_key_vault_secret.admin_username[0].value : each.value.adminLogin.userName
  admin_password                  = module.global.keyVault.name != "" ? data.azurerm_key_vault_secret.admin_password[0].value : each.value.adminLogin.userPassword
  disable_password_authentication = each.value.adminLogin.disablePasswordAuth
  custom_data = base64encode(
    templatefile(each.value.customExtension.parameters.autoScale.fileName, merge(each.value.customExtension.parameters,
      { renderManager = module.global.renderManager }
    ))
  )
  network_interface_ids = [
    "${azurerm_resource_group.scheduler.id}/providers/Microsoft.Network/networkInterfaces/${each.value.name}"
  ]
  os_disk {
    storage_account_type = each.value.operatingSystem.disk.storageType
    caching              = each.value.operatingSystem.disk.cachingType
  }
  identity {
    type = "UserAssigned"
    identity_ids = [
      data.azurerm_user_assigned_identity.studio.id
    ]
  }
  dynamic plan {
    for_each = each.value.machine.image.plan.name == "" ? [] : [1]
    content {
      publisher = each.value.machine.image.plan.publisher
      product   = each.value.machine.image.plan.product
      name      = each.value.machine.image.plan.name
    }
  }
  dynamic admin_ssh_key {
    for_each = each.value.adminLogin.sshPublicKey == "" ? [] : [1]
    content {
      username   = each.value.adminLogin.userName
      public_key = each.value.adminLogin.sshPublicKey
    }
  }
  depends_on = [
    azurerm_network_interface.scheduler
  ]
}

resource "azurerm_virtual_machine_extension" "initialize_linux" {
  for_each = {
    for virtualMachine in var.virtualMachines : virtualMachine.name => virtualMachine if virtualMachine.name != "" && virtualMachine.customExtension.enable && virtualMachine.operatingSystem.type == "Linux"
  }
  name                       = each.value.customExtension.name
  type                       = "CustomScript"
  publisher                  = "Microsoft.Azure.Extensions"
  type_handler_version       = "2.1"
  auto_upgrade_minor_version = true
  virtual_machine_id         = "${azurerm_resource_group.scheduler.id}/providers/Microsoft.Compute/virtualMachines/${each.value.name}"
  settings = jsonencode({
    "script": "${base64encode(
      templatefile(each.value.customExtension.fileName, merge(each.value.customExtension.parameters,
        { tenantId                 = data.azurerm_client_config.provider.tenant_id },
        { subscriptionId           = data.azurerm_client_config.provider.subscription_id },
        { regionName               = module.global.regionName },
        { binStorageHost           = module.global.binStorage.host },
        { binStorageAuth           = module.global.binStorage.auth },
        { renderManager            = module.global.renderManager },
        { servicePassword          = local.servicePassword },
        { networkResourceGroupName = data.azurerm_virtual_network.compute.resource_group_name },
        { networkName              = data.azurerm_virtual_network.compute.name },
        { networkSubnetName        = data.azurerm_subnet.farm.name },
        { imageResourceGroupName   = local.imageResourceGroupName },
        { imageGalleryName         = local.imageGalleryName },
        { imageVersionIdDefault    = local.imageVersionIdDefault },
        { adminUsername            = module.global.keyVault.name != "" ? data.azurerm_key_vault_secret.admin_username[0].value : each.value.adminLogin.userName },
        { adminPassword            = module.global.keyVault.name != "" ? data.azurerm_key_vault_secret.admin_password[0].value : each.value.adminLogin.userPassword }
      ))
    )}"
  })
  depends_on = [
    azurerm_linux_virtual_machine.scheduler
  ]
}

resource "azurerm_virtual_machine_extension" "monitor_linux" {
  for_each = {
    for virtualMachine in var.virtualMachines : virtualMachine.name => virtualMachine if virtualMachine.name != "" && virtualMachine.monitorExtension.enable && virtualMachine.operatingSystem.type == "Linux" && module.global.monitorWorkspace.name != ""
  }
  name                       = "Monitor"
  type                       = "AzureMonitorLinuxAgent"
  publisher                  = "Microsoft.Azure.Monitor"
  type_handler_version       = "1.21"
  auto_upgrade_minor_version = true
  virtual_machine_id         = "${azurerm_resource_group.scheduler.id}/providers/Microsoft.Compute/virtualMachines/${each.value.name}"
  settings = jsonencode({
    "workspaceId": data.azurerm_log_analytics_workspace.monitor[0].workspace_id
  })
  protected_settings = jsonencode({
    "workspaceKey": data.azurerm_log_analytics_workspace.monitor[0].primary_shared_key
  })
  depends_on = [
    azurerm_linux_virtual_machine.scheduler
  ]
}

resource "azurerm_windows_virtual_machine" "scheduler" {
  for_each = {
    for virtualMachine in var.virtualMachines : virtualMachine.name => virtualMachine if virtualMachine.name != "" && virtualMachine.operatingSystem.type == "Windows"
  }
  name                = each.value.name
  resource_group_name = azurerm_resource_group.scheduler.name
  location            = azurerm_resource_group.scheduler.location
  source_image_id     = each.value.machine.image.id
  size                = each.value.machine.size
  admin_username      = module.global.keyVault.name != "" ? data.azurerm_key_vault_secret.admin_username[0].value : each.value.adminLogin.userName
  admin_password      = module.global.keyVault.name != "" ? data.azurerm_key_vault_secret.admin_password[0].value : each.value.adminLogin.userPassword
  custom_data = base64encode(
    templatefile(each.value.customExtension.parameters.autoScale.fileName, merge(each.value.customExtension.parameters,
      { renderManager   = module.global.renderManager },
      { servicePassword = local.servicePassword }
    ))
  )
  network_interface_ids = [
    "${azurerm_resource_group.scheduler.id}/providers/Microsoft.Network/networkInterfaces/${each.value.name}"
  ]
  os_disk {
    storage_account_type = each.value.operatingSystem.disk.storageType
    caching              = each.value.operatingSystem.disk.cachingType
  }
  identity {
    type = "UserAssigned"
    identity_ids = [
      data.azurerm_user_assigned_identity.studio.id
    ]
  }
  depends_on = [
    azurerm_network_interface.scheduler
  ]
}

resource "azurerm_virtual_machine_extension" "initialize_windows" {
  for_each = {
    for virtualMachine in var.virtualMachines : virtualMachine.name => virtualMachine if virtualMachine.name != "" && virtualMachine.customExtension.enable && virtualMachine.operatingSystem.type == "Windows"
  }
  name                       = each.value.customExtension.name
  type                       = "CustomScriptExtension"
  publisher                  = "Microsoft.Compute"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true
  virtual_machine_id         = "${azurerm_resource_group.scheduler.id}/providers/Microsoft.Compute/virtualMachines/${each.value.name}"
  settings = jsonencode({
    "commandToExecute": "PowerShell -ExecutionPolicy Unrestricted -EncodedCommand ${textencodebase64(
      templatefile(each.value.customExtension.fileName, merge(each.value.customExtension.parameters,
        { renderManager   = module.global.renderManager },
        { servicePassword = local.servicePassword }
      )), "UTF-16LE"
    )}"
  })
  depends_on = [
    azurerm_windows_virtual_machine.scheduler
  ]
}

resource "azurerm_virtual_machine_extension" "monitor_windows" {
  for_each = {
    for virtualMachine in var.virtualMachines : virtualMachine.name => virtualMachine if virtualMachine.name != "" && virtualMachine.monitorExtension.enable && virtualMachine.operatingSystem.type == "Windows" && module.global.monitorWorkspace.name != ""
  }
  name                       = "Monitor"
  type                       = "AzureMonitorWindowsAgent"
  publisher                  = "Microsoft.Azure.Monitor"
  type_handler_version       = "1.7"
  auto_upgrade_minor_version = true
  virtual_machine_id         = "${azurerm_resource_group.scheduler.id}/providers/Microsoft.Compute/virtualMachines/${each.value.name}"
  settings = jsonencode({
    "workspaceId": data.azurerm_log_analytics_workspace.monitor[0].workspace_id
  })
  protected_settings = jsonencode({
    "workspaceKey": data.azurerm_log_analytics_workspace.monitor[0].primary_shared_key
  })
  depends_on = [
    azurerm_windows_virtual_machine.scheduler
  ]
}

resource "azurerm_private_dns_a_record" "scheduler" {
  name                = var.privateDns.aRecordName
  resource_group_name = data.azurerm_private_dns_zone.network.resource_group_name
  zone_name           = data.azurerm_private_dns_zone.network.name
  ttl                 = var.privateDns.ttlSeconds
  records = [
    azurerm_network_interface.scheduler[local.virtualMachineNames[0]].private_ip_address
  ]
}

output "resourceGroupName" {
  value = var.resourceGroupName
}

output "virtualMachines" {
  value = var.virtualMachines
}

output "privateDnsRecord" {
  value = azurerm_private_dns_a_record.scheduler
}
