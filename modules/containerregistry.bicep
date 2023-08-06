// Create Azure Container Registry with Azure Private Link endpoint
@description('Azure region of the deployment')
param location string

@description('Tags to add to the resources')
param tags object

@minLength(5)
@maxLength(50)
@description('Container registry name')
param containerRegistryName string

@description('Container registry private link endpoint name')
param containerRegistryPleName string

@description('Resource ID of the subnet')
param subnetId string

@description('Resource ID of the virtual network')
param virtualNetworkId string

// must be alphanumeric
var containerRegistryNameCleaned = replace(containerRegistryName, '-', '')

var privateDnsZoneName = 'privatelink${environment().suffixes.acrLoginServer}'

var groupName = 'registry' 

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2022-12-01' = {
  name: containerRegistryNameCleaned
  location: location
  tags: tags
  sku: {
    name: 'Premium'
  }
  properties: {
    adminUserEnabled: true
    dataEndpointEnabled: false
    networkRuleBypassOptions: 'AzureServices'
    networkRuleSet: {
      defaultAction: 'Deny'
    }
    policies: {
      quarantinePolicy: {
        status: 'disabled'
      }
      retentionPolicy: {
        status: 'enabled'
        days: 7
      }
      trustPolicy: {
        status: 'disabled'
        type: 'Notary'
      }
    }
    publicNetworkAccess: 'Disabled'
    zoneRedundancy: 'Disabled'
  }
}

resource containerRegistryPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-04-01' = {
  name: containerRegistryPleName
  location: location
  tags: tags
  properties: {
    privateLinkServiceConnections: [
      {
        name: containerRegistryPleName
        properties: {
          groupIds: [
            groupName
          ]
          privateLinkServiceId: containerRegistry.id
        }
      }
    ]
    subnet: {
      id: subnetId
    }
  }
}

resource containerRegistryPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateDnsZoneName
  location: 'global'
}

resource containerRegistryPrivateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: containerRegistryPrivateDnsZone
  name: '${privateDnsZoneName}-link' // uniqueString(containerRegistry.id)
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetworkId
    }
  }
}

resource privateEndpointDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-04-01' = {
  parent: containerRegistryPrivateEndpoint
  name: '${groupName}-PrivateDnsZoneGroup'
  properties:{
    privateDnsZoneConfigs: [
      {
        name: privateDnsZoneName
        properties:{
          privateDnsZoneId: containerRegistryPrivateDnsZone.id
        }
      }
    ]
  }
}

output containerRegistryId string = containerRegistry.id
