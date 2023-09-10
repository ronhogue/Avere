###################################################################################
# Storage (https://learn.microsoft.com/azure/storage/common/storage-introduction) #
###################################################################################

variable "storageAccounts" {
  type = list(object(
    {
      name                 = string
      type                 = string
      tier                 = string
      redundancy           = string
      enableHttpsOnly      = bool
      enableBlobNfsV3      = bool
      enableLargeFileShare = bool
      privateEndpointTypes = list(string)
      blobContainers = list(object(
        {
          name           = string
          rootAcl        = string
          rootAclDefault = string
          enableDataLoad = bool

        }
      ))
      fileShares = list(object(
        {
          name           = string
          tier           = string
          sizeGiB        = number
          protocol       = string
          enableDataLoad = bool
        }
      ))
    }
  ))
}

locals {
  serviceEndpointSubnets = !local.stateExistsNetwork ? var.storageNetwork.serviceEndpointSubnets : data.terraform_remote_state.network.outputs.storageEndpointSubnets
  privateEndpoints = flatten([
    for storageAccount in var.storageAccounts : [
      for privateEndpointType in storageAccount.privateEndpointTypes : {
        storageAccountName = storageAccount.name
        storageAccountId   = "/subscriptions/${data.azurerm_client_config.studio.subscription_id}/resourceGroups/${azurerm_resource_group.storage.name}/providers/Microsoft.Storage/storageAccounts/${storageAccount.name}"
        type               = privateEndpointType
        dnsZoneId          = "/subscriptions/${data.azurerm_client_config.studio.subscription_id}/resourceGroups/${data.azurerm_resource_group.network.name}/providers/Microsoft.Network/privateDnsZones/privatelink.${privateEndpointType}.core.windows.net"
      }
    ]
  ])
  blobStorageAccounts = [
    for storageAccount in var.storageAccounts : storageAccount if storageAccount.type == "StorageV2" || storageAccount.type == "BlockBlobStorage"
  ]
  blobContainers = flatten([
    for storageAccount in var.storageAccounts : [
      for blobContainer in storageAccount.blobContainers : {
        name               = blobContainer.name
        rootAcl            = blobContainer.rootAcl
        rootAclDefault     = blobContainer.rootAclDefault
        storageAccountName = storageAccount.name
        enableDataLoad     = blobContainer.enableDataLoad
        enableFileSystem   = storageAccount.enableBlobNfsV3
      }
    ]
  ])
  fileShares = flatten([
    for storageAccount in var.storageAccounts : [
      for fileShare in storageAccount.fileShares : {
        name               = fileShare.name
        tier               = fileShare.tier
        size               = fileShare.sizeGiB
        accessProtocol     = fileShare.protocol
        storageAccountName = storageAccount.name
        enableDataLoad     = fileShare.enableDataLoad
      }
    ]
  ])
}

resource "azurerm_storage_account" "storage" {
  for_each = {
    for storageAccount in var.storageAccounts : storageAccount.name => storageAccount
  }
  name                            = each.value.name
  resource_group_name             = azurerm_resource_group.storage.name
  location                        = azurerm_resource_group.storage.location
  account_kind                    = each.value.type
  account_tier                    = each.value.tier
  account_replication_type        = each.value.redundancy
  enable_https_traffic_only       = each.value.enableHttpsOnly
  is_hns_enabled                  = each.value.enableBlobNfsV3
  nfsv3_enabled                   = each.value.enableBlobNfsV3
  large_file_share_enabled        = each.value.enableLargeFileShare ? true : null
  allow_nested_items_to_be_public = false
  network_rules {
    default_action = "Deny"
    virtual_network_subnet_ids = [
      for serviceEndpointSubnet in local.serviceEndpointSubnets :
        "${data.azurerm_resource_group.network.id}/providers/Microsoft.Network/virtualNetworks/${serviceEndpointSubnet.virtualNetworkName}/subnets/${serviceEndpointSubnet.name}"
    ]
    ip_rules = [
      jsondecode(data.http.client_address.response_body).ip
    ]
  }
}

resource "azurerm_private_endpoint" "storage" {
  for_each = {
    for privateEndpoint in local.privateEndpoints : "${privateEndpoint.storageAccountName}.${privateEndpoint.type}" => privateEndpoint
  }
  name                = each.value.storageAccountName
  resource_group_name = azurerm_resource_group.storage.name
  location            = azurerm_resource_group.storage.location
  subnet_id           = local.storageSubnet.id
  private_service_connection {
    name                           = each.value.storageAccountName
    private_connection_resource_id = each.value.storageAccountId
    is_manual_connection           = false
    subresource_names = [
      each.value.type
    ]
  }
  private_dns_zone_group {
    name = each.value.storageAccountName
    private_dns_zone_ids = [
      each.value.dnsZoneId
    ]
  }
  depends_on = [
    azurerm_storage_account.storage
  ]
}

