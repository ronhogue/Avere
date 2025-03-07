// customize the Secured VM by adjusting the following local variables
locals {
  // The secure channel consists of SSH from a single Source IP Address
  // If you do not have VPN or express route, get your external IP address 
  // from http://www.myipaddress.com/
  source_ssh_ip_address = "169.254.169.254"

  // the region of the deployment
  location          = "eastus"
  vm_admin_username = "azureuser"

  // per ISE, only SSH keys and not passwords may be used
  vm_ssh_key_data     = "ssh-rsa AAAAB3...."
  resource_group_name = "resource_group"
  vm_size             = "Standard_D2s_v3"
  // this value for OS Disk resize must be between 20GB and 1023GB,
  // after this you will need to repartition the disk
  os_disk_size_gb = 128

  // the below is the resource group and name of the previously created custom image
  image_resource_group = "image_resource_group"
  image_name           = "image_name"
}

terraform {
  required_version = ">= 0.14.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>2.66.0"
    }
  }
}

provider "azurerm" {
  features {}
}

data "azurerm_resource_group" "main" {
  name = local.resource_group_name
}

data "azurerm_image" "custom_image" {
  name                = local.image_name
  resource_group_name = local.image_resource_group
}

resource "azurerm_network_security_group" "ssh_nsg" {
  name                = "ssh_nsg"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name

  // the following security rule only allows incoming traffic from the source ip
  // address.
  // As machines are added to this VNET, a rule that allows VNET to VNET
  // could be added for VMs to communicate with each other.
  security_rule {
    name = "SSH"
    // priorities are between 100 and 4096 an may not overlap.
    // A priority of 100 ensures this rule is hit first.
    priority                   = 100 // priorities are between 100 and 4096
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "${local.source_ssh_ip_address}/32"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "noinbound"
    priority                   = 101 // priorities are between 100 and 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  // the following security rule deny's all outbound traffic from any IP
  // within the VNET.
  // As machines are added to this VNET, a rule that allows VNET to VNET
  // could be added for VMs to communicate with each other.
  security_rule {
    name = "notrafficout"
    // priorities are between 100 and 4096 an may not overlap.
    // A priority of 100 ensures this rule is hit first.
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_virtual_network" "main" {
  name = "virtualnetwork"
  // The /29 is the smallest possible VNET in Azure, 5 addresses are reserved for Azure
  // and 3 are available for use.
  address_space       = ["10.0.0.0/29"]
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name

  subnet {
    name           = "internal"
    address_prefix = "10.0.0.0/29"
    security_group = azurerm_network_security_group.ssh_nsg.id
  }
}

resource "azurerm_public_ip" "vm" {
  name                = "publicip"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  allocation_method   = "Static"
}

resource "azurerm_network_interface" "main" {
  name                = "nic"
  resource_group_name = data.azurerm_resource_group.main.name
  location            = data.azurerm_resource_group.main.location

  ip_configuration {
    name                          = "internal"
    subnet_id                     = tolist(azurerm_virtual_network.main.subnet)[0].id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm.id
  }
}

resource "azurerm_linux_virtual_machine" "main" {
  name                  = "vm"
  resource_group_name   = data.azurerm_resource_group.main.name
  location              = data.azurerm_resource_group.main.location
  network_interface_ids = [azurerm_network_interface.main.id]
  computer_name         = "vm"
  size                  = local.vm_size
  admin_username        = local.vm_admin_username
  source_image_id       = data.azurerm_image.custom_image.id

  // by default the OS has encryption at rest
  os_disk {
    name                 = "osdisk"
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
    disk_size_gb         = local.os_disk_size_gb
  }

  // per ISE, only SSH keys and not passwords may be used
  admin_ssh_key {
    username   = local.vm_admin_username
    public_key = local.vm_ssh_key_data
  }
}

output "username" {
  value = local.vm_admin_username
}

output "jumpbox_address" {
  value = azurerm_public_ip.vm.ip_address
}

output "ssh_command" {
  value = "ssh ${local.vm_admin_username}@${azurerm_public_ip.vm.ip_address}"
}
