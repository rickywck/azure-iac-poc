@description('Resource location')
param location string

@description('Application Insights name')
param name string

@description('Resource tags')
param tags object = {}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: name
  location: location
  kind: 'web'
  tags: tags
  properties: {
    Application_Type: 'web'
    SamplingPercentage: 100
    DisableIpMasking: false
    IngestionMode: 'ApplicationInsights'
  }
}

output instrumentationKey string = appInsights.properties.InstrumentationKey
output connectionString string = appInsights.properties.ConnectionString
