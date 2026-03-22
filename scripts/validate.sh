#!/bin/bash
set -e

RESOURCE_GROUP="rg-agentic-poc-dev"

echo "Validating Azure IAC deployment..."
echo ""

# Check resource group exists
echo "Checking resource group..."
az group show --name $RESOURCE_GROUP --output table 2>/dev/null || {
    echo "ERROR: Resource group $RESOURCE_GROUP not found"
    exit 1
}

# Get deployment outputs
ACR_NAME=$(az deployment group show --resource-group $RESOURCE_GROUP --name main.bicep --query properties.outputs.acrName.value -o tsv 2>/dev/null)
UI_APP_URL=$(az deployment group show --resource-group $RESOURCE_GROUP --name main.bicep --query properties.outputs.uiAppURL.value -o tsv 2>/dev/null)
AGENTS_INTERNAL_FQDN=$(az deployment group show --resource-group $RESOURCE_GROUP --name main.bicep --query properties.outputs.agentsInternalFqdn.value -o tsv 2>/dev/null)

if [ -z "$ACR_NAME" ]; then
    echo "ERROR: Deployment outputs not found. Run ./scripts/deploy.sh first."
    exit 1
fi

# Validate ACR
echo "✓ ACR: $ACR_NAME"

# Validate Container Apps Environment
ENV_NAME=$(az containerapp env show --name ${ACR_NAME%acr}-env --resource-group $RESOURCE_GROUP --query name -o tsv 2>/dev/null) && echo "✓ Container Apps Environment: $ENV_NAME" || echo "✗ Container Apps Environment not found"

# Validate UI Container App
UI_APP_NAME=$(az containerapp show --name ${ACR_NAME%acr}-ui --resource-group $RESOURCE_GROUP --query name -o tsv 2>/dev/null) && echo "✓ UI Container App: $UI_APP_NAME (https://$UI_APP_URL)" || echo "✗ UI Container App not found"

# Validate Agents Container App
AGENTS_APP_NAME=$(az containerapp show --name ${ACR_NAME%acr}-agents --resource-group $RESOURCE_GROUP --query name -o tsv 2>/dev/null) && echo "✓ Agents Container App: $AGENTS_APP_NAME (internal FQDN: $AGENTS_INTERNAL_FQDN)" || echo "✗ Agents Container App not found"

# Validate PostgreSQL
POSTGRES_SERVER=$(az postgres flexible-server show --name ${ACR_NAME%acr}-psql --resource-group $RESOURCE_GROUP --query name -o tsv 2>/dev/null) && echo "✓ PostgreSQL Server: $POSTGRES_SERVER" || echo "✗ PostgreSQL Server not found"

# Validate Storage Account
STORAGE_ACCOUNT=$(az storage account show --name ${ACR_NAME%acr}storage --resource-group $RESOURCE_GROUP --query name -o tsv 2>/dev/null) && echo "✓ Storage Account: $STORAGE_ACCOUNT" || echo "✗ Storage Account not found"

# Validate Application Insights
APP_INSIGHTS=$(az monitor app-insights show --name ${ACR_NAME%acr}ai --resource-group $RESOURCE_GROUP --query name -o tsv 2>/dev/null) && echo "✓ Application Insights: $APP_INSIGHTS" || echo "✗ Application Insights not found"

# Test endpoints
echo ""
echo "Testing endpoints..."

if [ -n "$UI_APP_URL" ]; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" https://$UI_APP_URL || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "404" ]; then
        echo "✓ UI App is responding (HTTP $HTTP_CODE)"
    else
        echo "⚠ UI App returned HTTP $HTTP_CODE"
    fi
fi

if [ -n "$AGENTS_INTERNAL_FQDN" ]; then
    echo "ℹ Agents app uses internal ingress only; skipping public HTTP check"
fi

echo ""
echo "Validation complete!"
