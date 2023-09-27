#################################################################################################
# Virtual Network (https://learn.microsoft.com/azure/virtual-network/virtual-networks-overview) #
#################################################################################################

variable "computeNetwork" {
  type = object(
    {
      name         = string
      addressSpace = list(string)
      dnsAddresses = list(string)
      subnets = list(object(
        {
          name                 = string
          addressSpace         = list(string)
          serviceEndpoints     = list(string)
          serviceDelegation    = string
          denyOutboundInternet = bool
        }
      ))
      subnetIndex = object(
        {
          farm        = number
          workstation = number
          storage     = number
          cache       = number
        }
      )
      enableNatGateway = bool
    }
  )
}

variable "storageNetwork" {
  type = object(
    {
      enable       = bool
      name         = string
      addressSpace = list(string)
      dnsAddresses = list(string)
      subnets = list(object(
        {
          name                 = string
          addressSpace         = list(string)
          serviceEndpoints     = list(string)
          serviceDelegation    = string
          denyOutboundInternet = bool
        }
      ))
      subnetIndex = object(
        {
          primary     = number
          secondary   = number
          netAppFiles = number
        }
      )
      enableNatGateway = bool
    }
  )
}

variable "virtualNetwork" {
  type = object(
    {
      enable            = bool
      name              = string
      regionName        = string
      resourceGroupName = string
    }
  )
}

locals {
  computeNetworks = [
    for regionName in module.global.regionNames : merge(var.computeNetwork, {
      key               = "${regionName}-${var.computeNetwork.name}"
      regionName        = regionName
      resourceGroupId   = "/subscriptions/${data.azurerm_client_config.studio.subscription_id}/resourceGroups/${length(module.global.regionNames) > 1 ? "${var.resourceGroupName}.${regionName}" : var.resourceGroupName}"
      resourceGroupName = length(module.global.regionNames) > 1 ? "${var.resourceGroupName}.${regionName}" : var.resourceGroupName
    })
  ]
  storageNetwork = merge(var.storageNetwork, {
    key               = "${module.global.regionNames[0]}-${var.storageNetwork.name}"
    regionName        = module.global.regionNames[0]
    resourceGroupId   = "/subscriptions/${data.azurerm_client_config.studio.subscription_id}/resourceGroups/${var.resourceGroupName}"
    resourceGroupName = var.resourceGroupName
  })
  computeNetworksSubnets = flatten([
    for computeNetwork in local.computeNetworks : [
      for subnet in computeNetwork.subnets : merge(subnet, {
        key                = "${computeNetwork.key}-${subnet.name}"
        regionName         = computeNetwork.regionName
        resourceGroupId    = computeNetwork.resourceGroupId
        resourceGroupName  = computeNetwork.resourceGroupName
        virtualNetworkName = computeNetwork.name
      }) if subnet.name != "GatewaySubnet"
    ]
  ])
  computeNetworkStorageSubnet = merge(local.computeNetworks[0].subnets[var.computeNetwork.subnetIndex.storage], {
    key = "${local.computeNetworks[0].key}-${local.computeNetworks[0].subnets[var.computeNetwork.subnetIndex.storage].name}"
    regionName         = local.computeNetworks[0].regionName
    resourceGroupId    = local.computeNetworks[0].resourceGroupId
    resourceGroupName  = local.computeNetworks[0].resourceGroupName
    virtualNetworkName = local.computeNetworks[0].name
  })
  storageNetworkSubnets = [
    for subnet in local.storageNetwork.subnets : merge(subnet, {
      key                = "${local.storageNetwork.key}-${subnet.name}"
      regionName         = local.storageNetwork.regionName
      resourceGroupId    = local.storageNetwork.resourceGroupId
      resourceGroupName  = local.storageNetwork.resourceGroupName
      virtualNetworkName = local.storageNetwork.name
    }) if subnet.name != "GatewaySubnet" && local.storageNetwork.enable
  ]
  storageSubnets  = setunion(local.storageNetworkSubnets, [local.computeNetworkStorageSubnet])
  virtualNetworks = local.storageNetwork.enable ? merge(local.storageNetwork, local.computeNetworks) : local.computeNetworks
  virtualNetworksSubnets = flatten([
    for virtualNetwork in local.virtualNetworks : [
      for subnet in virtualNetwork.subnets : merge(subnet, {
        key                = "${virtualNetwork.key}-${subnet.name}"
        regionName         = virtualNetwork.regionName
        resourceGroupId    = virtualNetwork.resourceGroupId
        resourceGroupName  = virtualNetwork.resourceGroupName
        virtualNetworkName = virtualNetwork.name
      })
    ]
  ])
  virtualNetworksSubnetsSecurity = [
    for subnet in local.virtualNetworksSubnets : subnet if subnet.name != "GatewaySubnet" && subnet.name != "AzureBastionSubnet" && subnet.serviceDelegation == ""
  ]
}

resource "azurerm_virtual_network" "network" {
  for_each = {
    for virtualNetwork in local.virtualNetworks : virtualNetwork.key => virtualNetwork if var.virtualNetwork.name == ""
  }
  name                = each.value.name
  resource_group_name = each.value.resourceGroupName
  location            = each.value.regionName
  address_space       = each.value.addressSpace
  dns_servers         = each.value.dnsAddresses
  depends_on = [
    azurerm_resource_group.network
  ]
}

