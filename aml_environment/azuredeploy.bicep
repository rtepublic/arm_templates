@minLength(4)
@maxLength(15)
@description('The string all resources will be prefixed with.')
param resourcePrefix string = resourceGroup().name

// Variables
var location = resourceGroup().location
var name = resourcePrefix
var userPrincipalId = az.deployer().objectId

// VNET and subnet configuration
var vnetAddressPrefix = '10.0.0.0/16'
var privateEndpointSubnetPrefix = '10.0.1.0/24'
var computeSubnetPrefix = '10.0.2.0/24'

// Create VNET with default outbound connections set to false
resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: '${name}vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    enableDdosProtection: false
    subnets: [
      {
        name: 'private-endpoints-subnet'
        properties: {
          addressPrefix: privateEndpointSubnetPrefix
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Disabled'
          defaultOutboundAccess: false
        }
      }
      {
        name: 'compute-subnet'
        properties: {
          addressPrefix: computeSubnetPrefix
          defaultOutboundAccess: false
        }
      }
    ]
  }
}

// Reference to the private endpoints subnet
resource privateEndpointSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-07-01' existing = {
  parent: vnet
  name: 'private-endpoints-subnet'
}

resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2025-01-31-preview' = {
  name: '${name}id'
  location: location
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2025-01-01' = {
  name: toLower('${name}sa')
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    encryption: {
      services: {
        blob: {
          enabled: true
        }
        file: {
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
    supportsHttpsTrafficOnly: true
    allowSharedKeyAccess: false
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2024-04-01-preview' = {
  name: '${name}kv'
  location: location
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableSoftDelete: false
    enableRbacAuthorization: true
    accessPolicies: []
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
  }
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${name}law'
  location: location
  properties: {}
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${name}ai'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
  }
}

resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: '${name}acr'
  location: location
  sku: {
    name: 'Premium'
  }
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: 'Disabled'
    networkRuleBypassOptions: 'AzureServices'
  }
}

// API 2024-07-01-preview is required for the systemDatastoresAuthMode property. 
// The latest API version "2024-10-01" doesn't seem to support it.
// The 2024-10-01 API also doesn't seem to precreate datastores the way that 2024-07-01-preview does.

resource mlWorkspace 'Microsoft.MachineLearningServices/workspaces@2024-07-01-preview' = {
  name: '${name}ws'
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentity.id}': {}
    }
  }
  properties: {
    description: '${name} ML Workspace'
    friendlyName: '${name}ws'
    keyVault: keyVault.id
    storageAccount: storageAccount.id
    containerRegistry: acr.id
    applicationInsights: applicationInsights.id
    primaryUserAssignedIdentity: userAssignedIdentity.id
    systemDatastoresAuthMode: 'Identity'
    publicNetworkAccess: 'Disabled'
  }
}

// -------------------
// Private DNS Zones
// -------------------

resource keyVaultPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.vaultcore.azure.net'
  location: 'global'
}

resource acrPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.azurecr.io'
  location: 'global'
}

resource amlPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.api.azureml.ms'
  location: 'global'
}

resource amlNotebooksPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.notebooks.azure.net'
  location: 'global'
}

resource storagePrivateDnsZoneBlob 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.blob.${environment().suffixes.storage}'
  location: 'global'
}

resource storagePrivateDnsZoneFile 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.file.${environment().suffixes.storage}'
  location: 'global'
}

// -------------------
// Private DNS Zone Virtual Network Links
// -------------------

resource keyVaultPrivateDnsZoneVnetLink 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: '${name}kv-vnet-link'
  location: 'global'
  properties: {}
}

resource keyVaultToVirtualNetwork 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: keyVaultPrivateDnsZone
  name: 'link_to_${toLower(vnet.name)}'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource acrPrivateDnsZoneVnetLink 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: '${name}acr-vnet-link'
  location: 'global'
  properties: {}
}

resource acrToVirtualNetwork 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: acrPrivateDnsZoneVnetLink
  name: 'link_to_${toLower(vnet.name)}'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource amlPrivateDnsZoneVnetLink 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: '${name}aml-vnet-link'
  location: 'global'
  properties: {}
}

resource amlToVirtualNetwork 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: amlPrivateDnsZoneVnetLink
  name: 'link_to_${toLower(vnet.name)}'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}


resource amlNotebooksPrivateDnsZoneVnetLink 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: '${name}aml-notebooks-vnet-link'
  location: 'global'
  properties: {}
}

resource amlNotebooksToVirtualNetwork 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: amlNotebooksPrivateDnsZoneVnetLink
  name: 'link_to_${toLower(vnet.name)}'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource storagePrivateDnsZoneBlobVnetLink 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: '${name}storage-blob-vnet-link'
  location: 'global'
  properties: {}
}

