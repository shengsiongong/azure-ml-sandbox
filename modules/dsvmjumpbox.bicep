// Create Data Science Virtual Machine jumpbox
// https://learn.microsoft.com/en-us/azure/virtual-network/quick-create-bicep?tabs=azure-cli
// currently only 1 VM, so no need for availability set and load balancer --> should use loops and conditionals to make this more flexible
// but since usage will be just by DSD, no need to scale in near future
@description('Azure region of the deployment')
param location string

@description('Resource ID of the subnet')
param subnetId string

@description('Network Security Group Resource ID')
param networkSecurityGroupId string

@description('Virtual machine name')
param virtualMachineName string

@description('Virtual machine size')
param vmSizeParameter string

@maxLength(20)
@description('Virtual machine admin username')
param adminUsername string

@secure()
@minLength(8)
@description('Virtual machine admin password')
param adminPassword string

var aadLoginExtensionName = 'AADLoginForWindows'

resource networkInterface 'Microsoft.Network/networkInterfaces@2023-04-01' = {
  name: '${virtualMachineName}-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: subnetId
          }
        }
      }
    ]
    networkSecurityGroup: {
      id: networkSecurityGroupId
    }
  }
}

resource virtualMachine 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: virtualMachineName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSizeParameter
    }
    storageProfile: {
      imageReference: {
        publisher: 'microsoft-dsvm'
        offer: 'dsvm-win-2019'
        sku: 'server-2019'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        // check on managed disk capacity and pricing
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: networkInterface.id
        }
      ]
    }
    osProfile: {
      computerName: virtualMachineName
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        enableAutomaticUpdates: true
        provisionVMAgent: true
        patchSettings: {
          enableHotpatching: false
          patchMode: 'AutomaticByOS'
        }
      }
    }
    diagnosticsProfile: {
      // since storageURI is not specified, boot diagnostics will go to managed storage account
      // https://learn.microsoft.com/en-us/azure/virtual-machines/boot-diagnostics
      // $0.05 GB per month
      bootDiagnostics: {
        enabled: true
      }
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
}

resource virtualMachineName_aadLoginExtensionName 'Microsoft.Compute/virtualMachines/extensions@2023-03-01' = {
  parent: virtualMachine
  name: aadLoginExtensionName
  location: location
  properties: {
    publisher: 'Microsoft.Azure.ActiveDirectory'
    type: aadLoginExtensionName
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
  }
}

output dsvmId string = virtualMachine.id
