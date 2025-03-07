// customize the simple VM by editing the following local variables
locals {
  vm_name = var.unique_name

  # deliver the install script via cloud-init
  script_file_b64 = base64gzip(replace(file("${path.module}/install.sh"), "\r", ""))
  init_file       = templatefile("${path.module}/cloud-init.tpl", { installcmd = local.script_file_b64 })
}

data "azurerm_subnet" "vnet" {
  name                 = var.virtual_network_subnet_name
  virtual_network_name = var.virtual_network_name
  resource_group_name  = var.virtual_network_resource_group
}

resource "azurerm_resource_group" "vmss" {
  name     = var.resource_group_name
  location = var.location
}

locals {
  mount_all_env_var = var.mount_all ? " MOUNT_ALL=true " : ""
  env_vars          = " ${local.mount_all_env_var} LINUX_USER=${var.admin_username} NODE_PREFIX=${local.vm_name} NODE_COUNT=${var.vm_count} BASE_DIR=${var.mount_target} BOOTSTRAP_SCRIPT_PATH=${var.bootstrap_script_path} NFS_IP_CSV='${join(",", var.nfs_export_addresses)}' NFS_PATH=${var.nfs_export_path} ${var.additional_env_vars}"

  bootstrap_path = "/b"

  vmss_priority = "Standard"
}

resource "azurerm_virtual_machine_scale_set" "vmss" {
  name                = local.vm_name
  resource_group_name = azurerm_resource_group.vmss.name
  location            = azurerm_resource_group.vmss.location
  upgrade_policy_mode = "Manual"
  priority            = var.vmss_priority
  eviction_policy     = var.vmss_priority == "Spot" ? "Delete" : null
  overprovision       = var.overprovision

  dynamic "os_profile" {
    for_each = (var.ssh_key_data == null || var.ssh_key_data == "") && var.admin_password != null && var.admin_password != "" ? [var.admin_password] : [null]
    content {
      computer_name_prefix = var.unique_name
      admin_username       = var.admin_username
      admin_password       = var.admin_password
      custom_data          = base64encode(local.init_file)
    }
  }

  // dynamic block when password is specified
  dynamic "os_profile_linux_config" {
    for_each = (var.ssh_key_data == null || var.ssh_key_data == "") && var.admin_password != null && var.admin_password != "" ? [var.admin_password] : []
    content {
      disable_password_authentication = false
    }
  }

  // dynamic block when SSH key is specified
  dynamic "os_profile_linux_config" {
    for_each = var.ssh_key_data == null || var.ssh_key_data == "" ? [] : [var.ssh_key_data]
    content {
      disable_password_authentication = true
      ssh_keys {
        path     = "/home/${var.admin_username}/.ssh/authorized_keys"
        key_data = var.ssh_key_data
      }
    }
  }

  sku {
    name     = var.vm_size
    tier     = local.vmss_priority
    capacity = var.vm_count
  }

  storage_profile_image_reference {
    publisher = var.image_reference_publisher
    offer     = var.image_reference_offer
    sku       = var.image_reference_sku
    version   = var.image_reference_version
  }

  storage_profile_os_disk {
    caching           = "ReadWrite"
    managed_disk_type = "Standard_LRS"
    create_option     = "FromImage"
  }

  network_profile {
    name    = "vminic-${var.unique_name}"
    primary = true

    ip_configuration {
      name      = "internal"
      primary   = true
      subnet_id = data.azurerm_subnet.vnet.id
    }
  }

  // per the following article, wait for the bootstrap file to appear: https://github.com/hashicorp/terraform/issues/18303.
  // the solution is to either put a while loop in the below, or alternatively wait for https://www.terraform.io/docs/providers/external/data_source.html 
  extension {
    name                 = "${var.unique_name}-cse"
    publisher            = "Microsoft.Azure.Extensions"
    type                 = "CustomScript"
    type_handler_version = "2.0"
    # steps of the installer
    # 1. install nfs-common (retry 3 times for both update and install)
    # 2. create the bootstrap directory and mount the nfs server
    # 3. run the bootstrap script
    # 4. unmount the nfs server the bootstrap directory 
    settings = <<SETTINGS
    {
        "commandToExecute": "set -x && while [ ! -f /opt/install.completed ]; do sleep 2; done && mkdir -p ${local.bootstrap_path} && r=5 && for i in $(seq 1 $r); do mount -o 'hard,nointr,proto=tcp,mountproto=tcp,retry=30' ${var.nfs_export_addresses[0]}:${var.nfs_export_path} ${local.bootstrap_path} && break || [ $i == $r ] && break 0 || sleep 1; done && while [ ! -f ${local.bootstrap_path}${var.bootstrap_script_path} ]; do sleep 10; done && ${local.env_vars} /bin/bash ${local.bootstrap_path}${var.bootstrap_script_path} 2>&1 | tee -a /var/log/bootstrap.log && umount ${local.bootstrap_path} && rmdir ${local.bootstrap_path}"
    }
SETTINGS
  }
}

