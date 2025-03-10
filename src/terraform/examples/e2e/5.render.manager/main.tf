terraform {
  required_version = ">= 1.3.6"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.34.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~>2.31.0"
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
      name        = string
      imageId     = string
      machineSize = string
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
          sshPublicKey        = string
          disablePasswordAuth = bool
        }
      )
      customExtension = object(
        {
          enable   = bool
          fileName = string
          parameters = object(
            {
              fileSystemMountsStorage      = list(string)
              fileSystemMountsStorageCache = list(string)
              fileSystemMountsRoyalRender  = list(string)
              fileSystemMountsDeadline     = list(string)
              autoScale = object(
                {
                  enable                   = bool
                  fileName                 = string
                  scaleSetName             = string
                  resourceGroupName        = string
                  detectionIntervalSeconds = number
                  jobWaitThresholdSeconds  = number
                  workerIdleDeleteSeconds  = number
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
      enableAcceleratedNetworking = bool
    }
  ))
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

data "azurerm_client_config" "current" {}

data "azurerm_user_assigned_identity" "render" {
  name                = module.global.managedIdentityName
  resource_group_name = module.global.resourceGroupName
}

data "azurerm_key_vault" "render" {
  name                = module.global.keyVaultName
  resource_group_name = module.global.resourceGroupName
}

data "azurerm_key_vault_secret" "admin_username" {
  name         = module.global.keyVaultSecretNameAdminUsername
  key_vault_id = data.azurerm_key_vault.render.id
}

data "azurerm_key_vault_secret" "admin_password" {
  name         = module.global.keyVaultSecretNameAdminPassword
  key_vault_id = data.azurerm_key_vault.render.id
}

data "azurerm_log_analytics_workspace" "monitor" {
  name                = module.global.monitorWorkspaceName
  resource_group_name = module.global.resourceGroupName
}

data "terraform_remote_state" "network" {
  backend = "azurerm"
  config = {
    resource_group_name  = module.global.resourceGroupName
    storage_account_name = module.global.storageAccountName
    container_name       = module.global.storageContainerName
    key                  = "1.network"
  }
}

data "terraform_remote_state" "image" {
  backend = "azurerm"
  config = {
    resource_group_name  = module.global.resourceGroupName
    storage_account_name = module.global.storageAccountName
    container_name       = module.global.storageContainerName
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
  stateExistsNetwork     = try(length(data.terraform_remote_state.network.outputs) >= 0, false)
  stateExistsImage       = try(length(data.terraform_remote_state.image.outputs) >= 0, false)
  imageGalleryName       = !local.stateExistsImage ? var.computeGallery.name : try(data.terraform_remote_state.image.outputs.imageGallery.name, "")
  imageResourceGroupName = !local.stateExistsImage ? var.computeGallery.resourceGroupName : try(data.terraform_remote_state.image.outputs.resourceGroupName, "")
  imageVersionIdDefault  = !local.stateExistsImage ? var.computeGallery.imageVersionIdDefault : "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${local.imageResourceGroupName}/providers/Microsoft.Compute/galleries/${local.imageGalleryName}/images/Linux/versions/0.0.0"
  schedulerMachineNames = [
    for virtualMachine in var.virtualMachines : virtualMachine.name if virtualMachine.name != ""
  ]
}

resource "azurerm_resource_group" "scheduler" {
  name     = var.resourceGroupName
  location = module.global.regionName
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
  enable_accelerated_networking = each.value.enableAcceleratedNetworking
}

resource "azurerm_linux_virtual_machine" "scheduler" {
  for_each = {
    for virtualMachine in var.virtualMachines : virtualMachine.name => virtualMachine if virtualMachine.name != "" && virtualMachine.operatingSystem.type == "Linux"
  }
  name                            = each.value.name
  resource_group_name             = azurerm_resource_group.scheduler.name
  location                        = azurerm_resource_group.scheduler.location
  source_image_id                 = each.value.imageId
  size                            = each.value.machineSize
  admin_username                  = each.value.adminLogin.userName
  admin_password                  = data.azurerm_key_vault_secret.admin_password.value
  disable_password_authentication = each.value.adminLogin.disablePasswordAuth
  custom_data = base64encode(
    templatefile(each.value.customExtension.parameters.autoScale.fileName, each.value.customExtension.parameters)
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
      data.azurerm_user_assigned_identity.render.id
    ]
  }
  boot_diagnostics {
    storage_account_uri = null
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

resource "azurerm_virtual_machine_extension" "custom_linux" {
  for_each = {
    for virtualMachine in var.virtualMachines : virtualMachine.name => virtualMachine if virtualMachine.name != "" && virtualMachine.customExtension.enable && virtualMachine.operatingSystem.type == "Linux"
  }
  name                       = "Custom"
  type                       = "CustomScript"
  publisher                  = "Microsoft.Azure.Extensions"
  type_handler_version       = "2.1"
  auto_upgrade_minor_version = true
  virtual_machine_id         = "${azurerm_resource_group.scheduler.id}/providers/Microsoft.Compute/virtualMachines/${each.value.name}"
  settings = jsonencode({
    "script": "${base64encode(
      templatefile(each.value.customExtension.fileName, merge(each.value.customExtension.parameters,
        { tenantId                 = data.azurerm_client_config.current.tenant_id },
        { subscriptionId           = data.azurerm_client_config.current.subscription_id },
        { regionName               = module.global.regionName },
        { renderManager            = module.global.renderManager },
        { networkResourceGroupName = data.azurerm_virtual_network.compute.resource_group_name },
        { networkName              = data.azurerm_virtual_network.compute.name },
        { networkSubnetName        = data.azurerm_subnet.farm.name },
        { imageResourceGroupName   = local.imageResourceGroupName },
        { imageGalleryName         = local.imageGalleryName },
        { imageVersionIdDefault    = local.imageVersionIdDefault },
        { adminUsername            = data.azurerm_key_vault_secret.admin_username.value },
        { adminPassword            = data.azurerm_key_vault_secret.admin_password.value }
      ))
    )}"
  })
  depends_on = [
    azurerm_linux_virtual_machine.scheduler
  ]
}

resource "azurerm_virtual_machine_extension" "monitor_linux" {
  for_each = {
    for virtualMachine in var.virtualMachines : virtualMachine.name => virtualMachine if virtualMachine.name != "" && virtualMachine.monitorExtension.enable && virtualMachine.operatingSystem.type == "Linux"
  }
  name                       = "Monitor"
  type                       = "AzureMonitorLinuxAgent"
  publisher                  = "Microsoft.Azure.Monitor"
  type_handler_version       = "1.21"
  auto_upgrade_minor_version = true
  virtual_machine_id         = "${azurerm_resource_group.scheduler.id}/providers/Microsoft.Compute/virtualMachines/${each.value.name}"
  settings = jsonencode({
    "workspaceId": data.azurerm_log_analytics_workspace.monitor.workspace_id
  })
  protected_settings = jsonencode({
    "workspaceKey": data.azurerm_log_analytics_workspace.monitor.primary_shared_key
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
  source_image_id     = each.value.imageId
  size                = each.value.machineSize
  admin_username      = each.value.adminLogin.userName
  admin_password      = data.azurerm_key_vault_secret.admin_password.value
  custom_data = base64encode(
    templatefile(each.value.customExtension.parameters.autoScale.fileName, each.value.customExtension.parameters)
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
      data.azurerm_user_assigned_identity.render.id
    ]
  }
  boot_diagnostics {
    storage_account_uri = null
  }
  depends_on = [
    azurerm_network_interface.scheduler
  ]
}

resource "azurerm_virtual_machine_extension" "custom_windows" {
  for_each = {
    for virtualMachine in var.virtualMachines : virtualMachine.name => virtualMachine if virtualMachine.name != "" && virtualMachine.customExtension.enable && virtualMachine.operatingSystem.type == "Windows"
  }
  name                       = "Custom"
  type                       = "CustomScriptExtension"
  publisher                  = "Microsoft.Compute"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true
  virtual_machine_id         = "${azurerm_resource_group.scheduler.id}/providers/Microsoft.Compute/virtualMachines/${each.value.name}"
  settings = jsonencode({
    "commandToExecute": "PowerShell -ExecutionPolicy Unrestricted -EncodedCommand ${textencodebase64(
      templatefile(each.value.customExtension.fileName, merge(each.value.customExtension.parameters,
        { renderManager = module.global.renderManager }
      )), "UTF-16LE"
    )}"
  })
  depends_on = [
    azurerm_windows_virtual_machine.scheduler
  ]
}

resource "azurerm_virtual_machine_extension" "monitor_windows" {
  for_each = {
    for virtualMachine in var.virtualMachines : virtualMachine.name => virtualMachine if virtualMachine.name != "" && virtualMachine.monitorExtension.enable && virtualMachine.operatingSystem.type == "Windows"
  }
  name                       = "Monitor"
  type                       = "AzureMonitorWindowsAgent"
  publisher                  = "Microsoft.Azure.Monitor"
  type_handler_version       = "1.7"
  auto_upgrade_minor_version = true
  virtual_machine_id         = "${azurerm_resource_group.scheduler.id}/providers/Microsoft.Compute/virtualMachines/${each.value.name}"
  settings = jsonencode({
    "workspaceId": data.azurerm_log_analytics_workspace.monitor.workspace_id
  })
  protected_settings = jsonencode({
    "workspaceKey": data.azurerm_log_analytics_workspace.monitor.primary_shared_key
  })
  depends_on = [
    azurerm_windows_virtual_machine.scheduler
  ]
}

resource "azurerm_private_dns_a_record" "scheduler" {
  name                = "scheduler"
  resource_group_name = data.azurerm_private_dns_zone.network.resource_group_name
  zone_name           = data.azurerm_private_dns_zone.network.name
  ttl                 = 300
  records = [
    azurerm_network_interface.scheduler[local.schedulerMachineNames[0]].private_ip_address
  ]
}

######################################################################
# CycleCloud (https://learn.microsoft.com/azure/cyclecloud/overview) #
######################################################################

resource "azurerm_role_assignment" "cycle_cloud" {
  for_each = {
    for virtualMachine in var.virtualMachines : virtualMachine.name => virtualMachine if virtualMachine.customExtension.parameters.cycleCloud.enable
  }
  role_definition_name = "Contributor"
  principal_id         = data.azurerm_user_assigned_identity.render.principal_id
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
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
