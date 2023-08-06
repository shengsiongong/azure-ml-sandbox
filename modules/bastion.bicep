// Create Azure Bastion Subnet and host in specified Virtual Network
// https://learn.microsoft.com/en-us/azure/virtual-network/quick-create-bicep?tabs=azure-cli
@description('The Azure region where the Bastion should be deployed')
param location string

@description('Virtual network name')
param vnetName string

@description('The address prefix to use for the Bastion subnet. This must be within VNet IP address space')
param bastionSubnetPrefix string

@description('The name of the Bastion host')
param bastionHostName string = 'bastion-jumpbox'

@description('The name of the Bastion public IP address')
var publicIpAddressName = '${bastionHostName}-pip'
// The Bastion Subnet is required to be named 'AzureBastionSubnet'
var subnetName = 'AzureBastionSubnet'

// required config for Bastion
// https://learn.microsoft.com/en-us/azure/bastion/configuration-settings
// TO REMOVE: USD $4.38/ month
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

resource bastionSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-04-01' = {
  name: '${vnetName}/${subnetName}'
  properties: {
    addressPrefix: bastionSubnetPrefix
    privateEndpointNetworkPolicies: 'Disabled'
    privateLinkServiceNetworkPolicies: 'Disabled'
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
            id: bastionSubnet.id
          }
          publicIPAddress: {
            id: publicIpAddressForBastion.id
          }
        }
      }
    ]
  }
}

output bastionId string = bastionHost.id
