// TO DO: ADD PRIVATE ENDPOINT HERE
// Create Application Insights instance as dependency for Azure ML
// https://github.com/Azure-Samples/azure-monitor-private-link-scope
@description('Azure region of the deployment')
param location string

@description('Tags to add to the resources')
param tags object = {}

@description('Log Analytics resource name')
param logAnalyticsWorkspaceName string 

@description('Specify the pricing tier: PerGB2018 or CapacityReservation')
@allowed([
  'CapacityReservation'
  'PerGB2018'
])
param logAnalyticsWorkspaceSku string

// data ingested into workspace based application insights is retained for 90 days without additional charge
@description('Specify the number of days to retain data.')
param retentionInDays int

@description('Application Insights resource name')
param applicationInsightsName string

@description('Azure Monitor Private Link Scope Name')
param logAnalyticsPlsName string

@description('Azure Monitor Private Link Scope Private Link Endpoint Name')
param logAnalyticsPleName string

@description('Resource ID of the subnet')
param subnetId string

@description('Resource ID of the virtual network')
param virtualNetworkId string

// manually set for now
var PrivateDnsZoneName =  {
  monitor: 'privatelink.monitor.azure.com'
  oms: 'privatelink.oms.opinsights.azure.com'
  ods: 'privatelink.ods.opinsights.azure.com'
  agentsvc: 'privatelink.agentsvc.azure.automation-net'
  storage: 'privatelink.blob.${environment().suffixes.storage}'
}

// var monitorPrivateDnsZoneName = 'privatelink.monitor.azure.com'

var groupName = 'azuremonitor' 

// Without inference endpoints, most of logs should come from Azure ML training. If we don't use Azure ML resources, this should be minimal
// TO REMOVE: Ingestion - $2.76/ GB  (1st 5GB free), Retention - $0.12/ GB/ month (after 90 days)
// https://learn.microsoft.com/en-us/azure/azure-monitor/logs/resource-manager-workspace?tabs=bicep
// https://github.com/Azure-Samples/azure-monitor-private-link-scope/blob/main/templates/azuredeploy.json
// TO REVIEW AND REMOVE: Cost for Log Analytics Workspace Application Insights
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  properties:{
    sku: {
      name: logAnalyticsWorkspaceSku
    }
    retentionInDays: retentionInDays
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Disabled'
  }
}

// https://learn.microsoft.com/en-us/azure/azure-monitor/app/resource-manager-app-resource?tabs=bicep
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    // standard
    Flow_Type: 'Bluefield'
  }
}

// Private Link with Log Analytics still in preview...
// https://learn.microsoft.com/en-us/azure/azure-monitor/logs/private-link-configure 
resource logAnalyticsPrivateLinkScopes 'microsoft.insights/privateLinkScopes@2021-07-01-preview' = {
  name: logAnalyticsPlsName
  // The Azure Monitor Private Link Scope type is global and not bound to a location. 
  // However, you must specify a location for the resource group where the metadata associated with the Private Link Scope will reside. 
  // This location will have no impact on the runtime availability of your resource.
  location: 'global' // location
  tags: tags
  properties: {
    accessModeSettings: {
      ingestionAccessMode: 'PrivateOnly'
      queryAccessMode: 'PrivateOnly'
    }
  }
}

// might need one for the log analytics workspace too?
resource applicationInsightsPrivateLinkScopedResources 'Microsoft.Insights/privateLinkScopes/scopedResources@2021-07-01-preview' = {
  parent: logAnalyticsPrivateLinkScopes
  name: 'scoped-applicationInsights'
  properties: {
    linkedResourceId: applicationInsights.id
  }
  dependsOn: [
    logAnalyticsWorkspace
  ]
}

resource logAnalyticsPrivateLinkScopedResources 'Microsoft.Insights/privateLinkScopes/scopedResources@2021-07-01-preview' = {
  parent: logAnalyticsPrivateLinkScopes
  name: 'scoped-logAnalytics'
  properties: {
    linkedResourceId: logAnalyticsWorkspace.id
  }
}

