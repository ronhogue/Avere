////////////////////////////////////////////////////////////////////////////////////////
// WARNING: if you get an error deploying, please review https://aka.ms/avere-tf-prereqs
////////////////////////////////////////////////////////////////////////////////////////
locals {
  // the region of the deployment
  location          = "eastus"
  vm_admin_username = "azureuser"
  // use either SSH Key data or admin password, if ssh_key_data is specified
  // then admin_password is ignored
  vm_admin_password = "ReplacePassword$"
  // if you use SSH key, ensure you have ~/.ssh/id_rsa with permission 600
  // populated where you are running terraform
  vm_ssh_key_data = null //"ssh-rsa AAAAB3...."
  ssh_port        = 22

  // network details
  virtual_network_resource_group = "network_rg"
  virtual_network_name           = "vnet"
  controller_network_subnet_name = "cache"
  vfxt_network_subnet_name       = "cache"

  // vfxt details
  vfxt_resource_group_name = "vfxt_rg"
  // the following allows scaling to 6 nodes
  vfxt_node_count = 3
  vfxt_first_ip   = "10.0.1.50"
  vfxt_ip_count   = 6
  // if you are running a locked down network, set controller_add_public_ip to false, but ensure
  // you have access to the subnet
  controller_add_public_ip     = true
  vfxt_cluster_name            = "vfxt"
  vfxt_cluster_password        = "VFXT_PASSWORD"
  support_uploads_company_name = "REPLACE_WITH_COMPANY_NAME"
  vfxt_ssh_key_data            = local.vm_ssh_key_data
  // vfxt cache polies
  //  "Clients Bypassing the Cluster"
  //  "Read Caching"
  //  "Read and Write Caching"
  //  "Full Caching"
  //  "Transitioning Clients Before or After a Migration"
  cache_policy = "Clients Bypassing the Cluster"

  // enables support according to document https://docs.microsoft.com/en-us/azure/avere-vfxt/avere-vfxt-enable-support
  // please review privacy policy before setting to true: https://privacy.microsoft.com/en-us/privacystatement
  enable_support_uploads = false

  // set to true, to use the DNS Server for spoofing: https://github.com/Azure/Avere/tree/main/src/terraform/examples/dnsserver
  enable_dns_server   = true
  dnsserver_static_ip = "10.0.1.250"
  onprem_dns_servers  = "168.63.129.16 169.254.169.254"
  onprem_filer_fqdn   = "filer.rendering.com"

  // advanced scenario: vfxt and controller image ids, leave this null, unless not using default marketplace
  controller_image_id = null
  vfxt_image_id       = null
  // advanced scenario: put the custom image resource group here
  alternative_resource_groups = []
}

terraform {
  required_version = ">= 0.14.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>2.66.0"
    }
    avere = {
      source  = "hashicorp/avere"
      version = ">=1.0.0"
    }
  }
}

provider "azurerm" {
  features {}
}

// the vfxt controller
module "vfxtcontroller" {
  source                      = "github.com/Azure/Avere/src/terraform/modules/controller3"
  create_resource_group       = false
  resource_group_name         = local.vfxt_resource_group_name
  location                    = local.location
  admin_username              = local.vm_admin_username
  admin_password              = local.vm_admin_password
  ssh_key_data                = local.vm_ssh_key_data
  add_public_ip               = local.controller_add_public_ip
  image_id                    = local.controller_image_id
  alternative_resource_groups = local.alternative_resource_groups

  // network details
  virtual_network_resource_group = local.virtual_network_resource_group
  virtual_network_name           = local.virtual_network_name
  virtual_network_subnet_name    = local.controller_network_subnet_name
}

resource "avere_vfxt" "vfxt" {
  controller_address        = module.vfxtcontroller.controller_address
  controller_admin_username = module.vfxtcontroller.controller_username
  // ssh key takes precedence over controller password
  controller_admin_password = local.vm_ssh_key_data != null && local.vm_ssh_key_data != "" ? "" : local.vm_admin_password

  proxy_uri         = local.proxy_uri
  cluster_proxy_uri = local.cluster_proxy_uri
  image_id          = local.vfxt_image_id

  location                     = local.location
  azure_resource_group         = local.vfxt_resource_group_name
  azure_network_resource_group = local.virtual_network_resource_group
  azure_network_name           = local.virtual_network_name
  azure_subnet_name            = local.vfxt_network_subnet_name
  vfxt_cluster_name            = local.vfxt_cluster_name
  vfxt_admin_password          = local.vfxt_cluster_password
  vfxt_ssh_key_data            = local.vfxt_ssh_key_data

  vfxt_node_count  = local.vfxt_node_count
  vserver_first_ip = local.vfxt_first_ip
  vserver_ip_count = local.vfxt_ip_count

  // uncomment following two lines to save money during testing
  // node_cache_size = 1024
  // node_size = "unsupported_test_SKU"

  // support
  enable_support_uploads          = local.enable_support_uploads
  support_uploads_company_name    = local.support_uploads_company_name
  enable_rolling_trace_data       = false
  active_support_upload           = true
  enable_secure_proactive_support = "Support"

  // terraform is not creating the implicit dependency on the controller module
  // otherwise during destroy, it tries to destroy the controller at the same time as vfxt cluster
  // to work around, add the explicit dependency
  depends_on = [
    module.vfxtcontroller,
  ]
}

module "dnsserver" {
  count = local.enable_dns_server ? 1 : 0

  source              = "github.com/Azure/Avere/src/terraform/modules/dnsserver"
  resource_group_name = local.vfxt_resource_group_name
  location            = local.location
  admin_username      = local.vm_admin_username
  admin_password      = local.vm_admin_password
  ssh_key_data        = local.vm_ssh_key_data
  ssh_port            = local.ssh_port

  // network details
  virtual_network_resource_group = local.virtual_network_resource_group
  virtual_network_name           = module.network.virtual_network_name
  virtual_network_subnet_name    = module.network.vfxt_network_subnet_name

  // this is the address of the unbound dns server
  private_ip_address = local.dnsserver_static_ip

  dns_server          = local.onprem_dns_servers
  avere_first_ip_addr = avere_vfxt.vfxt.vserver_first_ip
  avere_ip_addr_count = avere_vfxt.vfxt.vserver_ip_count
  avere_filer_fqdn    = local.onprem_filer_fqdn

  // set the TTL
  dns_max_ttl_seconds = 300

  depends_on = [
    avere_vfxt.vfxt,
  ]
}

output "controller_username" {
  value = module.vfxtcontroller.controller_username
}

output "controller_address" {
  value = module.vfxtcontroller.controller_address
}

output "ssh_command_with_avere_tunnel" {
  value = "ssh -p ${local.ssh_port} -L8443:${avere_vfxt.vfxt.vfxt_management_ip}:443 ${module.vfxtcontroller.controller_username}@${module.vfxtcontroller.controller_address}"
}

output "management_ip" {
  value = avere_vfxt.vfxt.vfxt_management_ip
}

output "mount_addresses" {
  value = tolist(avere_vfxt.vfxt.vserver_ip_addresses)
}

output "unbound_dns_server_username" {
  value = local.enable_dns_server ? local.vm_admin_username : null
}

output "unbound_dns_server_ip" {
  value = local.enable_dns_server ? module.dnsserver[0].dnsserver_address : null
}