resource blobStorageToVirtualNetwork 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: storagePrivateDnsZoneBlobVnetLink
  name: 'link_to_${toLower(vnet.name)}'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource storagePrivateDnsZoneFileVnetLink 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: '${name}storage-file-vnet-link'
  location: 'global'
  properties: {}
}

resource fileStorageToVirtualNetwork 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: storagePrivateDnsZoneFileVnetLink
  name: 'link_to_${toLower(vnet.name)}'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

// -------------------
// Private Endpoints
// -------------------

resource keyVaultPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-07-01' = {
  name: '${name}kv-pe'
  location: location
  properties: {
    subnet: {
      id: privateEndpointSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: '${name}kv-pe-connection'
        properties: {
          privateLinkServiceId: keyVault.id
          groupIds: [
            'vault'
          ]
        }
      }
    ]
  }
}

resource acrPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-07-01' = {
  name: '${name}acr-pe'
  location: location
  properties: {
    subnet: {
      id: privateEndpointSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: '${name}acr-pe-connection'
        properties: {
          privateLinkServiceId: acr.id
          groupIds: [
            'registry'
          ]
        }
      }
    ]
  }
}

resource amlPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-07-01' = {
  name: '${name}aml-pe'
  location: location
  dependsOn: [
    mlWorkspace
    roleWorkspaceContributorUAMI
    roleAzureMLComputeOperatorUAMI
    roleAzureMLDataScientistUAMI
  ]
  properties: {
    subnet: {
      id: privateEndpointSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: '${name}aml-pe-connection'
        properties: {
          privateLinkServiceId: mlWorkspace.id
          groupIds: [
            'amlworkspace'
          ]
        }
      }
    ]
  }
}

resource storagePrivateEndpointBlob 'Microsoft.Network/privateEndpoints@2024-07-01' = {
  name: '${name}storage-blob-pe'
  location: location
  properties: {
    subnet: {
      id: privateEndpointSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: '${name}storage-blob-pe-connection'
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: [
            'blob'
          ]
        }
      }
    ]
  }
}

resource storagePrivateEndpointFile 'Microsoft.Network/privateEndpoints@2024-07-01' = {
  name: '${name}storage-file-pe'
  location: location
  properties: {
    subnet: {
      id: privateEndpointSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: '${name}storage-file-pe-connection'
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: [
            'file'
          ]
        }
      }
    ]
  }
}

// -------------------
// Private DNS Zone Groups
// -------------------

resource keyVaultPrivateEndpointDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-07-01' = {
  parent: keyVaultPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-vaultcore-azure-net'
        properties: {
          privateDnsZoneId: keyVaultPrivateDnsZone.id
        }
      }
    ]
  }
}

resource acrPrivateEndpointDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-07-01' = {
  parent: acrPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-azurecr-io'
        properties: {
          privateDnsZoneId: acrPrivateDnsZone.id
        }
      }
    ]
  }
}

resource amlPrivateEndpointDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-07-01' = {
  parent: amlPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-api-azureml-ms'
        properties: {
          privateDnsZoneId: amlPrivateDnsZone.id
        }
      }
      {
        name: 'privatelink-notebooks-azure-net'
        properties: {
          privateDnsZoneId: amlNotebooksPrivateDnsZone.id
        }
      }
    ]
  }
}

resource storagePrivateEndpointBlobDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-07-01' = {
  parent: storagePrivateEndpointBlob
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-blob-core-windows-net'
        properties: {
          privateDnsZoneId: storagePrivateDnsZoneBlob.id
        }
      }
    ]
  }
}

resource storagePrivateEndpointFileDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-07-01' = {
  parent: storagePrivateEndpointFile
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-file-core-windows-net'
        properties: {
          privateDnsZoneId: storagePrivateDnsZoneFile.id
        }
      }
    ]
  }
}

// -------------------
// Managed Identity Operator role assignments
// ------------------

// Workspace role assignments for the user-assigned identity

resource roleWorkspaceContributorUAMI 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: mlWorkspace
  name: guid(mlWorkspace.id, 'Contributor - UAMI')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource roleAzureMLComputeOperatorUAMI 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: mlWorkspace
  name: guid(mlWorkspace.id, 'AzureML Compute Operator - UAMI')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'e503ece1-11d0-4e8e-8e2c-7a6c3bf38815')
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource roleAzureMLDataScientistUAMI 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: mlWorkspace
  name: guid(mlWorkspace.id, 'AzureML Data Scientist - UAMI')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'f6c7c914-8db3-469d-8ca1-694a8f32e121')
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Key Vault role assignments for the user-assigned identity

resource roleKeyVaultAdminUAMI 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(keyVault.id, 'Key Vault Administrator - UAMI')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '00482a5a-887f-4fb3-b363-3b7fe8e74483')
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource roleKeyVaultContributorUAMI 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(keyVault.id, 'Key Vault Contributor - UAMI')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'f25e0fa2-a7c8-4377-a976-54943a77a395')
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// ACR role assignments for the user-assigned identity

