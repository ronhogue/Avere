resourceGroupName = "ArtistAnywhere.Farm" # Alphanumeric, underscores, hyphens, periods and parenthesis are allowed

######################################################################################################
# Virtual Machine Scale Sets (https://learn.microsoft.com/azure/virtual-machine-scale-sets/overview) #
######################################################################################################

virtualMachineScaleSets = [
  {
    enable = false
    name   = "LnxFarmC"
    machine = {
      size  = "Standard_HB120rs_v3"
      count = 2
      image = {
        id = "/subscriptions/5cc0d8f1-3643-410c-8646-1a2961134bd3/resourceGroups/ArtistAnywhere.Image/providers/Microsoft.Compute/galleries/azstudio/images/Linux/versions/2.0.0"
        plan = {
          enable    = false
          publisher = ""
          product   = ""
          name      = ""
        }
      }
    }
    spot = {
      enable         = true     # https://learn.microsoft.com/azure/virtual-machine-scale-sets/use-spot
      evictionPolicy = "Delete" # https://learn.microsoft.com/azure/virtual-machine-scale-sets/use-spot#eviction-policy
    }
    network = {
      enableAcceleration = true
    }
    operatingSystem = {
      type = "Linux"
      disk = {
        storageType = "Standard_LRS"
        cachingType = "ReadOnly"
        sizeGB      = 0
        ephemeral = { # https://learn.microsoft.com/azure/virtual-machines/ephemeral-os-disks
          enable    = true
          placement = "ResourceDisk"
        }
      }
    }
    adminLogin = {
      userName     = ""
      userPassword = ""
      sshPublicKey = "" # "ssh-rsa ..."
      passwordAuth = {
        disable = false
      }
    }
    activeDirectory = {
      enable           = false
      domainName       = ""
      domainServerName = ""
      orgUnitPath      = ""
      adminUsername    = ""
      adminPassword    = ""
    }
    extension = {
      initialize = {
        enable   = true
        fileName = "initialize.sh"
        parameters = {
          fileSystemMounts = [
            {
              enable = false # File Storage Read
              mount  = "azstudio1.file.core.windows.net/azstudio1/content /mnt/content nfs sec=sys,vers=4,minorversion=1 0 0"
            },
            {
              enable = false # File Cache Read
              mount  = "cache.artist.studio/mnt/content /mnt/content/read nfs hard,proto=tcp,mountproto=tcp,retry=30,nolock 0 0"
            },
            {
              enable = false # File Storage Write
              mount  = "azstudio1.file.core.windows.net/azstudio1/content /mnt/content nfs sec=sys,vers=4,minorversion=1 0 0"
            },
            {
              enable = false # File Cache Write
              mount  = "cache.artist.studio/mnt/content /mnt/content/write nfs hard,proto=tcp,mountproto=tcp,retry=30,nolock 0 0"
            },
            {
              enable = true # Job Scheduler
              mount  = "scheduler.artist.studio/Deadline /DeadlineServer nfs defaults 0 0"
            }
          ]
          terminateNotification = { # https://learn.microsoft.com/azure/virtual-machine-scale-sets/virtual-machine-scale-sets-terminate-notification
            enable       = true
            delayTimeout = "PT5M"
          }
        }
      }
      health = {
        enable      = true
        protocol    = "tcp"
        port        = 111
        requestPath = ""
      }
      monitor = {
        enable = false
      }
    }
  },
  {
    enable = false
    name   = "LnxFarmG"
    machine = {
      size  = "Standard_NV36ads_A10_v5"
      count = 2
      image = {
        id = "/subscriptions/5cc0d8f1-3643-410c-8646-1a2961134bd3/resourceGroups/ArtistAnywhere.Image/providers/Microsoft.Compute/galleries/azstudio/images/Linux/versions/2.1.0"
        plan = {
          enable    = false
          publisher = ""
          product   = ""
          name      = ""
        }
      }
    }
    spot = {
      enable         = true     # https://learn.microsoft.com/azure/virtual-machine-scale-sets/use-spot
      evictionPolicy = "Delete" # https://learn.microsoft.com/azure/virtual-machine-scale-sets/use-spot#eviction-policy
    }
    network = {
      enableAcceleration = true
    }
    operatingSystem = {
      type = "Linux"
      disk = {
        storageType = "Standard_LRS"
        cachingType = "ReadOnly"
        sizeGB      = 0
        ephemeral = { # https://learn.microsoft.com/azure/virtual-machines/ephemeral-os-disks
          enable    = true
          placement = "ResourceDisk"
        }
      }
    }
    adminLogin = {
      userName     = ""
      userPassword = ""
      sshPublicKey = "" # "ssh-rsa ..."
      passwordAuth = {
        disable = false
      }
    }
    activeDirectory = {
      enable           = false
      domainName       = ""
      domainServerName = ""
      orgUnitPath      = ""
      adminUsername    = ""
      adminPassword    = ""
    }
    extension = {
      initialize = {
        enable   = true
        fileName = "initialize.sh"
        parameters = {
          fileSystemMounts = [
            {
              enable = false # File Storage Read
              mount  = "azstudio1.blob.core.windows.net/azstudio1/content /mnt/content nfs sec=sys,vers=4,minorversion=1 0 0"
            },
            {
              enable = false # File Cache Read
              mount  = "cache.artist.studio/mnt/content /mnt/content/read nfs hard,proto=tcp,mountproto=tcp,retry=30,nolock 0 0"
            },
            {
              enable = false # File Storage Write
              mount  = "azstudio1.blob.core.windows.net/azstudio1/content /mnt/content nfs sec=sys,vers=4,minorversion=1 0 0"
            },
            {
              enable = false # File Cache Write
              mount  = "cache.artist.studio/mnt/content /mnt/content/write nfs hard,proto=tcp,mountproto=tcp,retry=30,nolock 0 0"
            },
            {
              enable = true # Job Scheduler
              mount  = "scheduler.artist.studio/Deadline /DeadlineServer nfs defaults 0 0"
            }
          ]
          terminateNotification = { # https://learn.microsoft.com/azure/virtual-machine-scale-sets/virtual-machine-scale-sets-terminate-notification
            enable       = true
            delayTimeout = "PT5M"
          }
        }
      }
      health = {
        enable      = true
        protocol    = "tcp"
        port        = 111
        requestPath = ""
      }
      monitor = {
        enable = false
      }
    }
  },
  {
    enable = false
    name   = "WinFarmC"
    machine = {
      size  = "Standard_HB120rs_v3"
      count = 2
      image = {
        id = "/subscriptions/5cc0d8f1-3643-410c-8646-1a2961134bd3/resourceGroups/ArtistAnywhere.Image/providers/Microsoft.Compute/galleries/azstudio/images/WinFarm/versions/2.0.0"
        plan = {
          enable    = false
          publisher = ""
          product   = ""
          name      = ""
        }
      }
    }
    spot = {
      enable         = true     # https://learn.microsoft.com/azure/virtual-machine-scale-sets/use-spot
      evictionPolicy = "Delete" # https://learn.microsoft.com/azure/virtual-machine-scale-sets/use-spot#eviction-policy
    }
    network = {
      enableAcceleration = true
    }
    operatingSystem = {
      type = "Windows"
      disk = {
        storageType = "Standard_LRS"
        cachingType = "ReadOnly"
        sizeGB      = 0
        ephemeral = { # https://learn.microsoft.com/azure/virtual-machines/ephemeral-os-disks
          enable    = true
          placement = "ResourceDisk"
        }
      }
    }
    adminLogin = {
      userName     = ""
      userPassword = ""
      sshPublicKey = "" # "ssh-rsa ..."
      passwordAuth = {
        disable = false
      }
    }
    activeDirectory = {
      enable           = true
      domainName       = "artist.studio"
      domainServerName = "WinScheduler"
      orgUnitPath      = ""
      adminUsername    = ""
      adminPassword    = ""
    }
    extension = {
      initialize = {
        enable   = true
        fileName = "initialize.ps1"
        parameters = {
          fileSystemMounts = [
            {
              enable = false # File Storage Read
              mount  = "mount -o anon nolock \\\\azstudio1.blob.core.windows.net\\azstudio1\\content R:"
            },
            {
              enable = false # File Cache Read
              mount  = "mount -o anon nolock \\\\cache.artist.studio\\mnt\\content R:"
            },
            {
              enable = false # File Storage Write
              mount  = "mount -o anon nolock \\\\azstudio1.blob.core.windows.net\\azstudio1\\content W:"
            },
            {
              enable = false # File Cache Write
              mount  = "mount -o anon nolock \\\\cache.artist.studio\\mnt\\content W:"
            },
            {
              enable = true # Job Scheduler
              mount  = "mount -o anon \\\\scheduler.artist.studio\\Deadline S:"
            }
          ]
          terminateNotification = { # https://learn.microsoft.com/azure/virtual-machine-scale-sets/virtual-machine-scale-sets-terminate-notification
            enable       = true
            delayTimeout = "PT5M"
          }
        }
      }
      health = {
        enable      = true
        protocol    = "tcp"
        port        = 445
        requestPath = ""
      }
      monitor = {
        enable = false
      }
    }
  },
  {
    enable = false
    name   = "WinFarmG"
    machine = {
      size  = "Standard_NV36ads_A10_v5"
      count = 2
      image = {
        id = "/subscriptions/5cc0d8f1-3643-410c-8646-1a2961134bd3/resourceGroups/ArtistAnywhere.Image/providers/Microsoft.Compute/galleries/azstudio/images/WinFarm/versions/2.1.0"
        plan = {
          enable    = false
          publisher = ""
          product   = ""
          name      = ""
        }
      }
    }
    spot = {
      enable         = true     # https://learn.microsoft.com/azure/virtual-machine-scale-sets/use-spot
      evictionPolicy = "Delete" # https://learn.microsoft.com/azure/virtual-machine-scale-sets/use-spot#eviction-policy
    }
    network = {
      enableAcceleration = true
    }
    operatingSystem = {
      type = "Windows"
      disk = {
        storageType = "Standard_LRS"
        cachingType = "ReadOnly"
        sizeGB      = 0
        ephemeral = { # https://learn.microsoft.com/azure/virtual-machines/ephemeral-os-disks
          enable    = true
          placement = "ResourceDisk"
        }
      }
    }
    adminLogin = {
      userName     = ""
      userPassword = ""
      sshPublicKey = "" # "ssh-rsa ..."
      passwordAuth = {
        disable = false
      }
    }
    activeDirectory = {
      enable           = true
      domainName       = "artist.studio"
      domainServerName = "WinScheduler"
      orgUnitPath      = ""
      adminUsername    = ""
      adminPassword    = ""
    }
    extension = {
      initialize = {
        enable   = true
        fileName = "initialize.ps1"
        parameters = {
          fileSystemMounts = [
            {
              enable = false # File Storage Read
              mount  = "mount -o anon nolock \\\\azstudio1.blob.core.windows.net\\azstudio1\\content R:"
            },
            {
              enable = false # File Cache Read
              mount  = "mount -o anon nolock \\\\cache.artist.studio\\mnt\\content R:"
            },
            {
              enable = false # File Storage Write
              mount  = "mount -o anon nolock \\\\azstudio1.blob.core.windows.net\\azstudio1\\content W:"
            },
            {
              enable = false # File Cache Write
              mount  = "mount -o anon nolock \\\\cache.artist.studio\\mnt\\content W:"
            },
            {
              enable = true # Job Scheduler
              mount  = "mount -o anon \\\\scheduler.artist.studio\\Deadline S:"
            }
          ]
          terminateNotification = { # https://learn.microsoft.com/azure/virtual-machine-scale-sets/virtual-machine-scale-sets-terminate-notification
            enable       = true
            delayTimeout = "PT5M"
          }
        }
      }
      health = {
        enable      = true
        protocol    = "tcp"
        port        = 445
        requestPath = ""
      }
      monitor = {
        enable = false
      }
    }
  }
]