resource "azurerm_subnet" "network" {
  for_each = {
    for subnet in local.virtualNetworksSubnets : subnet.key => subnet if var.virtualNetwork.name == ""
  }
  name                                          = each.value.name
  resource_group_name                           = each.value.resourceGroupName
  virtual_network_name                          = each.value.virtualNetworkName
  address_prefixes                              = each.value.addressSpace
  service_endpoints                             = each.value.serviceEndpoints
  private_endpoint_network_policies_enabled     = each.value.name == "GatewaySubnet"
  private_link_service_network_policies_enabled = each.value.name == "GatewaySubnet"
  dynamic delegation {
    for_each = each.value.serviceDelegation != "" ? [1] : []
    content {
      name = "delegation"
      service_delegation {
        name = each.value.serviceDelegation
      }
    }
  }
  depends_on = [
    azurerm_virtual_network.network
  ]
}

resource "azurerm_network_security_group" "network" {
  for_each = {
    for subnet in local.virtualNetworksSubnetsSecurity : subnet.key => subnet if var.virtualNetwork.name == ""
  }
  name                = "${each.value.virtualNetworkName}-${each.value.name}"
  resource_group_name = each.value.resourceGroupName
  location            = each.value.regionName
  security_rule {
    name                       = "AllowOutARM"
    priority                   = 3200
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = "*"
    source_port_range          = "*"
    destination_address_prefix = "AzureResourceManager"
    destination_port_range     = "*"
  }
  security_rule {
    name                       = "AllowOutStorage"
    priority                   = 3100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = "*"
    source_port_range          = "*"
    destination_address_prefix = "Storage"
    destination_port_range     = "*"
  }
  dynamic security_rule {
    for_each = each.value.denyOutboundInternet ? [1] : []
    content {
      name                       = "DenyOutInternet"
      priority                   = 3000
      direction                  = "Outbound"
      access                     = "Deny"
      protocol                   = "*"
      source_address_prefix      = "*"
      source_port_range          = "*"
      destination_address_prefix = "Internet"
      destination_port_range     = "*"
    }
  }
  dynamic security_rule {
    for_each = each.value.name == "Workstation" ? [1] : []
    content {
      name                       = "AllowInPCoIP.TCP"
      priority                   = 2000
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_address_prefix      = "Internet"
      source_port_range          = "*"
      destination_address_prefix = "*"
      destination_port_ranges = [
        "443",
        "4172",
        "60433"
      ]
    }
  }
  dynamic security_rule {
    for_each = each.value.name == "Workstation" ? [1] : []
    content {
      name                       = "AllowInPCoIP.UDP"
      priority                   = 2100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Udp"
      source_address_prefix      = "Internet"
      source_port_range          = "*"
      destination_address_prefix = "*"
      destination_port_range     = "4172"
    }
  }
  dynamic security_rule {
    for_each = each.value.denyOutboundInternet && each.value.name == "Workstation" ? [1] : []
    content {
      name                       = "AllowOutHTTP"
      priority                   = 2000
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_address_prefix      = "*"
      source_port_range          = "*"
      destination_address_prefix = "Internet"
      destination_port_range     = "80"
    }
  }
  dynamic security_rule {
    for_each = each.value.denyOutboundInternet && each.value.name == "Workstation" ? [1] : []
    content {
      name                       = "AllowOutPCoIP.TCP"
      priority                   = 2100
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_address_prefix      = "*"
      source_port_range          = "*"
      destination_address_prefix = "Internet"
      destination_port_range     = "443"
    }
  }
  dynamic security_rule {
    for_each = each.value.denyOutboundInternet && each.value.name == "Workstation" ? [1] : []
    content {
      name                       = "AllowOutPCoIP.UDP"
      priority                   = 2200
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "Udp"
      source_address_prefix      = "*"
      source_port_range          = "*"
      destination_address_prefix = "Internet"
      destination_port_range     = "4172"
    }
  }
  depends_on = [
    azurerm_virtual_network.network
  ]
}

resource "azurerm_subnet_network_security_group_association" "network" {
  for_each = {
    for subnet in local.virtualNetworksSubnetsSecurity : subnet.key => subnet if var.virtualNetwork.name == ""
  }
  subnet_id                 = "${each.value.resourceGroupId}/providers/Microsoft.Network/virtualNetworks/${each.value.virtualNetworkName}/subnets/${each.value.name}"
  network_security_group_id = "${each.value.resourceGroupId}/providers/Microsoft.Network/networkSecurityGroups/${each.value.virtualNetworkName}-${each.value.name}"
  depends_on = [
    azurerm_subnet.network,
    azurerm_network_security_group.network
  ]
}

output "computeNetwork" {
  value = var.virtualNetwork.enable ? null : local.computeNetworks[0]
}

output "storageNetwork" {
  value = var.virtualNetwork.enable ? null : local.storageNetwork
}

output "storageEndpointSubnets" {
  value = [
    for subnet in local.virtualNetworksSubnets : subnet if contains(subnet.serviceEndpoints, "Microsoft.Storage") && var.virtualNetwork.name == ""
  ]
}
