param (
  $computeRegionName = "",    # List available regions via Azure CLI (az account list-locations --query [].name)
  $resourceGroupPrefix = "",  # Alphanumeric characters, periods, underscores, hyphens and parentheses allowed

  $computeNetworkName = "",
  $networkResourceGroupName = "",

  $managedIdentityName = "",
  $managedIdentityResourceGroupName = "",

  $imageBuilderStorageAccountName = "",
  $imageBuilderStorageContainerName = "",

  $renderManagerHost = ""
)

$modulePath = $PSScriptRoot
$rootDirectory = "$modulePath/.."
$moduleDirectory = (Get-Item -Path $modulePath).Name
Import-Module "$rootDirectory/Functions.psm1"

# (14) Artist Workstation Image Template
$moduleName = "(14) Artist Workstation Image Template"
New-TraceMessage $moduleName $false

Set-StorageScripts $rootDirectory $moduleDirectory $imageBuilderStorageAccountName $imageBuilderStorageContainerName

$templateResourcesPath = "$modulePath/14.Image.json"
$templateParametersPath = "$modulePath/14.Image.Parameters.json"

Set-OverrideParameter $templateParametersPath "managedIdentity" "name" $managedIdentityName
Set-OverrideParameter $templateParametersPath "managedIdentity" "resourceGroupName" $managedIdentityResourceGroupName

Set-OverrideParameter $templateParametersPath "virtualNetwork" "name" $computeNetworkName
Set-OverrideParameter $templateParametersPath "virtualNetwork" "resourceGroupName" $networkResourceGroupName

$resourceGroupName = Set-ResourceGroup $computeRegionName $resourceGroupPrefix ".Gallery"
$groupDeployment = (az deployment group create --resource-group $resourceGroupName --template-file $templateResourcesPath --parameters $templateParametersPath) | ConvertFrom-Json

$imageTemplates = $groupDeployment.properties.outputs.imageTemplates.value
$imageGallery = $groupDeployment.properties.outputs.imageGallery.value

New-TraceMessage $moduleName $true

# (14) Artist Workstation Image Build
$moduleName = "(14) Artist Workstation Image Build"
Build-ImageTemplates $moduleName $computeRegionName $imageTemplates $imageGallery

# (15) Artist Workstation Machine
$moduleName = "(15) Artist Workstation Machine"
New-TraceMessage $moduleName $false

$templateResourcesPath = "$modulePath/15.Machine.json"
$templateParametersPath = "$modulePath/15.Machine.Parameters.json"

Set-OverrideParameter $templateParametersPath "managedIdentity" "name" $managedIdentityName
Set-OverrideParameter $templateParametersPath "managedIdentity" "resourceGroupName" $managedIdentityResourceGroupName

Set-OverrideParameter $templateParametersPath "virtualNetwork" "name" $computeNetworkName
Set-OverrideParameter $templateParametersPath "virtualNetwork" "resourceGroupName" $networkResourceGroupName

Set-OverrideParameter $templateParametersPath "customExtension" "scriptParameters.renderManagerHost" $renderManagerHost

$resourceGroupName = Set-ResourceGroup $computeRegionName $resourceGroupPrefix ".Workstation"
$groupDeployment = (az deployment group create --resource-group $resourceGroupName --template-file $templateResourcesPath --parameters $templateParametersPath) | ConvertFrom-Json

$artistWorkstations = $groupDeployment.properties.outputs.artistWorkstations.value

New-TraceMessage $moduleName $true
