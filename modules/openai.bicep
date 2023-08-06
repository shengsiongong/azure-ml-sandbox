// Create OpenAI Resource and deployment
// https://techcommunity.microsoft.com/t5/fasttrack-for-azure/deploy-and-run-a-azure-openai-chatgpt-application-on-aks-via/ba-p/3834619
// https://github.com/Azure-Samples/azure-search-openai-demo/blob/main/infra/main.bicep
// Subsequently can get diagnostics to flow to application insights
// vnet must be same region as resource... so must create another vnet for openai???\
// https://learn.microsoft.com/en-us/azure/virtual-network/tutorial-connect-virtual-networks-portal (VNet Peering)
// https://learn.microsoft.com/en-us/azure/vpn-gateway/vpn-gateway-howto-vnet-vnet-resource-manager-portal (VPN Gateway)
@description('Azure region of the deployment')
param location string = 'eastus'

@description('Tags to apply to the OpenAI')
param tags object = {}

@description('Name of the OpenAI')
param openaiName string

@description('Specifies the OpenAI deployments to create.')
param deployments array = [
  {
    name: 'text-embedding-ada-002'
    version: '2'
    raiPolicyName: ''
    capacity: 30
    scaleType: 'Standard'
  }
  {
    name: 'gpt-35-turbo-16k'
    version: '0613'
    raiPolicyName: ''
    capacity: 30
    scaleType: 'Standard'
  }
]

@description('The name of OpenAI private link endpoint')
param openaiPleName string

@description('The Subnet ID where the OpenAI Private Link is to be created')
param subnetId string

@description('The VNet ID where OpenAI Private Link is to be created')
param virtualNetworkId string

// https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns
var privateDnsZoneName = 'privatelink.openai.azure.com'

var groupName = 'account' 

resource openai 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: openaiName
  location: location
  kind: 'OpenAI'
  sku: {
    name: 'S0'
  }
  properties: {
    publicNetworkAccess: 'Disabled'
    customSubDomainName: openaiName
  }
}

resource openaiModel 'Microsoft.CognitiveServices/accounts/deployments@2023-05-01' = [for deployment in deployments: {
  parent: openai
  name: deployment.name
  sku:{
    name: deployment.scaleType
    capacity: deployment.capacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: deployment.name
      version: deployment.version
    }
    raiPolicyName: deployment.raiPolicyName
    // scaleSettings: {
    //   capacity: deployment.capacity
    //   scaleType: deployment.scaleType
    // }
  }
}]

resource openaiPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-04-01' = {
  name: openaiPleName
  location: location
  tags: tags
  properties: {
    privateLinkServiceConnections: [
      {
        name: openaiPleName
        properties: {
          groupIds: [
            groupName
          ]
          privateLinkServiceId: openai.id
        }
      }
    ]
    subnet: {
      id: subnetId
    }
  }
}

resource openaiPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateDnsZoneName
  location: 'global'
}

resource openaiPrivateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: openaiPrivateDnsZone
  name: '${privateDnsZoneName}-link' // uniqueString(keyVault.id)
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetworkId
    }
  }
}

resource privateEndpointDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-04-01' = {
  parent: openaiPrivateEndpoint
  name: '${groupName}-PrivateDnsZoneGroup'
  properties:{
    privateDnsZoneConfigs: [
      {
        name: privateDnsZoneName
        properties:{
          privateDnsZoneId: openaiPrivateDnsZone.id
        }
      }
    ]
  }
}

output openaiId string = openai.id
output openaiKeys string = openai.listKeys().key1
