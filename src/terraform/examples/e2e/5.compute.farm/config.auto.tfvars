resourceGroupName = "AzureRender.Farm"

# Virtual Machine Scale Sets - https://docs.microsoft.com/en-us/azure/virtual-machine-scale-sets/overview
virtualMachineScaleSets = [
  {
    name        = ""
    imageId     = "/subscriptions/3d07cfbc-17aa-41b4-baa1-488fef85a1d3/resourceGroups/AzureRender.Image/providers/Microsoft.Compute/galleries/Gallery/images/LinuxFarm/versions/1.0.0"
    nodeSizeSku = "Standard_HB120rs_v2"
    nodeCount   = 10
    osType      = "Linux"
    osDisk = {
      storageType = "Standard_LRS"
      cachingType = "ReadOnly"
      ephemeralEnable = false // https://docs.microsoft.com/en-us/azure/virtual-machines/ephemeral-os-disks
    }
    adminLogin = {
      username     = "azureadmin"
      sshPublicKey = "" // "ssh-rsa ..."
      disablePasswordAuthentication = false
    }
    spot = {                    // https://docs.microsoft.com/en-us/azure/virtual-machine-scale-sets/use-spot
      evictionPolicy = "Delete" // https://docs.microsoft.com/en-us/azure/virtual-machine-scale-sets/use-spot#eviction-policy
      maxNodePrice   = -1       // https://docs.microsoft.com/en-us/azure/virtual-machine-scale-sets/use-spot#pricing
    }
    script = {
      file = "initialize.sh"
      parameters = {
        fileSystemMounts = [
          "cache.media.studio.:/mnt/farm /mnt/show/read nfs hard,proto=tcp,mountproto=tcp,retry=30 0 0",
          "azasset.blob.core.windows.net:/azasset/show /mnt/show/write nfs sec=sys,vers=3,proto=tcp,nolock 0 0"
        ]
      }
    }
  },
  {
    name        = ""
    imageId     = "/subscriptions/3d07cfbc-17aa-41b4-baa1-488fef85a1d3/resourceGroups/AzureRender.Image/providers/Microsoft.Compute/galleries/Gallery/images/WindowsFarm/versions/1.0.0"
    nodeSizeSku = "Standard_HB120rs_v2"
    nodeCount   = 10
    osType      = "Windows"
    osDisk = {
      storageType = "Standard_LRS"
      cachingType = "ReadOnly"
      ephemeralEnable = false // https://docs.microsoft.com/en-us/azure/virtual-machines/ephemeral-os-disks
    }
    adminLogin = {
      username     = "azureadmin"
      sshPublicKey = "" // "ssh-rsa ..."
      disablePasswordAuthentication = false
    }
    spot = {                    // https://docs.microsoft.com/en-us/azure/virtual-machine-scale-sets/use-spot
      evictionPolicy = "Delete" // https://docs.microsoft.com/en-us/azure/virtual-machine-scale-sets/use-spot#eviction-policy
      maxNodePrice   = -1       // https://docs.microsoft.com/en-us/azure/virtual-machine-scale-sets/use-spot#pricing
    }
    script = {
      file = "initialize.ps1"
      parameters = {
        fileSystemMounts = [         
        ]
      }
    }
  }
]

# Virtual Network - https://docs.microsoft.com/en-us/azure/virtual-network/virtual-networks-overview
virtualNetwork = {
  name              = ""
  subnetName        = ""
  resourceGroupName = ""
}