/*
Commenting out for now as this needs discussion with Terraform team.  By decoupling the extension with the VMSS,
it is mandatory to set the VMSS to auto-upgrade.

This is covered by the following two bugs: https://github.com/terraform-providers/terraform-provider-azurerm/issues/5976
and https://github.com/terraform-providers/terraform-provider-azurerm/issues/5860.

resource "azurerm_linux_virtual_machine_scale_set" "vmss" {
  name                = local.vm_name
  resource_group_name = azurerm_resource_group.vmss.name
  location            = azurerm_resource_group.vmss.location
  sku                 = var.vm_size
  instances           = var.vm_count
  admin_username      = var.admin_username
  upgrade_mode        = "Automatic" // automatic is necesary to run the custom script extension
  health_probe_id     = ""
  priority            = var.vmss_priority
  eviction_policy     = var.vmss_priority == "Spot" ? "Delete" : null

  automatic_os_upgrade_policy {
    disable_automatic_rollback = true
    enable_automatic_os_upgrade = false
  }

  dynamic "admin_ssh_key" {
      for_each = var.ssh_key_data == null || var.ssh_key_data == "" ? [] : [var.ssh_key_data]
      content {
          username   = var.admin_username
          public_key = var.ssh_key_data
      }
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"

    dynamic "diff_disk_settings" {
      for_each = var.use_ephemeral_os_disk == true ? [var.use_ephemeral_os_disk] : []
      content {
          option = "Local"
      }
    }
  }

  network_interface {
    name    = "vminic-${var.unique_name}"
    primary = true

    ip_configuration {
      name      = "internal"
      primary   = true
      subnet_id = data.azurerm_subnet.vnet.id
    }
  }
}

locals {
    env_vars = " LINUX_USER=${var.admin_username} NODE_PREFIX=${local.vm_name} NODE_COUNT=${var.vm_count} BASE_DIR=${var.mount_target} BOOTSTRAP_SCRIPT_PATH=${var.bootstrap_script_path} NFS_IP_CSV='${join(",",var.nfs_export_addresses)}' NFS_PATH=${var.nfs_export_path}"

    bootstrap_path = "/b"
}*/

/*
resource "azurerm_virtual_machine_scale_set_extension" "vmss" {
  name                         = "${var.unique_name}-cse"
  virtual_machine_scale_set_id = azurerm_linux_virtual_machine_scale_set.vmss.id
  publisher                    = "Microsoft.Azure.Extensions"
  type                         = "CustomScript"
  type_handler_version         = "2.0"
  # steps of the installer
  # 1. install nfs-common
  # 2. create the bootstrap directory and mount the nfs server
  # 3. run the bootstrap script
  # 4. unmount the nfs server the bootstrap directory 
  settings = <<SETTINGS
    {
        "commandToExecute": "(apt-get update || (sleep 10 && apt-get update) || (sleep 10 && apt-get update)) && (apt-get install -y nfs-common || (sleep 10 && apt-get install -y nfs-common) || (sleep 10 && apt-get install -y nfs-common))  && mkdir -p ${local.bootstrap_path} && r=5 && for i in $(seq 1 $r); do mount -o 'hard,nointr,proto=tcp,mountproto=tcp,retry=30' ${var.nfs_export_addresses[0]}:${var.nfs_export_path} ${local.bootstrap_path} && break || [ $i == $r ] && break 0 || sleep 1; done && ${local.env_vars} /bin/bash ${local.bootstrap_path}${var.bootstrap_script_path} 2>&1 | tee -a /var/log/bootstrap.log && umount ${local.bootstrap_path} && rmdir ${local.bootstrap_path}"
    }
SETTINGS
}*/


