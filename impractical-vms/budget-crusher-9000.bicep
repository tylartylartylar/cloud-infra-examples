param vmNamePrefix string = 'budgetcrusher9000'
param adminUsername string = 'azureuser'
@secure()
param adminPassword string
param location string = resourceGroup().location

// VNet & Subnet
resource vnet 'Microsoft.Network/virtualNetworks@2022-05-01' = {
  name: '${vmNamePrefix}-vnet'
  location: location
  properties: {
    addressSpace: { addressPrefixes: ['10.0.0.0/16'] }
    subnets: [
      { name: 'default'; properties: { addressPrefix: '10.0.0.0/24' } }
    ]
  }
}

// NAT Gateway for max egress
resource natGateway 'Microsoft.Network/natGateways@2022-05-01' = {
  name: '${vmNamePrefix}-nat'
  location: location
  sku: { name: 'Standard' }
  properties: {
    publicIpAddresses: [
      {
        id: resourceId('Microsoft.Network/publicIPAddresses', '${vmNamePrefix}-pip1')
      }
    ]
  }
}

// Premium Public IPs
resource pip1 'Microsoft.Network/publicIPAddresses@2022-05-01' = {
  name: '${vmNamePrefix}-pip1'
  location: location
  sku: { name: 'Standard' }
  properties: { publicIPAllocationMethod: 'Static' }
}

// Bastion Host
resource bastion 'Microsoft.Network/bastionHosts@2022-05-01' = {
  name: '${vmNamePrefix}-bastion'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'bastionIP'
        properties: {
          subnet: {
            id: '${vnet.id}/subnets/AzureBastionSubnet'
          }
          publicIPAddress: {
            id: pip1.id
          }
        }
      }
    ]
  }
}

// Dedicated Host
resource hostGroup 'Microsoft.Compute/hostGroups@2022-11-01' = {
  name: '${vmNamePrefix}-hostgroup'
  location: location
  properties: {
    platformFaultDomainCount: 2
  }
}

resource dedicatedHost 'Microsoft.Compute/hostGroups/hosts@2022-11-01' = {
  name: '${hostGroup.name}/${vmNamePrefix}-host'
  location: location
  properties: {
    sku: { name: 'DSv3-Type1' }
    platformFaultDomain: 0
  }
}

// Monster VM on Dedicated Host, with 4x Ultra Disks
resource vm 'Microsoft.Compute/virtualMachines@2022-11-01' = {
  name: '${vmNamePrefix}-vm'
  location: location
  zones: ['1']
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_M832i-96mv2'
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftSQLServer'
        offer: 'SQL2019-WS2019'
        sku: 'Enterprise'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'UltraSSD_LRS'
        }
        diskSizeGB: 4096
      }
      dataDisks: [
        for i in range(0, 3): {
          lun: i
          createOption: 'Empty'
          diskSizeGB: 65536
          managedDisk: {
            storageAccountType: 'UltraSSD_LRS'
          }
        }
      ]
    }
    osProfile: {
      computerName: '${vmNamePrefix}-vm'
      adminUsername: adminUsername
      adminPassword: adminPassword
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: pip1.id
        }
      ]
    }
    host: {
      id: dedicatedHost.id
    }
  }
}

// Load Balancer
resource lb 'Microsoft.Network/loadBalancers@2022-05-01' = {
  name: '${vmNamePrefix}-lb'
  location: location
  sku: { name: 'Standard' }
  properties: {
    frontendIPConfigurations: [
      {
        name: 'LoadBalancerFrontEnd'
        properties: {
          publicIPAddress: {
            id: pip1.id
          }
        }
      }
    ]
  }
}
