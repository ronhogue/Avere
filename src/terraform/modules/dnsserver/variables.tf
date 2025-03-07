variable "resource_group_name" {
  description = "The existing resource group to contain the dnsserver."
}

variable "location" {
  description = "The Azure Region into which the dnsserver will be created."
}

variable "admin_username" {
  description = "Admin username on the dnsserver."
  default     = "azureuser"
}

variable "admin_password" {
  description = "(optional) The password used for access to the dnsserver.  If not specified, ssh_key_data needs to be set."
  default     = null
}

variable "ssh_key_data" {
  description = "(optional) The public SSH key used for access to the dnsserver.  If not specified, admin_password needs to be set.  The ssh_key_data takes precedence over the admin_password, and if set, the admin_password will be ignored."
}

variable "ssh_port" {
  description = "specifies the tcp port to use for ssh"
  default     = 22
}

variable "unique_name" {
  description = "The unique name used for the dnsserver and for resource names associated with the VM."
  default     = "dnsserver"
}

variable "vm_size" {
  description = "Size of the VM."
  default     = "Standard_D2s_v3"
}

variable "virtual_network_resource_group" {
  description = "The resource group name for the VNET."
}

variable "virtual_network_name" {
  description = "The unique name used for the virtual network."
}

variable "virtual_network_subnet_name" {
  description = "The unique name used for the virtual network subnet."
}

variable "private_ip_address" {
  description = "specifies a static private ip address to use"
  default     = null
}

variable "dns_server" {
  description = "A space separated list of dns servers to forward to.  At least one dns server must be specified"
}

variable "excluded_subnet_cidrs" {
  description = "the list of excluded subnets from spoofing.  The Cache should be in this subnet."
  default     = []
}

variable "avere_address_list" {
  description = "the list of addresses from the Avere vserver."
  default     = []
}

variable "avere_first_ip_addr" {
  description = "the first ip address of the Avere vserver."
  default     = ""
}

variable "avere_ip_addr_count" {
  description = "the count of ip addresses on the vserver."
  default     = 0
}

variable "avere_first_ip_addr2" {
  description = "the first ip address of the Avere vserver2."
  default     = ""
}

variable "avere_ip_addr_count2" {
  description = "the count of ip addresses on the vserver2."
  default     = 0
}

variable "avere_first_ip_addr3" {
  description = "the first ip address of the Avere vserver3."
  default     = ""
}

variable "avere_ip_addr_count3" {
  description = "the count of ip addresses on the vserver3."
  default     = 0
}

variable "avere_first_ip_addr4" {
  description = "the first ip address of the Avere vserver4."
  default     = ""
}

variable "avere_ip_addr_count4" {
  description = "the count of ip addresses on the vserver4."
  default     = 0
}

variable "avere_filer_fqdn" {
  description = "the fqdn of the avere."
}

variable "dns_max_ttl_seconds" {
  description = "The max ttl in seconds of the dns records, the default is 5 minutes.  This will cap larger TTLS, and TTLs set lower than this value will still be respected."
  default     = 300
}

variable "avere_filer_alternate_fqdn" {
  default     = []
  description = "alternate fqdn of the avere and is useful to point other names at Avere or can be used to emulate a domain search list."
}

variable "proxy" {
  description = "specify a proxy address if one exists in the format of http://PROXY_SERVER:PORT"
  default     = null
}
