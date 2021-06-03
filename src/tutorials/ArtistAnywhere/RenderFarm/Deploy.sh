#!/bin/bash

computeRegionName=""    # List available regions via Azure CLI (az account list-locations --query [].name)
resourceGroupPrefix=""  # Alphanumeric characters, periods, underscores, hyphens and parentheses allowed

computeNetworkName=""
networkResourceGroupName=""

managedIdentityName=""
managedIdentityResourceGroupName=""

imageBuilderStorageAccountName=""
imageBuilderStorageContainerName=""

renderManagerHost=""

modulePath=$(pwd)
rootDirectory="$modulePath/.."
moduleDirectory="$(basename $(pwd))"
source "$rootDirectory/Functions.sh"

# (12) Render Farm Image Template
moduleName="(12) Render Farm Image Template"
New-TraceMessage "$moduleName" false

Set-StorageScripts $rootDirectory $moduleDirectory $imageBuilderStorageAccountName $imageBuilderStorageContainerName

templateResourcesPath="$modulePath/12.Image.json"
templateParametersPath="$modulePath/12.Image.Parameters.json"

Set-OverrideParameter $templateParametersPath "managedIdentity" "name" $managedIdentityName
Set-OverrideParameter $templateParametersPath "managedIdentity" "resourceGroupName" $managedIdentityResourceGroupName

Set-OverrideParameter $templateParametersPath "virtualNetwork" "name" $computeNetworkName
Set-OverrideParameter $templateParametersPath "virtualNetwork" "resourceGroupName" $networkResourceGroupName

resourceGroupName=$(Set-ResourceGroup $computeRegionName $resourceGroupPrefix ".Gallery")
groupDeployment=$(az deployment group create --resource-group $resourceGroupName --template-file $templateResourcesPath --parameters $templateParametersPath | jq -c .)

imageTemplates=$(Get-PropertyValue "$groupDeployment" .properties.outputs.imageTemplates.value true)
imageGallery=$(Get-PropertyValue "$groupDeployment" .properties.outputs.imageGallery.value true)

New-TraceMessage "$moduleName" true

# (12) Render Farm Image Build
moduleName="(12) Render Farm Image Build"
Build-ImageTemplates "$moduleName" $computeRegionName $imageTemplates $imageGallery

# (13) Render Farm Scale Set
moduleName="(13) Render Farm Scale Set"
New-TraceMessage "$moduleName" false

templateResourcesPath="$modulePath/13.ScaleSet.json"
templateParametersPath="$modulePath/13.ScaleSet.Parameters.json"

Set-OverrideParameter $templateParametersPath "managedIdentity" "name" $managedIdentityName
Set-OverrideParameter $templateParametersPath "managedIdentity" "resourceGroupName" $managedIdentityResourceGroupName

Set-OverrideParameter $templateParametersPath "virtualNetwork" "name" $computeNetworkName
Set-OverrideParameter $templateParametersPath "virtualNetwork" "resourceGroupName" $networkResourceGroupName

Set-OverrideParameter $templateParametersPath "customExtension" "scriptParameters.renderManagerHost" $renderManagerHost

resourceGroupName=$(Set-ResourceGroup $computeRegionName $resourceGroupPrefix ".Farm")
groupDeployment=$(az deployment group create --resource-group $resourceGroupName --template-file $templateResourcesPath --parameters $templateParametersPath | jq -c .)

renderFarms=$(Get-PropertyValue "$groupDeployment" .properties.outputs.renderFarms.value true)

New-TraceMessage "$moduleName" true