terraform {
  required_version = ">= 1.2.8"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.21.1"
    }
  }
  backend "azurerm" {
    key = "2.network"
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

module "global" {
  source = "../0.global"
}

variable "resourceGroupName" {
  type = string
}

variable "computeNetwork" {
  type = object(
    {
      name               = string
      regionName         = string
      addressSpace       = list(string)
      dnsServerAddresses = list(string)
      subnets = list(object(
        {
          name              = string
          addressSpace      = list(string)
          serviceEndpoints  = list(string)
          serviceDelegation = string
        }
      ))
    }
  )
}

variable "computeNetworkSubnetIndex" {
  type = object(
    {
      farm        = number
      workstation = number
      cache       = number
    }
  )
}

variable "storageNetwork" {
  type = object(
    {
      name               = string
      regionName         = string
      addressSpace       = list(string)
      dnsServerAddresses = list(string)
      subnets = list(object(
        {
          name              = string
          addressSpace      = list(string)
          serviceEndpoints  = list(string)
          serviceDelegation = string
        }
      ))
    }
  )
}

variable "storageNetworkSubnetIndex" {
  type = object(
    {
      primary   = number
      secondary = number
      netApp    = number
    }
  )
}

variable "networkPeering" {
  type = object(
    {
      enabled                     = bool
      allowRemoteNetworkAccess    = bool
      allowRemoteForwardedTraffic = bool
      allowNetworkGatewayTransit  = bool
    }
  )
}

variable "privateDns" {
  type = object(
    {
      zoneName               = string
      enableAutoRegistration = bool
    }
  )
}

variable "networkGateway" {
  type = object(
    {
      type    = string
      address = object(
        {
          type             = string
          allocationMethod = string
        }
      )
    }
  )
}

variable "vpnGateway" {
  type = object(
    {
      sku                = string
      type               = string
      generation         = string
      enableBgp          = bool
      enableActiveActive = bool
      pointToSiteClient = object(
        {
          addressSpace    = list(string)
          certificateName = string
          certificateData = string
        }
      )
    }
  )
}

variable "vpnGatewayLocal" {
  type = object(
    {
      fqdn         = string
      address      = string
      addressSpace = list(string)
      bgp = object(
        {
          enabled        = bool
          asn            = number
          peerWeight     = number
          peeringAddress = string
        }
      )
    }
  )
}

variable "expressRouteGateway" {
  type = object(
    {
      sku = string
      connection = object(
        {
          circuitId        = string
          authorizationKey = string
          enableFastPath   = bool
        }
      )
    }
  )
}

data "azurerm_key_vault" "vault" {
  name                = module.global.keyVaultName
  resource_group_name = module.global.securityResourceGroupName
}

data "azurerm_key_vault_secret" "gateway_connection" {
  name         = module.global.keyVaultSecretNameGatewayConnection
  key_vault_id = data.azurerm_key_vault.vault.id
}

locals {
  virtualNetworks        = distinct(var.storageNetwork.name == "" ? [var.computeNetwork, var.computeNetwork] : [var.computeNetwork, var.storageNetwork])
  virtualNetworksSubnets = flatten([
    for virtualNetwork in local.virtualNetworks : [
      for virtualNetworkSubnet in virtualNetwork.subnets : merge(virtualNetworkSubnet,
        {regionName         = virtualNetwork.regionName},
        {virtualNetworkName = virtualNetwork.name}
      )
    ]
  ])
  virtualGatewayNetworks = flatten([
    for virtualNetwork in local.virtualNetworks : [
      for virtualNetworkSubnet in virtualNetwork.subnets : virtualNetwork if virtualNetworkSubnet.name == "GatewaySubnet"
    ]
  ])
  virtualGatewayNetworkNames = [for virtualGatewayNetwork in local.virtualGatewayNetworks : virtualGatewayNetwork.name]
  virtualGatewayActiveActive = var.networkGateway.type == "Vpn" && var.vpnGateway.enableActiveActive
}

resource "azurerm_resource_group" "network" {
  name     = var.resourceGroupName
  location = var.computeNetwork.regionName
}

################################################################################################
# Virtual Network (https://docs.microsoft.com/azure/virtual-network/virtual-networks-overview) #
################################################################################################

resource "azurerm_virtual_network" "network" {
  for_each = {
    for virtualNetwork in local.virtualNetworks : virtualNetwork.name => virtualNetwork
  }
  name                = each.value.name
  resource_group_name = azurerm_resource_group.network.name
  location            = each.value.regionName
  address_space       = each.value.addressSpace
  dns_servers         = each.value.dnsServerAddresses
}

resource "azurerm_subnet" "network" {
  for_each = {
    for virtualNetworksSubnet in local.virtualNetworksSubnets : "${virtualNetworksSubnet.virtualNetworkName}.${virtualNetworksSubnet.name}" => virtualNetworksSubnet
  }
  name                                          = each.value.name
  resource_group_name                           = azurerm_resource_group.network.name
  virtual_network_name                          = each.value.virtualNetworkName
  address_prefixes                              = each.value.addressSpace
  service_endpoints                             = each.value.serviceEndpoints
  private_endpoint_network_policies_enabled     = each.value.name == "GatewaySubnet"
  private_link_service_network_policies_enabled = each.value.name == "GatewaySubnet"
  dynamic "delegation" {
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
    for virtualNetworksSubnet in local.virtualNetworksSubnets : "${virtualNetworksSubnet.virtualNetworkName}.${virtualNetworksSubnet.name}" => virtualNetworksSubnet if virtualNetworksSubnet.name != "GatewaySubnet" && virtualNetworksSubnet.serviceDelegation == ""
  }
  name                = "${each.value.virtualNetworkName}.${each.value.name}"
  resource_group_name = azurerm_resource_group.network.name
  location            = each.value.regionName
  security_rule {
    name                       = "AllowSSH"
    priority                   = 2000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = "GatewayManager"
    source_port_range          = "*"
    destination_address_prefix = "*"
    destination_port_range     = "22"
  }
  security_rule {
    name                       = "AllowRDP"
    priority                   = 2001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = "GatewayManager"
    source_port_range          = "*"
    destination_address_prefix = "*"
    destination_port_range     = "3389"
  }
}

resource "azurerm_subnet_network_security_group_association" "network" {
  for_each = {
    for virtualNetworksSubnet in local.virtualNetworksSubnets : "${virtualNetworksSubnet.virtualNetworkName}.${virtualNetworksSubnet.name}" => virtualNetworksSubnet if virtualNetworksSubnet.name != "GatewaySubnet" && virtualNetworksSubnet.serviceDelegation == ""
  }
  subnet_id                 = "${azurerm_resource_group.network.id}/providers/Microsoft.Network/virtualNetworks/${each.value.virtualNetworkName}/subnets/${each.value.name}"
  network_security_group_id = "${azurerm_resource_group.network.id}/providers/Microsoft.Network/networkSecurityGroups/${each.value.virtualNetworkName}.${each.value.name}"
  depends_on = [
    azurerm_subnet.network,
    azurerm_network_security_group.network
  ]
}

###########################################################################
# Private DNS (https://docs.microsoft.com/azure/dns/private-dns-overview) #
###########################################################################

resource "azurerm_private_dns_zone" "network" {
  name                = var.privateDns.zoneName
  resource_group_name = azurerm_resource_group.network.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "network" {
  for_each = {
    for virtualNetwork in local.virtualNetworks : virtualNetwork.name => virtualNetwork
  }
  name                  = each.value.name
  resource_group_name   = azurerm_resource_group.network.name
  private_dns_zone_name = azurerm_private_dns_zone.network.name
  virtual_network_id    = "${azurerm_resource_group.network.id}/providers/Microsoft.Network/virtualNetworks/${each.value.name}"
  registration_enabled  = var.privateDns.enableAutoRegistration
  depends_on = [
    azurerm_virtual_network.network
  ]
}

###############################################################################################################
# Virtual Network Peering (https://docs.microsoft.com/azure/virtual-network/virtual-network-peering-overview) #
###############################################################################################################

resource "azurerm_virtual_network_peering" "network_peering_up" {
  count                        = var.networkPeering.enabled ? length(local.virtualNetworks) - 1 : 0
  name                         = "${local.virtualNetworks[count.index].name}.${local.virtualNetworks[count.index + 1].name}"
  resource_group_name          = azurerm_resource_group.network.name
  virtual_network_name         = local.virtualNetworks[count.index].name
  remote_virtual_network_id    = "${azurerm_resource_group.network.id}/providers/Microsoft.Network/virtualNetworks/${local.virtualNetworks[count.index + 1].name}"
  allow_virtual_network_access = var.networkPeering.allowRemoteNetworkAccess
  allow_forwarded_traffic      = var.networkPeering.allowRemoteForwardedTraffic
  allow_gateway_transit        = var.networkPeering.allowNetworkGatewayTransit && contains(local.virtualGatewayNetworkNames, local.virtualNetworks[count.index].name)
  depends_on = [
    azurerm_subnet_network_security_group_association.network
  ]
}

resource "azurerm_virtual_network_peering" "network_peering_down" {
  count                        = var.networkPeering.enabled ? length(local.virtualNetworks) - 1 : 0
  name                         = "${local.virtualNetworks[count.index + 1].name}.${local.virtualNetworks[count.index].name}"
  resource_group_name          = azurerm_resource_group.network.name
  virtual_network_name         = local.virtualNetworks[count.index + 1].name
  remote_virtual_network_id    = "${azurerm_resource_group.network.id}/providers/Microsoft.Network/virtualNetworks/${local.virtualNetworks[count.index].name}"
  allow_virtual_network_access = var.networkPeering.allowRemoteNetworkAccess
  allow_forwarded_traffic      = var.networkPeering.allowRemoteForwardedTraffic
  allow_gateway_transit        = var.networkPeering.allowNetworkGatewayTransit && contains(local.virtualGatewayNetworkNames, local.virtualNetworks[count.index + 1].name)
  depends_on = [
    azurerm_subnet_network_security_group_association.network
  ]
}

#######################################
# Virtual Network Gateway (Public IP) #
#######################################

resource "azurerm_public_ip" "address1" {
  for_each = {
    for virtualNetwork in local.virtualGatewayNetworks : virtualNetwork.name => virtualNetwork if var.networkGateway.type != ""
  }
  name                = local.virtualGatewayActiveActive ? "${each.value.name}1" : "${each.value.name}"
  resource_group_name = azurerm_resource_group.network.name
  location            = each.value.regionName
  sku                 = var.networkGateway.address.type
  allocation_method   = var.networkGateway.address.allocationMethod
}

resource "azurerm_public_ip" "address2" {
  for_each = {
    for virtualNetwork in local.virtualGatewayNetworks : virtualNetwork.name => virtualNetwork if local.virtualGatewayActiveActive
  }
  name                = "${each.value.name}2"
  resource_group_name = azurerm_resource_group.network.name
  location            = each.value.regionName
  sku                 = var.networkGateway.address.type
  allocation_method   = var.networkGateway.address.allocationMethod
}

resource "azurerm_public_ip" "address3" {
  for_each = {
    for virtualNetwork in local.virtualGatewayNetworks : virtualNetwork.name => virtualNetwork if local.virtualGatewayActiveActive && length(var.vpnGateway.pointToSiteClient.addressSpace) > 0
  }
  name                = "${each.value.name}3"
  resource_group_name = azurerm_resource_group.network.name
  location            = each.value.regionName
  sku                 = var.networkGateway.address.type
  allocation_method   = var.networkGateway.address.allocationMethod
}

#################################
# Virtual Network Gateway (VPN) #
#################################

resource "azurerm_virtual_network_gateway" "vpn" {
  for_each = {
    for virtualNetwork in local.virtualGatewayNetworks : virtualNetwork.name => virtualNetwork if var.networkGateway.type == "Vpn"
  }
  name                = each.value.name
  resource_group_name = azurerm_resource_group.network.name
  location            = each.value.regionName
  type                = var.networkGateway.type
  sku                 = var.vpnGateway.sku
  vpn_type            = var.vpnGateway.type
  generation          = var.vpnGateway.generation
  enable_bgp          = var.vpnGateway.enableBgp
  active_active       = local.virtualGatewayActiveActive
  ip_configuration {
    name                 = "ipConfig1"
    public_ip_address_id = "${azurerm_resource_group.network.id}/providers/Microsoft.Network/publicIPAddresses/${each.value.name}${local.virtualGatewayActiveActive ? "1" : ""}"
    subnet_id            = "${azurerm_resource_group.network.id}/providers/Microsoft.Network/virtualNetworks/${each.value.name}/subnets/GatewaySubnet"
  }
  dynamic "ip_configuration" {
    for_each = local.virtualGatewayActiveActive ? [1] : []
    content {
      name                 = "ipConfig2"
      public_ip_address_id = "${azurerm_resource_group.network.id}/providers/Microsoft.Network/publicIPAddresses/${each.value.name}2"
      subnet_id            = "${azurerm_resource_group.network.id}/providers/Microsoft.Network/virtualNetworks/${each.value.name}/subnets/GatewaySubnet"
    }
  }
  dynamic "ip_configuration" {
    for_each = local.virtualGatewayActiveActive && length(var.vpnGateway.pointToSiteClient.addressSpace) > 0 ? [1] : []
    content {
      name                 = "ipConfig3"
      public_ip_address_id = "${azurerm_resource_group.network.id}/providers/Microsoft.Network/publicIPAddresses/${each.value.name}3"
      subnet_id            = "${azurerm_resource_group.network.id}/providers/Microsoft.Network/virtualNetworks/${each.value.name}/subnets/GatewaySubnet"
    }
  }
  dynamic "vpn_client_configuration" {
    for_each = length(var.vpnGateway.pointToSiteClient.addressSpace) > 0 ? [1] : []
    content {
      address_space = var.vpnGateway.pointToSiteClient.addressSpace
      root_certificate {
        name             = var.vpnGateway.pointToSiteClient.certificateName
        public_cert_data = var.vpnGateway.pointToSiteClient.certificateData
      }
    }
  }
  depends_on = [
    azurerm_subnet_network_security_group_association.network,
    azurerm_public_ip.address1,
    azurerm_public_ip.address2,
    azurerm_public_ip.address3
  ]
}

resource "azurerm_virtual_network_gateway_connection" "vnet_to_vnet_up" {
  count                           = var.networkGateway.type == "Vpn" ? length(local.virtualGatewayNetworks) - 1 : 0
  name                            = "${local.virtualGatewayNetworks[count.index].name}.${local.virtualGatewayNetworks[count.index + 1].name}"
  resource_group_name             = azurerm_resource_group.network.name
  location                        = local.virtualGatewayNetworks[count.index].regionName
  type                            = "Vnet2Vnet"
  virtual_network_gateway_id      = "${azurerm_resource_group.network.id}/providers/Microsoft.Network/virtualNetworkGateways/${local.virtualGatewayNetworks[count.index].name}"
  peer_virtual_network_gateway_id = "${azurerm_resource_group.network.id}/providers/Microsoft.Network/virtualNetworkGateways/${local.virtualGatewayNetworks[count.index + 1].name}"
  shared_key                      = data.azurerm_key_vault_secret.gateway_connection.value
  depends_on = [
    azurerm_virtual_network_gateway.vpn
  ]
}

resource "azurerm_virtual_network_gateway_connection" "vnet_to_vnet_down" {
  count                           = var.networkGateway.type == "Vpn" ? length(local.virtualGatewayNetworks) - 1 : 0
  name                            = "${local.virtualGatewayNetworks[count.index + 1].name}.${local.virtualGatewayNetworks[count.index].name}"
  resource_group_name             = azurerm_resource_group.network.name
  location                        = local.virtualGatewayNetworks[count.index + 1].regionName
  type                            = "Vnet2Vnet"
  virtual_network_gateway_id      = "${azurerm_resource_group.network.id}/providers/Microsoft.Network/virtualNetworkGateways/${local.virtualGatewayNetworks[count.index + 1].name}"
  peer_virtual_network_gateway_id = "${azurerm_resource_group.network.id}/providers/Microsoft.Network/virtualNetworkGateways/${local.virtualGatewayNetworks[count.index].name}"
  shared_key                      = data.azurerm_key_vault_secret.gateway_connection.value
  depends_on = [
    azurerm_virtual_network_gateway.vpn
  ]
}

#########################################################################################################################
# Local Network Gateway (VPN) (https://docs.microsoft.com/azure/vpn-gateway/vpn-gateway-about-vpn-gateway-settings#lng) #
#########################################################################################################################

resource "azurerm_local_network_gateway" "vpn" {
  count               = var.networkGateway.type == "Vpn" && (var.vpnGatewayLocal.fqdn != "" || var.vpnGatewayLocal.address != "") ? 1 : 0
  name                = var.computeNetwork.name
  resource_group_name = azurerm_resource_group.network.name
  location            = var.computeNetwork.regionName
  gateway_fqdn        = var.vpnGatewayLocal.address == "" ? var.vpnGatewayLocal.fqdn : null
  gateway_address     = var.vpnGatewayLocal.fqdn == "" ? var.vpnGatewayLocal.address : null
  address_space       = var.vpnGatewayLocal.addressSpace
  dynamic "bgp_settings" {
    for_each = var.vpnGatewayLocal.bgp.enabled ? [1] : []
    content {
      asn                 = var.vpnGatewayLocal.bgp.asn
      peer_weight         = var.vpnGatewayLocal.bgp.peerWeight
      bgp_peering_address = var.vpnGatewayLocal.bgp.peeringAddress
    }
  }
}

resource "azurerm_virtual_network_gateway_connection" "site_to_site" {
  count                      = var.networkGateway.type == "Vpn" && (var.vpnGatewayLocal.fqdn != "" || var.vpnGatewayLocal.address != "") ? 1 : 0
  name                       = var.computeNetwork.name
  resource_group_name        = azurerm_resource_group.network.name
  location                   = var.computeNetwork.regionName
  type                       = "IPsec"
  virtual_network_gateway_id = azurerm_virtual_network_gateway.vpn[count.index].id
  local_network_gateway_id   = azurerm_local_network_gateway.vpn[count.index].id
  shared_key                 = data.azurerm_key_vault_secret.gateway_connection.value
  enable_bgp                 = var.vpnGatewayLocal.bgp.enabled
}

##########################################
# Virtual Network Gateway (ExpressRoute) #
##########################################

resource "azurerm_virtual_network_gateway" "express_route" {
  count               = var.networkGateway.type == "ExpressRoute" ? 1 : 0
  name                = var.computeNetwork.name
  resource_group_name = azurerm_resource_group.network.name
  location            = var.computeNetwork.regionName
  type                = var.networkGateway.type
  sku                 = var.expressRouteGateway.sku
  ip_configuration {
    name                 = "ipConfig"
    public_ip_address_id = "${azurerm_resource_group.network.id}/providers/Microsoft.Network/publicIPAddresses/${var.computeNetwork.name}"
    subnet_id            = "${azurerm_resource_group.network.id}/providers/Microsoft.Network/virtualNetworks/${var.computeNetwork.name}/subnets/GatewaySubnet"
  }
  depends_on = [
    azurerm_subnet_network_security_group_association.network,
    azurerm_public_ip.address1
  ]
}

resource "azurerm_virtual_network_gateway_connection" "express_route" {
  count                        = var.networkGateway.type == "ExpressRoute" && var.expressRouteGateway.connection.circuitId != "" ? 1 : 0
  name                         = var.computeNetwork.name
  resource_group_name          = azurerm_resource_group.network.name
  location                     = var.computeNetwork.regionName
  type                         = "ExpressRoute"
  virtual_network_gateway_id   = azurerm_virtual_network_gateway.express_route[count.index].id
  express_route_circuit_id     = var.expressRouteGateway.connection.circuitId
  express_route_gateway_bypass = var.expressRouteGateway.connection.enableFastPath
  authorization_key            = var.expressRouteGateway.connection.authorizationKey
}

output "resourceGroupName" {
  value = var.resourceGroupName
}

output "computeNetwork" {
  value = var.computeNetwork
}

output "computeNetworkSubnetIndex" {
  value = var.computeNetworkSubnetIndex
}

output "storageNetwork" {
  value = var.storageNetwork
}

output "storageNetworkSubnetIndex" {
  value = var.storageNetworkSubnetIndex
}

output "storageEndpointSubnets" {
  value = [
    for virtualNetworksSubnet in local.virtualNetworksSubnets : virtualNetworksSubnet if contains(virtualNetworksSubnet.serviceEndpoints, "Microsoft.Storage")
  ]
}

output "privateDns" {
  value = var.privateDns
}
