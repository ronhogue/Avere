terraform {
  required_version = ">= 1.3.6"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.34.0"
    }
  }
  backend "azurerm" {
    key = "4.image.builder"
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    template_deployment {
      delete_nested_items_during_deletion = false
    }
  }
}

module "global" {
  source = "../0.global/module"
}

variable "resourceGroupName" {
  type = string
}

variable "imageGallery" {
  type = object(
    {
      name = string
      imageDefinitions = list(object(
        {
          name       = string
          type       = string
          generation = string
          publisher  = string
          offer      = string
          sku        = string
        }
      ))
    }
  )
}

variable "imageTemplates" {
  type = list(object(
    {
      name = string
      image = object(
        {
          definitionName = string
          inputVersion   = string
        }
      )
      build = object(
        {
          machineType    = string
          machineSize    = string
          gpuPlatform    = list(string)
          osDiskSizeGB   = number
          timeoutMinutes = number
          outputVersion  = string
          renderEngines  = list(string)
        }
      )
    }
  ))
}

variable "computeNetwork" {
  type = object(
    {
      name              = string
      resourceGroupName = string
    }
  )
}

data "azurerm_user_assigned_identity" "render" {
  name                = module.global.managedIdentityName
  resource_group_name = module.global.resourceGroupName
}

data "azurerm_key_vault" "render" {
  name                = module.global.keyVaultName
  resource_group_name = module.global.resourceGroupName
}

data "azurerm_key_vault_secret" "admin_username" {
  name         = module.global.keyVaultSecretNameAdminUsername
  key_vault_id = data.azurerm_key_vault.render.id
}

data "azurerm_key_vault_secret" "admin_password" {
  name         = module.global.keyVaultSecretNameAdminPassword
  key_vault_id = data.azurerm_key_vault.render.id
}

data "terraform_remote_state" "network" {
  backend = "azurerm"
  config = {
    resource_group_name  = module.global.resourceGroupName
    storage_account_name = module.global.storageAccountName
    container_name       = module.global.storageContainerName
    key                  = "1.network"
  }
}

data "azurerm_resource_group" "network" {
  name = data.azurerm_virtual_network.compute.resource_group_name
}

data "azurerm_virtual_network" "compute" {
  name                = !local.stateExistsNetwork ? var.computeNetwork.name : data.terraform_remote_state.network.outputs.computeNetwork.name
  resource_group_name = !local.stateExistsNetwork ? var.computeNetwork.resourceGroupName : data.terraform_remote_state.network.outputs.resourceGroupName
}

locals {
  stateExistsNetwork = try(length(data.terraform_remote_state.network.outputs) >= 0, false)
}

resource "azurerm_resource_group" "image" {
  name     = var.resourceGroupName
  location = module.global.regionName
}

resource "azurerm_role_assignment" "network" {
  role_definition_name = "Virtual Machine Contributor" # https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#virtual-machine-contributor
  principal_id         = data.azurerm_user_assigned_identity.render.principal_id
  scope                = data.azurerm_resource_group.network.id
}

resource "azurerm_role_assignment" "image" {
  role_definition_name = "Contributor" # https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#contributor
  principal_id         = data.azurerm_user_assigned_identity.render.principal_id
  scope                = azurerm_resource_group.image.id
}

resource "azurerm_shared_image_gallery" "gallery" {
  name                = var.imageGallery.name
  resource_group_name = azurerm_resource_group.image.name
  location            = azurerm_resource_group.image.location
}

resource "azurerm_shared_image" "definitions" {
  count               = length(var.imageGallery.imageDefinitions)
  name                = var.imageGallery.imageDefinitions[count.index].name
  resource_group_name = azurerm_resource_group.image.name
  location            = azurerm_resource_group.image.location
  gallery_name        = azurerm_shared_image_gallery.gallery.name
  os_type             = var.imageGallery.imageDefinitions[count.index].type
  hyper_v_generation  = var.imageGallery.imageDefinitions[count.index].generation
  identifier {
    publisher = var.imageGallery.imageDefinitions[count.index].publisher
    offer     = var.imageGallery.imageDefinitions[count.index].offer
    sku       = var.imageGallery.imageDefinitions[count.index].sku
  }
}

