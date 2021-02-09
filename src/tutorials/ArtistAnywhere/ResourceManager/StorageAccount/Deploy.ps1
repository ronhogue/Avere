param (
    $resourceGroup = @{
        "name" = ""
        "regionName" = "WestUS2"    # https://azure.microsoft.com/global-infrastructure/geographies/
    },
    $storageAccount = @{            # https://docs.microsoft.com/azure/storage/common/storage-account-overview
        "name" = ""
        "type" = "StorageV2"
        "replication" = "Standard_LRS"
        "blobContainers" = @(
            @{
                "name" = ""
                "publicAccess" = "None"
            }
        )
        "fileShares" = @(
            @{
                "name" = ""
                "size" = 5120
            }
        )
        "messageQueues" = @(
            @{
                "name" = ""
            }
        )
    }
)

az group create --name $resourceGroup.name --location $resourceGroup.regionName

$templateFile = "$PSScriptRoot/Template.json"
$templateParameters = "$PSScriptRoot/Template.Parameters.json"

$templateConfig = Get-Content -Path $templateParameters -Raw | ConvertFrom-Json
$templateConfig.parameters.storageAccount.value = $storageAccount
$templateConfig | ConvertTo-Json -Depth 5 | Out-File $templateParameters

az deployment group create --resource-group $resourceGroup.name --template-file $templateFile --parameters $templateParameters
