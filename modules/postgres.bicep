@description('Resource location')
param location string

@description('PostgreSQL server name')
param serverName string

@description('Admin username')
param adminUsername string

@description('Admin password (secure)')
@secure()
param adminPassword string

@description('Database name')
param databaseName string

@description('SKU tier')
param sku string

@description('PostgreSQL version')
param version string

@description('Resource tags')
param tags object = {}

@description('Allow Azure services to access PostgreSQL')
param allowAzureServices bool = true

// PostgreSQL Flexible Server with public access (POC - simplified networking)
resource postgresServer 'Microsoft.DBforPostgreSQL/flexibleServers@2023-12-01-preview' = {
  name: serverName
  location: location
  sku: {
    name: sku
    tier: 'Burstable'
  }
  properties: {
    version: version
    administratorLogin: adminUsername
    administratorLoginPassword: adminPassword
    storage: {
      storageSizeGB: 32
    }
    network: {
      publicNetworkAccess: 'Enabled'
    }
    highAvailability: {
      mode: 'Disabled'
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
  }
  tags: tags
}

// Firewall rule to allow Azure services
resource firewallRule 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2023-12-01-preview' = if (allowAzureServices) {
  name: '${serverName}/AllowAllAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

resource database 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2023-12-01-preview' = {
  name: '${serverName}/${databaseName}'
  properties: {
    charset: 'UTF8'
    collation: 'en_US.UTF8'
  }
}

output host string = postgresServer.properties.fullyQualifiedDomainName
output serverId string = postgresServer.id
