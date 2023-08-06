// Execute this main file to configure Azure Machine Learning end-to-end in a moderately secure set up
// Parameters
@minLength(2)
@maxLength(10)
@description('Prefix for all resource names.')
param prefix string

@description('Azure region used for the deployment of all resources.')
param location string = resourceGroup().location

@description('Set of tags to apply to all resources.')
param tags object = {}

@description('Virtual network address prefix')
param vnetAddressPrefix string = '192.168.0.0/16'

@description('Training subnet address prefix')
param trainingSubnetPrefix string = '192.168.0.0/24'

@description('Scoring subnet address prefix')
param scoringSubnetPrefix string = '192.168.1.0/24'

@description('Bastion subnet address prefix')
param azureBastionSubnetPrefix string = '192.168.250.0/27'

@description('Virtual network out of region address prefix')
param vnetGeoAddressPrefix string = '10.0.0.0/16'

@description('AI subnet out of region address prefix')
param aiGeoSubnetPrefix string = '10.0.0.0/24'

@description('Deploy a Bastion jumphost to access the network-isolated environment?')
param deployJumphost bool = true

@description('Jumphost virtual machine username')
param dsvmJumpboxUsername string

@secure()
@minLength(8)
@description('Jumphost virtual machine password')
param dsvmJumpboxPassword string

@description('Enable public IP for Azure Machine Learning compute nodes')
param machineLearningComputePublicIp bool = true

@description('VM size for the default compute cluster and instance')
param machineLearningComputeDefaultVmSize string = 'Standard_DS3_v2'

@description('VM size for the default Bastion jumphost')
param jumphostComputeDefaultVmSize string = 'Standard_DS3_v2'

// Variables
var name = toLower('${prefix}')

// Create a short, unique suffix, that will be unique to each resource group
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 4)

// // reader definition for studio access
// var roleDefinitionID = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'

// Virtual network and network security group
module nsg 'modules/nsg.bicep' = { 
  name: 'nsg-${name}-${uniqueSuffix}-deployment'
  params: {
    location: location
    tags: tags 
    nsgName: 'nsg-${name}-${uniqueSuffix}'
  }
}

module vnet 'modules/vnet.bicep' = { 
  name: 'vnet-${name}-${uniqueSuffix}-deployment'
  params: {
    location: location
    virtualNetworkName: 'vnet-${name}-${uniqueSuffix}'
    networkSecurityGroupId: nsg.outputs.networkSecurityGroup
    vnetAddressPrefix: vnetAddressPrefix
    trainingSubnetPrefix: trainingSubnetPrefix
    scoringSubnetPrefix: scoringSubnetPrefix
    bastionSubnetPrefix: azureBastionSubnetPrefix
    virtualNetworkGeoName: 'vnet-geo-${name}-${uniqueSuffix}'
    vnetGeoAddressPrefix: vnetGeoAddressPrefix
    aiGeoSubnetPrefix: aiGeoSubnetPrefix
    // need to figure out how to specify bastion Subnet, if not redeployment will try to delete subnet
    // bastionSubnetPrefix: azureBastionSubnetPrefix
    tags: tags
  }
}

// Dependent resources for the Azure Machine Learning workspace
module keyvault 'modules/keyvault.bicep' = {
  name: 'kv-${name}-${uniqueSuffix}-deployment'
  params: {
    location: location
    keyVaultName: 'kv-${name}-${uniqueSuffix}'
    keyVaultPleName: 'ple-${name}-${uniqueSuffix}-kv'
    subnetId: '${vnet.outputs.id}/subnets/snet-training'
    virtualNetworkId: vnet.outputs.id
    tags: tags
  }
}

module storage 'modules/storage.bicep' = {
  name: 'st${name}${uniqueSuffix}-deployment'
  params: {
    location: location
    storageName: 'st${name}${uniqueSuffix}'
    storagePleBlobName: 'ple-${name}-${uniqueSuffix}-st-blob'
    storagePleFileName: 'ple-${name}-${uniqueSuffix}-st-file'
    storageSkuName: 'Standard_LRS'
    subnetId: '${vnet.outputs.id}/subnets/snet-training'
    virtualNetworkId: vnet.outputs.id
    tags: tags
  }
}

module containerRegistry 'modules/containerregistry.bicep' = {
  name: 'cr${name}${uniqueSuffix}-deployment'
  params: {
    location: location
    containerRegistryName: 'cr${name}${uniqueSuffix}'
    containerRegistryPleName: 'ple-${name}-${uniqueSuffix}-cr'
    subnetId: '${vnet.outputs.id}/subnets/snet-training'
    virtualNetworkId: vnet.outputs.id
    tags: tags
  }
}