resource "azurerm_resource_group_template_deployment" "image_builder" {
  name                = "ImageBuilder"
  resource_group_name = azurerm_resource_group.image.name
  deployment_mode     = "Incremental"
  parameters_content  = jsonencode({
    "renderManager" = {
      value = module.global.renderManager
    }
    "managedIdentityName" = {
      value = module.global.managedIdentityName
    }
    "managedIdentityResourceGroupName" = {
      value = module.global.resourceGroupName
    }
    "imageGalleryName" = {
      value = var.imageGallery.name
    }
    "imageTemplates" = {
      value = var.imageTemplates
    }
    "keyVaultSecretAdminUsername" = {
      value = data.azurerm_key_vault_secret.admin_username.value
    }
    "keyVaultSecretAdminPassword" = {
      value = data.azurerm_key_vault_secret.admin_password.value
    }
  })
  template_content = <<TEMPLATE
    {
      "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
      "contentVersion": "1.0.0.0",
      "parameters": {
        "renderManager": {
          "type": "string"
        },
        "managedIdentityName": {
          "type": "string"
        },
        "managedIdentityResourceGroupName": {
          "type": "string"
        },
        "imageGalleryName": {
          "type": "string"
        },
        "imageTemplates": {
          "type": "array"
        },
        "keyVaultSecretAdminUsername": {
          "type": "string"
        },
        "keyVaultSecretAdminPassword": {
          "type": "string"
        }
      },
      "variables": {
        "imageBuilderApiVersion": "2022-02-14",
        "imageGalleryApiVersion": "2022-08-03"
      },
      "functions": [
        {
          "namespace": "fx",
          "members": {
            "GetCustomizeCommandsLinux": {
              "parameters": [
                {
                  "name": "imageTemplate",
                  "type": "object"
                },
                {
                  "name": "renderManager",
                  "type": "string"
                },
                {
                  "name": "adminUsername",
                  "type": "string"
                },
                {
                  "name": "adminPassword",
                  "type": "string"
                }
              ],
              "output": {
                "type": "array",
                "value": [
                  {
                    "type": "Shell",
                    "inline": [
                      "[concat('hostname ', parameters('imageTemplate').name)]"
                    ]
                  },
                  {
                    "type": "File",
                    "sourceUri": "https://github.com/Azure/Avere/blob/main/src/terraform/examples/e2e/4.image.builder/customize.sh",
                    "destination": "/tmp/customize.sh"
                  },
                  {
                    "type": "File",
                    "sourceUri": "https://github.com/Azure/Avere/blob/main/src/terraform/examples/e2e/4.image.builder/onTerminate.sh",
                    "destination": "/tmp/onTerminate.sh"
                  },
                  {
                    "type": "Shell",
                    "inline": [
                      "[format('cat /tmp/customize.sh | tr -d \r | {0} /bin/bash', concat('buildConfigEncoded=', base64(string(union(parameters('imageTemplate').build, createObject('renderManager', parameters('renderManager')), createObject('adminUsername', parameters('adminUsername')), createObject('adminPassword', parameters('adminPassword')))))))]"
                    ]
                  }
                ]
              }
            },
            "GetCustomizeCommandsWindows": {
              "parameters": [
                {
                  "name": "imageTemplate",
                  "type": "object"
                },
                {
                  "name": "renderManager",
                  "type": "string"
                }
              ],
              "output": {
                "type": "array",
                "value": [
                  {
                    "type": "PowerShell",
                    "inline": [
                      "[concat('Rename-Computer -NewName ', parameters('imageTemplate').name)]"
                    ]
                  },
                  {
                    "type": "WindowsRestart"
                  },
                  {
                    "type": "File",
                    "sourceUri": "https://github.com/Azure/Avere/blob/main/src/terraform/examples/e2e/4.image.builder/customize.ps1",
                    "destination": "C:\\Users\\Public\\Downloads\\customize.ps1"
                  },
                  {
                    "type": "File",
                    "sourceUri": "https://github.com/Azure/Avere/blob/main/src/terraform/examples/e2e/4.image.builder/onTerminate.ps1",
                    "destination": "C:\\Users\\Public\\Downloads\\onTerminate.ps1"
                  },
                  {
                    "type": "PowerShell",
                    "inline": [
                      "[concat('C:\\Users\\Public\\Downloads\\customize.ps1 -buildConfigEncoded ', base64(string(union(parameters('imageTemplate').build, createObject('renderManager', parameters('renderManager'))))))]"
                    ],
                    "runElevated": "[if(and(equals(parameters('renderManager'), 'Deadline'), equals(parameters('imageTemplate').build.machineType, 'Scheduler')), true(), false())]"
                  },
                  {
                    "type": "WindowsRestart"
                  }
                ]
              }
            }
          }
        }
      ],
      "resources": [
        {
          "type": "Microsoft.VirtualMachineImages/imageTemplates",
          "name": "[parameters('imageTemplates')[copyIndex()].name]",
          "apiVersion": "[variables('imageBuilderApiVersion')]",
          "location": "[resourceGroup().location]",
          "identity": {
            "type": "UserAssigned",
            "userAssignedIdentities": {
              "[resourceId(parameters('managedIdentityResourceGroupName'), 'Microsoft.ManagedIdentity/userAssignedIdentities', parameters('managedIdentityName'))]": {
              }
            }
          },
          "properties": {
            "vmProfile": {
              "vmSize": "[parameters('imageTemplates')[copyIndex()].build.machineSize]",
              "osDiskSizeGB": "[parameters('imageTemplates')[copyIndex()].build.osDiskSizeGB]"
            },
            "source": {
              "type": "PlatformImage",
              "publisher": "[reference(resourceId('Microsoft.Compute/galleries/images', parameters('imageGalleryName'), parameters('imageTemplates')[copyIndex()].image.definitionName), variables('imageGalleryApiVersion')).identifier.publisher]",
              "offer": "[reference(resourceId('Microsoft.Compute/galleries/images', parameters('imageGalleryName'), parameters('imageTemplates')[copyIndex()].image.definitionName), variables('imageGalleryApiVersion')).identifier.offer]",
              "sku": "[reference(resourceId('Microsoft.Compute/galleries/images', parameters('imageGalleryName'), parameters('imageTemplates')[copyIndex()].image.definitionName), variables('imageGalleryApiVersion')).identifier.sku]",
              "version": "[parameters('imageTemplates')[copyIndex()].image.inputVersion]"
            },
            "customize": "[if(equals(reference(resourceId('Microsoft.Compute/galleries/images', parameters('imageGalleryName'), parameters('imageTemplates')[copyIndex()].image.definitionName), variables('imageGalleryApiVersion')).osType, 'Windows'), fx.GetCustomizeCommandsWindows(parameters('imageTemplates')[copyIndex()], parameters('renderManager')), fx.GetCustomizeCommandsLinux(parameters('imageTemplates')[copyIndex()], parameters('renderManager'), parameters('keyVaultSecretAdminUsername'), parameters('keyVaultSecretAdminPassword')))]",
            "buildTimeoutInMinutes": "[parameters('imageTemplates')[copyIndex()].build.timeoutMinutes]",
            "distribute": [
              {
                "type": "SharedImage",
                "runOutputName": "[concat(parameters('imageTemplates')[copyIndex()].name, '-', parameters('imageTemplates')[copyIndex()].build.outputVersion)]",
                "galleryImageId": "[resourceId('Microsoft.Compute/galleries/images/versions', parameters('imageGalleryName'), parameters('imageTemplates')[copyIndex()].image.definitionName, parameters('imageTemplates')[copyIndex()].build.outputVersion)]",
                "replicationRegions": [
                  "[resourceGroup().location]"
                ],
                "artifactTags": {
                  "imageTemplateName": "[parameters('imageTemplates')[copyIndex()].name]"
                }
              }
            ]
          },
          "copy": {
            "name": "imageTemplates",
            "count": "[length(parameters('imageTemplates'))]"
          }
        }
      ],
      "outputs": {
      }
    }
  TEMPLATE
  depends_on = [
    azurerm_shared_image.definitions
  ]
}

output "resourceGroupName" {
  value = var.resourceGroupName
}

output "imageGallery" {
  value = var.imageGallery
}

output "imageTemplates" {
  value = var.imageTemplates
}
