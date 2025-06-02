@minLength(4)
@maxLength(15)
@description('The string all resources will be prefixed with.')
param resourcePrefix string = resourceGroup().name

// Variables
var location = resourceGroup().location
var name = resourcePrefix
var userPrincipalId = az.deployer().objectId

resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-07-31-preview' = {
  name: '${name}id'
  location: location
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
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
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
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