resource roleAcrPullUAMI 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: acr
  name: guid(acr.id, 'ACR Pull - UAMI')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource roleAcrPushUAMI 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: acr
  name: guid(acr.id, 'ACR Push - UAMI')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8311e382-0749-4cb8-b61a-304f252e45ec')
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource roleAcrRepositoryContributorUAMI 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: acr
  name: guid(acr.id, 'ACR Repository Contributor - UAMI')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '2efddaa5-3f1f-4df3-97df-af3f13818f4c')
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// App Insights role assignments for the user-assigned identity

resource roleAppInsightsContributorUAMI 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: applicationInsights
  name: guid(applicationInsights.id, 'App Insights Contributor - UAMI')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ae349356-3a1b-4a5e-921d-050484c6347e')
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Storage Account role assignments for the user-assigned identity

resource roleStorageContributorUAMI 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, 'Storage Account Contributor - UAMI')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '17d1049b-9a84-46fb-8f53-869881c3d3ab')
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource roleStorageBlobDataContributorUAMI 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, 'Storage Blob Data Contributor - UAMI')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource roleLogAnalyticsContributorUAMI 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: logAnalyticsWorkspace
  name: guid(logAnalyticsWorkspace.id, 'Log Analytics Contributor - UAMI')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '92aaf0da-9dab-42b6-94a3-d43ce8d16293')
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// -------------------
// User role assignments
// ------------------

resource roleWorkspaceContributorScalt 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: mlWorkspace
  name: guid(mlWorkspace.id, 'Contributor - Sc-alt')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
    principalId: userPrincipalId
    principalType: 'User'
  }
}

resource roleAzureMLComputeOperatorScalt 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: mlWorkspace
  name: guid(mlWorkspace.id, 'AzureML Compute Operator - Sc-alt')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'e503ece1-11d0-4e8e-8e2c-7a6c3bf38815')
    principalId: userPrincipalId
    principalType: 'User'
  }
}

resource roleAzureMLDataScientistScalt 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: mlWorkspace
  name: guid(mlWorkspace.id, 'AzureML Data Scientist - Sc-alt')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'f6c7c914-8db3-469d-8ca1-694a8f32e121')
    principalId: userPrincipalId
    principalType: 'User'
  }
}

// Key Vault role assignments for the user-assigned identity

resource roleKeyVaultAdminScalt 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(keyVault.id, 'Key Vault Administrator - Sc-alt')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '00482a5a-887f-4fb3-b363-3b7fe8e74483')
    principalId: userPrincipalId
    principalType: 'User'
  }
}

resource roleKeyVaultContributorScalt 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(keyVault.id, 'Key Vault Contributor - Sc-alt')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'f25e0fa2-a7c8-4377-a976-54943a77a395')
    principalId: userPrincipalId
    principalType: 'User'
  }
}

// ACR role assignments for the user-assigned identity

resource roleAcrPullScalt 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: acr
  name: guid(acr.id, 'ACR Pull - Sc-alt')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
    principalId: userPrincipalId
    principalType: 'User'
  }
}

resource roleAcrPushScalt 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: acr
  name: guid(acr.id, 'ACR Push - Sc-alt')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8311e382-0749-4cb8-b61a-304f252e45ec')
    principalId: userPrincipalId
    principalType: 'User'
  }
}

resource roleAcrRepositoryContributorScalt 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: acr
  name: guid(acr.id, 'ACR Repository Contributor - Sc-alt')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '2efddaa5-3f1f-4df3-97df-af3f13818f4c')
    principalId: userPrincipalId
    principalType: 'User'
  }
}

// App Insights role assignments for the user-assigned identity

resource roleAppInsightsContributorScalt 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: applicationInsights
  name: guid(applicationInsights.id, 'App Insights Contributor - Sc-alt')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ae349356-3a1b-4a5e-921d-050484c6347e')
    principalId: userPrincipalId
    principalType: 'User'
  }
}

// Storage Account role assignments for the user

resource roleStorageContributorScalt 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, 'Storage Account Contributor - Sc-alt')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '17d1049b-9a84-46fb-8f53-869881c3d3ab')
    principalId: userPrincipalId
    principalType: 'User'
  }
}

resource roleStorageBlobDataContributorScalt 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, 'Storage Blob Data Contributor - Sc-alt')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: userPrincipalId
    principalType: 'User'
  }
}

resource roleLogAnalyticsContributorScalt 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: logAnalyticsWorkspace
  name: guid(logAnalyticsWorkspace.id, 'Log Analytics Contributor - Sc-alt')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '92aaf0da-9dab-42b6-94a3-d43ce8d16293')
    principalId: userPrincipalId
    principalType: 'User'
  }
}

