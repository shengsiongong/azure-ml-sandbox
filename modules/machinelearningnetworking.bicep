// Creates private endpoints and DNS zones for the azure machine learning workspace
@description('Azure region of the deployment')
param location string

@description('Machine learning workspace private link endpoint name')
param machineLearningPleName string

@description('Resource ID of the virtual network resource')
param virtualNetworkId string

@description('Resource ID of the subnet resource')
param subnetId string

@description('Resource ID of the machine learning workspace')
param machineLearningWorkspaceId string

@description('Tags to add to the resources')
param tags object

var machineLearningPrivateDnsZoneName = 'privatelink.api.azureml.ms'

var notebookPrivateDnsZoneName = 'privatelink.notebooks.azure.net'

// https://blog.blksthl.com/2023/03/22/the-complete-list-of-groupids-for-private-endpoint-privatelink-service-connection/
var groupName = 'amlworkspace'

resource machineLearningPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-04-01' = {
  name: machineLearningPleName
  location: location
  tags: tags
  properties: {
    privateLinkServiceConnections: [
      {
        name: machineLearningPleName
        properties: {
          groupIds: [
            groupName
          ]
          privateLinkServiceId: machineLearningWorkspaceId
        }
      }
    ]
    subnet: {
      id: subnetId
    }
  }
}

resource machineLearningPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: machineLearningPrivateDnsZoneName
  location: 'global'
}

resource machineLearningPrivateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: machineLearningPrivateDnsZone
  name: '${machineLearningPrivateDnsZoneName}-link' // uniqueString(machineLearningWorkspaceId)
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetworkId
    }
  }
}

// Notebook
resource notebookPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: notebookPrivateDnsZoneName
  location: 'global'
}

resource notebookPrivateDnsZoneVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: notebookPrivateDnsZone
  name: '${notebookPrivateDnsZoneName}-link' // uniqueString(machineLearningWorkspaceId)
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetworkId
    }
  }
}

resource privateEndpointDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-04-01' = {
  parent: machineLearningPrivateEndpoint
  name: '${groupName}-PrivateDnsZoneGroup' // 'amlworkspace-PrivateDnsZoneGroup'
  properties:{
    privateDnsZoneConfigs: [
      {
        name: machineLearningPrivateDnsZoneName
        properties:{
          privateDnsZoneId: machineLearningPrivateDnsZone.id
        }
      }
      {
        name: notebookPrivateDnsZoneName
        properties:{
          privateDnsZoneId: notebookPrivateDnsZone.id
        }
      }
    ]
  }
}