############################################################################
# Batch (https://learn.microsoft.com/azure/batch/batch-technical-overview) #
############################################################################

batch = {
  enable = false
  account = {
    name = "azstudio"
    storage = {
      accountName       = ""
      resourceGroupName = ""
    }
  }
  pools = [
    {
      enable      = false
      name        = "LnxFarmC"
      displayName = "Linux Render Farm (CPU)"
      node = {
        image = {
          id      = "/subscriptions/5cc0d8f1-3643-410c-8646-1a2961134bd3/resourceGroups/ArtistAnywhere.Image/providers/Microsoft.Compute/galleries/azstudio/images/Linux/versions/2.0.0"
          agentId = "batch.node.el 9"
        }
        machine = {
          size  = "Standard_HB120rs_v3" # https://learn.microsoft.com/azure/batch/batch-pool-vm-sizes
          count = 2
        }
        osDisk = {
          ephemeral = {
            enable = true # https://learn.microsoft.com/azure/batch/create-pool-ephemeral-os-disk
          }
        }
        deallocationMode   = "Terminate"
        maxConcurrentTasks = 1
      }
      spot = {
        enable = true # https://learn.microsoft.com/azure/batch/batch-spot-vms
      }
      fillMode = {
        nodePack = false
      }
    },
    {
      enable      = false
      name        = "LnxFarmG"
      displayName = "Linux Render Farm (GPU)"
      node = {
        image = {
          id      = "/subscriptions/5cc0d8f1-3643-410c-8646-1a2961134bd3/resourceGroups/ArtistAnywhere.Image/providers/Microsoft.Compute/galleries/azstudio/images/Linux/versions/2.1.0"
          agentId = "batch.node.el 9"
        }
        machine = {
          size  = "Standard_NV18ads_A10_v5" # https://learn.microsoft.com/azure/batch/batch-pool-vm-sizes
          count = 2
        }
        osDisk = {
          ephemeral = {
            enable = true # https://learn.microsoft.com/azure/batch/create-pool-ephemeral-os-disk
          }
        }
        deallocationMode   = "Terminate"
        maxConcurrentTasks = 1
      }
      spot = {
        enable = false # https://learn.microsoft.com/azure/batch/batch-spot-vms
      }
      fillMode = {
        nodePack = false
      }
    },
    {
      enable      = false
      name        = "WinFarmC"
      displayName = "Windows Render Farm (CPU)"
      node = {
        image = {
          id      = "/subscriptions/5cc0d8f1-3643-410c-8646-1a2961134bd3/resourceGroups/ArtistAnywhere.Image/providers/Microsoft.Compute/galleries/azstudio/images/WinFarm/versions/2.0.0"
          agentId = "batch.node.windows amd64"
        }
        machine = {
          size  = "Standard_HB120rs_v3" # https://learn.microsoft.com/azure/batch/batch-pool-vm-sizes
          count = 2
        }
        osDisk = {
          ephemeral = {
            enable = true # https://learn.microsoft.com/azure/batch/create-pool-ephemeral-os-disk
          }
        }
        deallocationMode   = "Terminate"
        maxConcurrentTasks = 1
      }
      spot = {
        enable = true # https://learn.microsoft.com/azure/batch/batch-spot-vms
      }
      fillMode = {
        nodePack = false
      }
    },
    {
      enable      = false
      name        = "WinFarmG"
      displayName = "Windows Render Farm (GPU)"
      node = {
        image = {
          id      = "/subscriptions/5cc0d8f1-3643-410c-8646-1a2961134bd3/resourceGroups/ArtistAnywhere.Image/providers/Microsoft.Compute/galleries/azstudio/images/WinFarm/versions/2.1.0"
          agentId = "batch.node.windows amd64"
        }
        machine = {
          size  = "Standard_NV18ads_A10_v5" # https://learn.microsoft.com/azure/batch/batch-pool-vm-sizes
          count = 2
        }
        osDisk = {
          ephemeral = {
            enable = true # https://learn.microsoft.com/azure/batch/create-pool-ephemeral-os-disk
          }
        }
        deallocationMode   = "Terminate"
        maxConcurrentTasks = 1
      }
      spot = {
        enable = false # https://learn.microsoft.com/azure/batch/batch-spot-vms
      }
      fillMode = {
        nodePack = false
      }
    }
  ]
}

###########################################################################
# Open AI (https://learn.microsoft.com/azure/ai-services/openai/overview) #
###########################################################################

openAI = {
  enable      = false
  regionName  = "CanadaEast"
  accountName = ""
  domainName  = ""
  serviceTier = "S0"
  modelDeployments = [
    {
      enable  = true
      name    = "gpt-4"
      format  = "OpenAI"
      version = ""
      scale   = "Standard"
    }
  ]
  storage = {
    enable = false
  }
}

#######################################################################
# Resource dependency configuration for pre-existing deployments only #
#######################################################################

computeNetwork = {
  enable            = false
  name              = ""
  subnetName        = ""
  resourceGroupName = ""
}

storageAccount = {
  enable             = false
  name               = ""
  resourceGroupName  = ""
}