resource logAnalyticsPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-04-01' = {
  name: logAnalyticsPleName
  location: location
  tags: tags
  properties: {
    privateLinkServiceConnections: [
      {
        name: logAnalyticsPleName
        properties: {
          groupIds: [
            groupName
          ]
          privateLinkServiceId: logAnalyticsPrivateLinkScopes.id
        }
      }
    ]
    subnet: {
      id: subnetId
    }
  }
}

// resource logAnalyticsPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
//   name: PrivateDnsZoneName.monitor
//   location: 'global'
// }

// resource logAnalyticsPrivateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
//   parent: logAnalyticsPrivateDnsZone
//   name: '${PrivateDnsZoneName.monitor}-link' // uniqueString(containerRegistry.id)
//   location: 'global'
//   properties: {
//     registrationEnabled: false
//     virtualNetwork: {
//       id: virtualNetworkId
//     }
//   }
// }

resource monitorPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: PrivateDnsZoneName.monitor
  location: 'global'
}

resource omsPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: PrivateDnsZoneName.oms
  location: 'global'
}

resource odsPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: PrivateDnsZoneName.ods
  location: 'global'
}

resource agentsvcPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: PrivateDnsZoneName.agentsvc
  location: 'global'
}

// resource storagePrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
//   name: PrivateDnsZoneName.storage
//   location: 'global'
// }

resource monitorPrivateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: monitorPrivateDnsZone
  name: '${PrivateDnsZoneName.monitor}-link' // uniqueString(containerRegistry.id)
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetworkId
    }
  }
}

resource omsPrivateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: omsPrivateDnsZone
  name: '${PrivateDnsZoneName.oms}-link' // uniqueString(containerRegistry.id)
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetworkId
    }
  }
}

resource odsPrivateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: odsPrivateDnsZone
  name: '${PrivateDnsZoneName.ods}-link' // uniqueString(containerRegistry.id)
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetworkId
    }
  }
}

resource agentsvcPrivateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: agentsvcPrivateDnsZone
  name: '${PrivateDnsZoneName.agentsvc}-link' // uniqueString(containerRegistry.id)
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetworkId
    }
  }
}

// resource storagePrivateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
//   parent: storagePrivateDnsZone
//   name: '${PrivateDnsZoneName.storage}-link' // uniqueString(containerRegistry.id)
//   location: 'global'
//   properties: {
//     registrationEnabled: false
//     virtualNetwork: {
//       id: virtualNetworkId
//     }
//   }
// }

resource privateEndpointDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-04-01' = {
  parent: logAnalyticsPrivateEndpoint
  name: '${groupName}-PrivateDnsZoneGroup'
  properties:{
    privateDnsZoneConfigs: [
      {
        // CHECK HERE! THERE IS A BUNCH OF DNS TO RESOLVE....
        name: 'privatelink-monitor-azure-com'
        properties: {
          privateDnsZoneId: resourceId('Microsoft.Network/privateDnsZones', PrivateDnsZoneName.monitor)
        }
      }
      {
        name: 'privatelink-oms-opinsights-azure-com'
        properties: {
          privateDnsZoneId: resourceId('Microsoft.Network/privateDnsZones', PrivateDnsZoneName.oms)
        }
      }
      {
        name: 'privatelink-ods-opinsights-azure-com'
        properties: {
          privateDnsZoneId: resourceId('Microsoft.Network/privateDnsZones', PrivateDnsZoneName.ods)
        }
      }
      {
        name: 'privatelink-agentsvc-azure-automation-net'
        properties: {
          privateDnsZoneId: resourceId('Microsoft.Network/privateDnsZones', PrivateDnsZoneName.agentsvc)
        }
      }
      {
        name: 'privatelink-blob-core-windows-net'
        properties: {
          privateDnsZoneId: resourceId('Microsoft.Network/privateDnsZones', PrivateDnsZoneName.storage)
        }
      }
    ]
  }
}

output applicationInsightsId string = applicationInsights.id
