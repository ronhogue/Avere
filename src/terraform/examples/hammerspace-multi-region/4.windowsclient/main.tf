// customize the simple VM by adjusting the following local variables
locals {
  resource_group_name = "houdini_vm_rg"
  unique_name         = "unique"
  // leave blank to not rename VM, otherwise it will be named "VMPREFIX-OCTET3-OCTET4" where the octets are from the IPv4 address of the machine
  vmPrefix = local.unique_name
  // paste in the id of the full custom image
  source_image_id = ""
  // can be any of the following None, Windows_Client and Windows_Server
  license_type      = "None"
  vm_size           = "Standard_D4s_v3"
  add_public_ip     = true
  vm_admin_username = "azureuser"
  // use either SSH Key data or admin password, if ssh_key_data is specified
  // then admin_password is ignored
  vm_admin_password = "ReplacePassword$"

  // replace below variables with the infrastructure variables from 0.network
  location                       = ""
  vnet_render_clients1_subnet_id = ""

  // update the below with information about the domain
  ad_domain = "" // example "rendering.com"
  // leave blank to add machine to default location
  ou_path     = ""
  ad_username = ""
  ad_password = ""

  // update if you need to change the RDP port
  rdp_port = 3389

  // the following are the arguments to be passed to the custom script
  windows_custom_script_arguments = "$arguments = ' -RenameVMPrefix ''${local.vmPrefix}'' -ADDomain ''${local.ad_domain}'' -OUPath ''${local.ou_path}'' ''${local.ad_username}'' -DomainPassword ''${local.ad_password}'' -RDPPort ${local.rdp_port} '  ; "

  // load the powershell file, you can substitute kv pairs as you need them, but 
  // use arguments where possible
  powershell_script = file("${path.module}/../../setupMachine.ps1")
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

resource "azurerm_resource_group" "win" {
  name     = local.resource_group_name
  location = local.location
}

resource "azurerm_public_ip" "vm" {
  name                = "${local.unique_name}-publicip"
  location            = local.location
  resource_group_name = azurerm_resource_group.win.name
  allocation_method   = "Static"

  count = local.add_public_ip ? 1 : 0
}

resource "azurerm_network_interface" "vm" {
  name                = "${local.unique_name}-nic"
  location            = azurerm_resource_group.win.location
  resource_group_name = azurerm_resource_group.win.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = local.vnet_render_clients1_subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = local.add_public_ip ? azurerm_public_ip.vm[0].id : ""
  }
}

resource "azurerm_windows_virtual_machine" "vm" {
  name                  = "${local.unique_name}-vm"
  location              = azurerm_resource_group.win.location
  resource_group_name   = azurerm_resource_group.win.name
  computer_name         = local.unique_name
  custom_data           = base64gzip(local.powershell_script)
  admin_username        = local.vm_admin_username
  admin_password        = local.vm_admin_password
  size                  = local.vm_size
  network_interface_ids = [azurerm_network_interface.vm.id]
  source_image_id       = local.source_image_id

  os_disk {
    name                 = "${local.unique_name}-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  license_type = local.license_type
}

locals {
  // the following powershell code will unzip and de-base64 the custom data payload enabling it
  // to be executed as a powershell script
  windows_custom_script_suffix = " $inputFile = '%SYSTEMDRIVE%\\\\AzureData\\\\CustomData.bin' ; $outputFile = '%SYSTEMDRIVE%\\\\AzureData\\\\CustomDataSetupScript.ps1' ; $inputStream = New-Object System.IO.FileStream $inputFile, ([IO.FileMode]::Open), ([IO.FileAccess]::Read), ([IO.FileShare]::Read) ; $sr = New-Object System.IO.StreamReader(New-Object System.IO.Compression.GZipStream($inputStream, [System.IO.Compression.CompressionMode]::Decompress)) ; $sr.ReadToEnd() | Out-File($outputFile) ; Invoke-Expression('{0} {1}' -f $outputFile, $arguments) ; "

  windows_custom_script = "powershell.exe -ExecutionPolicy Unrestricted -command \\\"${local.windows_custom_script_arguments} ${local.windows_custom_script_suffix}\\\""
}

resource "azurerm_virtual_machine_extension" "cse" {
  name                 = "${local.unique_name}-cse"
  virtual_machine_id   = azurerm_windows_virtual_machine.vm.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  // protected_settings necessary to pass secrets
  protected_settings = <<SETTINGS
    {
        "commandToExecute": "${local.windows_custom_script} > %SYSTEMDRIVE%\\AzureData\\CustomDataSetupScript.log 2>&1"
    }
SETTINGS
}

output "username" {
  value = local.vm_admin_username
}

output "vm_address" {
  value = local.add_public_ip ? azurerm_public_ip.vm[0].ip_address : azurerm_network_interface.vm.ip_configuration[0].private_ip_address
}