module applicationInsights 'modules/applicationinsights.bicep' = {
  name: 'appi-${name}-${uniqueSuffix}-deployment'
  params: {
    location: location
    applicationInsightsName: 'appi-${name}-${uniqueSuffix}'
    logAnalyticsWorkspaceName: 'ws-${name}-${uniqueSuffix}'
    logAnalyticsWorkspaceSku: 'PerGB2018'
    retentionInDays: 30
    logAnalyticsPlsName:' pls-${name}-${uniqueSuffix}-appi'
    logAnalyticsPleName: 'ple-${name}-${uniqueSuffix}-appi'
    subnetId: '${vnet.outputs.id}/subnets/snet-training'
    virtualNetworkId: vnet.outputs.id
    tags: tags
  }
}

module machineLearningWorkspace 'modules/machinelearning.bicep' = {
  name: 'mlw-${name}-${uniqueSuffix}-deployment'
  params: {
    // workspace organization
    machineLearningName: 'mlw-${name}-${uniqueSuffix}'
    machineLearningFriendlyName: 'Private link endpoint sample workspace'
    machineLearningDescription: 'This is an example workspace having a private link endpoint.'
    location: location
    prefix: name
    tags: tags

    // dependent resources
    applicationInsightsId: applicationInsights.outputs.applicationInsightsId
    containerRegistryId: containerRegistry.outputs.containerRegistryId
    keyVaultId: keyvault.outputs.keyVaultId
    storageAccountId: storage.outputs.storageId

    // networking
    subnetId: '${vnet.outputs.id}/subnets/snet-training'
    computeSubnetId: '${vnet.outputs.id}/subnets/snet-training'
    // aksSubnetId: '${vnet.outputs.id}/subnets/snet-scoring'
    virtualNetworkId: vnet.outputs.id
    machineLearningPleName: 'ple-${name}-${uniqueSuffix}-mlw'

    // compute
    machineLearningComputePublicIp: machineLearningComputePublicIp
    // mlAksName: 'aks-${name}-${uniqueSuffix}'
    vmSizeParam: machineLearningComputeDefaultVmSize
  }
  dependsOn: [
    keyvault
    containerRegistry
    applicationInsights
    storage
  ]
}

// Optional VM and Bastion jumphost to help access the network isolated environment
module dsvm 'modules/dsvmjumpbox.bicep' = if (deployJumphost) {
  name: 'vm-${name}-${uniqueSuffix}-deployment'
  params: {
    location: location
    virtualMachineName: 'vm-${name}-${uniqueSuffix}'
    subnetId: '${vnet.outputs.id}/subnets/snet-training'
    adminUsername: dsvmJumpboxUsername
    adminPassword: dsvmJumpboxPassword
    networkSecurityGroupId: nsg.outputs.networkSecurityGroup
    vmSizeParameter: jumphostComputeDefaultVmSize
  }
}

// module bastion 'modules/bastion.bicep' = if (deployJumphost) {
//   name: 'bas-${name}-${uniqueSuffix}-deployment'
//   params: {
//     bastionHostName: 'bas-${name}-${uniqueSuffix}'
//     location: location
//     vnetName: vnet.outputs.name
//     bastionSubnetPrefix: azureBastionSubnetPrefix
//   }
//   dependsOn: [
//     vnet
//   ]
// }

// Azure AI Services
// Currently only Azure OpenAI
module openai 'modules/openai.bicep' = {
  name: 'oai-${name}-${uniqueSuffix}-deployment'
  params: {
    // not available in southeastasia for now
    location: 'eastus'
    openaiName: 'oai-${name}-${uniqueSuffix}'
    openaiPleName: 'ple-${name}-${uniqueSuffix}-oai'
    subnetId: '${vnet.outputs.idgeo}/subnets/snet-ai-geo'
    virtualNetworkId: vnet.outputs.idgeo
    tags: tags
  }
}

// // TO CHECK: To enable usage of Studio, there are additional steps to take. Can consider shifting out subsequently as separate module
// resource storagePrivateEndpointBlob 'Microsoft.Network/privateEndpoints@2023-04-01' existing = {
//   name: 'ple-${name}-${uniqueSuffix}-st-blob'
// }

// resource storagePrivateEndpointFile 'Microsoft.Network/privateEndpoints@2023-04-01' existing = {
//   name: 'ple-${name}-${uniqueSuffix}-st-file'
// }

// resource storageBlobRoleAssignPle 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
//   name: guid(roleDefinitionID, resourceGroup().id, 'blob')
//   scope: storagePrivateEndpointBlob
//   properties: {
//     // assign to Azure ML Workspace
//     principalId: machineLearningWorkspace.outputs.machineLearningId
//     roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionID)
//   }
// }

// resource storageFileRoleAssignPle 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
//   name: guid(roleDefinitionID, resourceGroup().id, 'file')
//   scope: storagePrivateEndpointFile
//   properties: {
//     // assign to Azure ML Workspace
//     principalId: machineLearningWorkspace.outputs.machineLearningId
//     roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionID)
//   }
// }
