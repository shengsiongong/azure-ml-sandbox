// Create Virtual Network
@description('Name of virtual network resource')
param virtualNetworkName string

@description('Azure region of deployment')
param location string = resourceGroup().location

@description('Tags to add to the resources')
param tags object = {}

@description('Virtual network address prefix')
param vnetAddressPrefix string = '192.168.0.0/16'

@description('Training subnet address prefix')
param trainingSubnetPrefix string = '192.168.0.0/24'

@description('Scoring subnet address prefix')
param scoringSubnetPrefix string = '192.168.1.0/24'

@description('Scoring subnet address prefix')
param bastionSubnetPrefix string = '192.168.1.0/24'

@description('The name of the Bastion host')
param bastionHostName string = 'bastion-jumpbox'

@description('Group ID of the network security group')
param networkSecurityGroupId string

@description('Name of virtual network resource outside region')
param virtualNetworkGeoName string

@description('Virtual network out of region address prefix')
param vnetGeoAddressPrefix string

@description('AI subnet out of region address prefix')
param aiGeoSubnetPrefix string

@description('The name of the Bastion public IP address')
var publicIpAddressName = '${bastionHostName}-pip'

var bastionSubnetName = 'AzureBastionSubnet'

// @description('Deploy a Bastion jumphost to access the network-isolated environment?')
// param deployJumphost bool

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-04-01' = {
  name: virtualNetworkName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: 'snet-training'
        properties: {
          addressPrefix: trainingSubnetPrefix
          // default behavior - unclear on purpose
          privateEndpointNetworkPolicies: 'Disabled'
          // explicitly disabled to enable choosing of source IP address for private Links service
          privateLinkServiceNetworkPolicies: 'Disabled'
          networkSecurityGroup: {
            id: networkSecurityGroupId
          }
        }
      }
      {
        // currently not used, but needed for inference endpoints
        name: 'snet-scoring'
        properties: {
          addressPrefix: scoringSubnetPrefix
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Disabled'
          // template uses service endpoints here then private endpoints at the other resource
          // not sure why these connect to scoring subnet and not training subnet as well...
          // serviceEndpoints: [
          //   {
          //     service: 'Microsoft.KeyVault'
          //   }
          //   {
          //     service: 'Microsoft.ContainerRegistry'
          //   }
          //   {
          //     service: 'Microsoft.Storage'
          //   }
          // ]
          networkSecurityGroup: {
            id: networkSecurityGroupId
          }
        }
      }
      {
        // can't seem to figure out how to conditionally deploy this for now
        name: bastionSubnetName
        properties: {
          addressPrefix: bastionSubnetPrefix
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Disabled'
          // networkSecurityGroup: {
          //   id: networkSecurityGroupId
          // }       
        }
      }
    ]
  }
  resource bastionSubnetTemp 'subnets' existing = {
    name: bastionSubnetName
  }
}

resource publicIpAddressForBastion 'Microsoft.Network/publicIPAddresses@2023-04-01' = {
  name: publicIpAddressName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// TO REMOVE: USD $211.70/ month
resource bastionHost 'Microsoft.Network/bastionHosts@2023-04-01' = {
  name: bastionHostName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'IpConf'
        properties: {
          subnet: {
            id: virtualNetwork::bastionSubnetTemp.id
          }
          publicIPAddress: {
            id: publicIpAddressForBastion.id
          }
        }
      }
    ]
  }
}

// temporary virtual network outside of southeastasia region as Azure OpenAI not available locally
resource virtualNetworkGeo 'Microsoft.Network/virtualNetworks@2023-04-01' = {
  name: virtualNetworkGeoName
  location: 'eastus'
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetGeoAddressPrefix
      ]
    }
    subnets: [
      {
        name: 'snet-ai-geo'
        properties: {
          addressPrefix: aiGeoSubnetPrefix
          // default behavior - unclear on purpose
          privateEndpointNetworkPolicies: 'Disabled'
          // explicitly disabled to enable choosing of source IP address for private Links service
          privateLinkServiceNetworkPolicies: 'Disabled'
          // networkSecurityGroup: {
          //   id: networkSecurityGroupId
          // }
        }
      }
    ]
  }
}

resource sourceToDestinationPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-04-01' = {
  name: '${virtualNetworkName}-To-${virtualNetworkGeoName}'
  parent: virtualNetwork
  properties: {
    allowForwardedTraffic: true
    allowGatewayTransit: true
    remoteVirtualNetwork: {
      id: virtualNetworkGeo.id
    } 
  }
}

resource destinationToSourcePeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-04-01' = {
  name: '${virtualNetworkGeoName}-To-${virtualNetworkName}'
  parent: virtualNetworkGeo
  properties: {
    allowForwardedTraffic: true
    allowGatewayTransit: true
    remoteVirtualNetwork: {
      id: virtualNetwork.id
    } 
  }
}

output bastionId string = bastionHost.id
output id string = virtualNetwork.id
output name string = virtualNetwork.name
output idgeo string = virtualNetworkGeo.id
