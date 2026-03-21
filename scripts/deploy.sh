#!/bin/bash
set -e

# Configuration
RESOURCE_GROUP="rg-agentic-poc-dev"
LOCATION="eastus"
TEMPLATE_FILE="main.bicep"
PARAMETERS_FILE="config/parameters.dev.json"

# Prompt for secrets if not set
if [ -z "$POSTGRES_PASSWORD" ]; then
    read -sp "Enter PostgreSQL password: " POSTGRES_PASSWORD
    echo
fi

if [ -z "$FOUNDRY_API_KEY" ]; then
    read -sp "Enter Foundry API key: " FOUNDRY_API_KEY
    echo
fi

if [ -z "$FOUNDRY_ENDPOINT" ]; then
    read -p "Enter Foundry endpoint (e.g., https://<resource>.openai.azure.com/): " FOUNDRY_ENDPOINT
fi

# Create resource group
echo "Creating resource group..."
az group create \
    --name $RESOURCE_GROUP \
    --location $LOCATION

# Deploy infrastructure
echo "Deploying infrastructure..."
az deployment group create \
    --resource-group $RESOURCE_GROUP \
    --template-file $TEMPLATE_FILE \
    --parameters @$PARAMETERS_FILE \
    --parameters postgresAdminPassword="$POSTGRES_PASSWORD" \
                    foundryApiKey="$FOUNDRY_API_KEY" \
                    foundryEndpoint="$FOUNDRY_ENDPOINT"

# Extract outputs
echo "Extracting deployment outputs..."
ACR_NAME=$(az deployment group show --resource-group $RESOURCE_GROUP --name main.bicep --query properties.outputs.acrName.value -o tsv)
ACR_LOGIN_SERVER=$(az deployment group show --resource-group $RESOURCE_GROUP --name main.bicep --query properties.outputs.acrLoginServer.value -o tsv)
UI_APP_URL=$(az deployment group show --resource-group $RESOURCE_GROUP --name main.bicep --query properties.outputs.uiAppURL.value -o tsv)
AGENTS_APP_URL=$(az deployment group show --resource-group $RESOURCE_GROUP --name main.bicep --query properties.outputs.agentsAppURL.value -o tsv)
POSTGRES_HOST=$(az deployment group show --resource-group $RESOURCE_GROUP --name main.bicep --query properties.outputs.postgresHost.value -o tsv)

echo ""
echo "Deployment complete!"
echo "================================"
echo "ACR Login Server: $ACR_LOGIN_SERVER"
echo "ACR Name: $ACR_NAME"
echo "UI App URL: https://$UI_APP_URL"
echo "Agents App URL: https://$AGENTS_APP_URL"
echo "PostgreSQL Host: $POSTGRES_HOST"
echo "================================"
echo ""
echo "Next steps:"
echo "1. Build and push container images:"
echo "   az acr login --name $ACR_NAME"
echo "   docker build -t $ACR_LOGIN_SERVER/ui:latest ./sample-app/ui"
echo "   docker build -t $ACR_LOGIN_SERVER/backend:latest ./sample-app/backend"
echo "   docker build -t $ACR_LOGIN_SERVER/agents:latest ./sample-app/agents"
echo "   docker push $ACR_LOGIN_SERVER/ui:latest"
echo "   docker push $ACR_LOGIN_SERVER/backend:latest"
echo "   docker push $ACR_LOGIN_SERVER/agents:latest"
echo ""
echo "2. Validate deployment: ./scripts/validate.sh"