resource "azurerm_storage_container" "core" {
  for_each = {
    for blobContainer in local.blobContainers : "${blobContainer.storageAccountName}.${blobContainer.name}" => blobContainer
  }
  name                 = each.value.name
  storage_account_name = each.value.storageAccountName
  depends_on = [
    azurerm_private_endpoint.storage
  ]
}

resource "azurerm_storage_share" "core" {
  for_each = {
    for fileShare in local.fileShares : "${fileShare.storageAccountName}.${fileShare.name}" => fileShare
  }
  name                 = each.value.name
  access_tier          = each.value.tier
  storage_account_name = each.value.storageAccountName
  enabled_protocol     = each.value.accessProtocol
  quota                = each.value.size
  depends_on = [
    azurerm_private_endpoint.storage
  ]
}

resource "terraform_data" "storage_container_permission" {
  for_each = {
    for blobContainer in local.blobContainers : "${blobContainer.storageAccountName}.${blobContainer.name}" => blobContainer if blobContainer.enableFileSystem
  }
  provisioner "local-exec" {
    command = "az storage fs access set --account-name ${each.value.storageAccountName} --file-system ${each.value.name} --path / --acl ${each.value.rootAcl}"
  }
  provisioner "local-exec" {
    command = "az storage fs access set --account-name ${each.value.storageAccountName} --file-system ${each.value.name} --path / --acl ${each.value.rootAclDefault}"
  }
  depends_on = [
    azurerm_storage_container.core
   ]
}

resource "terraform_data" "storage_container_data" {
  for_each = {
    for blobContainer in local.blobContainers : "${blobContainer.storageAccountName}.${blobContainer.name}" => blobContainer if blobContainer.name == "data" && var.dataLoadSource.accountName != "" && var.dataLoadSource.blobName == "" && blobContainer.enableDataLoad
  }
  provisioner "local-exec" {
    command = "az storage copy --source-account-name ${var.dataLoadSource.accountName} --source-account-key ${var.dataLoadSource.accountKey} --source-container ${var.dataLoadSource.containerName} --recursive --account-name ${each.value.storageAccountName} --destination-container ${each.value.name}"
  }
  depends_on = [
    azurerm_storage_container.core
   ]
}

resource "terraform_data" "storage_container_blob_data" {
  for_each = {
    for blobContainer in local.blobContainers : "${blobContainer.storageAccountName}.${blobContainer.name}" => blobContainer if blobContainer.name == "data" && var.dataLoadSource.accountName != "" && var.dataLoadSource.blobName != "" && blobContainer.enableDataLoad
  }
  provisioner "local-exec" {
    command = "az storage copy --source-account-name ${var.dataLoadSource.accountName} --source-account-key ${var.dataLoadSource.accountKey} --source-container ${var.dataLoadSource.containerName} --source-blob ${var.dataLoadSource.blobName} --recursive --account-name ${each.value.storageAccountName} --destination-container ${each.value.name} --destination-blob ${var.dataLoadSource.blobName}"
  }
  depends_on = [
    azurerm_storage_container.core
   ]
}

resource "terraform_data" "storage_share_data" {
  for_each = {
    for fileShare in local.fileShares : "${fileShare.storageAccountName}.${fileShare.name}" => fileShare if fileShare.name == "data" && var.dataLoadSource.accountName != "" && var.dataLoadSource.blobName == "" && fileShare.enableDataLoad
  }
  provisioner "local-exec" {
    command = "az storage copy --source-account-name ${var.dataLoadSource.accountName} --source-account-key ${var.dataLoadSource.accountKey} --source-container ${var.dataLoadSource.containerName} --recursive --account-name ${each.value.storageAccountName} --destination-share ${each.value.name}"
  }
  depends_on = [
    azurerm_storage_share.core
   ]
}

resource "terraform_data" "storage_share_file_data" {
  for_each = {
    for fileShare in local.fileShares : "${fileShare.storageAccountName}.${fileShare.name}" => fileShare if fileShare.name == "data" && var.dataLoadSource.accountName != "" && var.dataLoadSource.blobName != "" && fileShare.enableDataLoad
  }
  provisioner "local-exec" {
    command = "az storage copy --source-account-name ${var.dataLoadSource.accountName} --source-account-key ${var.dataLoadSource.accountKey} --source-container ${var.dataLoadSource.containerName} --source-blob ${var.dataLoadSource.blobName} --recursive --account-name ${each.value.storageAccountName} --destination-share ${each.value.name} --destination-file-path ${var.dataLoadSource.blobName}"
  }
  depends_on = [
    azurerm_storage_share.core
   ]
}

output "blobStorageAccounts" {
  value = local.blobStorageAccounts
}
