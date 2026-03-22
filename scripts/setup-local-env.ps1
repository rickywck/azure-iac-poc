# Setup local development environment
# Run: .\scripts\setup-local-env.ps1 -ResourceGroup rg-agentic-poc-dev -PostgresPassword "YourPassword"

param(
    [string]$ResourceGroup = "rg-agentic-poc-dev",
    [string]$Location = "eastus2",
    [string]$PostgresPassword = ""
)

Write-Host "=== Setting up local development environment ===" -ForegroundColor Cyan
Write-Host "Resource Group: $ResourceGroup"
Write-Host ""

# Check if Azure CLI is installed
$azVersion = az version --output json 2>$null | ConvertFrom-Json
if (-not $azVersion) {
    Write-Error "Azure CLI not found. Install from: https://aka.ms/installazurecliwindows"
    exit 1
}

# Get deployment details
Write-Host "Retrieving deployment details..." -ForegroundColor Yellow

$deployment = az deployment group show `
    --resource-group $ResourceGroup `
    --name "main" `
    --query "properties" `
    --output json 2>$null | ConvertFrom-Json

if (-not $deployment) {
    Write-Error "Deployment not found. Run .\scripts\deploy.ps1 first."
    exit 1
}

$outputs = $deployment.outputs
$parameters = $deployment.parameters

$postgresHost = $outputs.postgresHost.value
$foundryEndpoint = $outputs.foundryEndpoint.value
$foundryAccountName = $outputs.foundryAccountName.value
$storageAccountName = $outputs.storageAccountName.value
$appInsightsKey = $outputs.appInsightsInstrumentationKey.value
$foundryModelDeploymentName = $outputs.foundryModelDeploymentName.value
$postgresUser = $parameters.postgresAdminUsername.value
$postgresDb = $parameters.postgresDatabaseName.value

Write-Host "Deployment details retrieved." -ForegroundColor Green
Write-Host ""

# Get PostgreSQL password
if ([string]::IsNullOrWhiteSpace($PostgresPassword)) {
    $securePassword = Read-Host "Enter PostgreSQL admin password" -AsSecureString
    $PostgresPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword))
}

# Get Foundry API key
Write-Host "Retrieving Foundry API key..." -ForegroundColor Yellow
$foundryKey = az cognitiveservices account keys list `
    --resource-group $ResourceGroup `
    --name $foundryAccountName `
    --query "key1" `
    --output tsv

if (-not $foundryKey) {
    Write-Error "Failed to retrieve Foundry API key. Check that the Foundry account exists."
    exit 1
}

Write-Host "Foundry API key retrieved." -ForegroundColor Green

# Get Storage account key
Write-Host "Retrieving Storage account key..." -ForegroundColor Yellow
$storageKey = az storage account keys list `
    --resource-group $ResourceGroup `
    --account-name $storageAccountName `
    --query "[0].value" `
    --output tsv

if (-not $storageKey) {
    Write-Error "Failed to retrieve Storage account key. Check that the Storage account exists."
    exit 1
}

Write-Host "Storage account key retrieved." -ForegroundColor Green
Write-Host ""

# Detect model name from deployment
Write-Host "Detecting Foundry model name..." -ForegroundColor Yellow
$modelDeployment = az cognitiveservices account deployment show `
    --resource-group $ResourceGroup `
    --name $foundryAccountName `
    --deployment-name $foundryModelDeploymentName `
    --query "properties.model.name" `
    --output tsv 2>$null

if (-not $modelDeployment) {
    $modelDeployment = "gpt-4o-mini"  # Fallback
    Write-Host "Could not detect model, using default: $modelDeployment" -ForegroundColor Yellow
} else {
    Write-Host "Detected model: $modelDeployment" -ForegroundColor Green
}

Write-Host ""

# Create .env files
Write-Host "Creating .env files..." -ForegroundColor Yellow

# Backend .env
$backendEnv = @"
# PostgreSQL
POSTGRES_USER=$postgresUser
POSTGRES_PASSWORD=$PostgresPassword
POSTGRES_HOST=$postgresHost
POSTGRES_DB=$postgresDb
POSTGRES_SSLMODE=require

# Local service wiring
AGENT_SERVICE_URL=http://localhost:8001

# Storage
STORAGE_ACCOUNT_NAME=$storageAccountName
STORAGE_ACCOUNT_KEY=$storageKey

# Application Insights
APPLICATIONINSIGHTS_INSTRUMENTATION_KEY=$appInsightsKey
"@

$backendPath = "sample-app/backend/.env"
Set-Content -Path $backendPath -Value $backendEnv
Write-Host "Created $backendPath" -ForegroundColor Green

# Agents .env
$agentsEnv = @"
# Local service wiring
PORT=8001

# Foundry / OpenAI
FOUNDRY_ENDPOINT=$foundryEndpoint
FOUNDRY_API_KEY=$foundryKey
FOUNDRY_MODEL=$foundryModelDeploymentName
OPENAI_API_KEY=$foundryKey

# Optional tracing
LANGCHAIN_API_KEY=$foundryKey
LANGCHAIN_TRACING_V2=true
LANGCHAIN_ENDPOINT=https://api.smith.langchain.com
"@

$agentsPath = "sample-app/agents/.env"
Set-Content -Path $agentsPath -Value $agentsEnv
Write-Host "Created $agentsPath" -ForegroundColor Green

# UI .env (only needs API endpoint)
$uiEnv = @"
# API endpoint for UI to call backend
VITE_API_URL=http://localhost:8000/api
"@

$uiPath = "sample-app/ui/.env"
Set-Content -Path $uiPath -Value $uiEnv
Write-Host "Created $uiPath" -ForegroundColor Green

Write-Host ""
Write-Host "=== Setup Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "Environment variables configured for:" -ForegroundColor Cyan
Write-Host ("  - PostgreSQL: {0}" -f $postgresHost)
Write-Host ("  - Foundry: {0}" -f $foundryEndpoint)
Write-Host ("  - Storage: {0}" -f $storageAccountName)
Write-Host ("  - Foundry Model: {0}" -f $modelDeployment)
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host ""
Write-Host "Backend (in new terminal):" -ForegroundColor Cyan
Write-Host "  cd sample-app/backend"
Write-Host "  python -m venv venv"
Write-Host "  .\venv\Scripts\activate"
Write-Host "  pip install -r requirements.txt"
Write-Host "  python main.py"
Write-Host ""
Write-Host "Agents (in another new terminal):" -ForegroundColor Cyan
Write-Host "  cd sample-app/agents"
Write-Host "  python -m venv venv"
Write-Host "  .\venv\Scripts\activate"
Write-Host "  pip install -r requirements.txt"
Write-Host "  python main.py"
Write-Host ""
Write-Host "UI (in another new terminal):" -ForegroundColor Cyan
Write-Host "  cd sample-app/ui"
Write-Host "  npm install"
Write-Host "  npm run dev"
