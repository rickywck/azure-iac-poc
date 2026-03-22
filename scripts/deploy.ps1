# Azure IAC Deployment Script for Windows
# Run: .\scripts\deploy.ps1

param(
    [string]$ResourceGroup = "rg-agentic-poc-dev",
    [string]$Location = "eastus2",
    [string]$TemplateFile = "main.bicep",
    [string]$ParametersFile = "config/parameters.dev.json",
    [string]$FoundryModelDeploymentName = "gpt-4mini",
    [string]$FoundryModelName = "gpt-4o-mini",
    [int]$FoundryModelCapacity = 10,
    [string[]]$FoundryModelFallbackNames = @("gpt-4.1-mini"),
    [switch]$UseExistingFoundry
)

# Check if Azure CLI is installed
$azVersion = az version --output json 2>$null | ConvertFrom-Json
if (-not $azVersion) {
    Write-Error "Azure CLI not found. Install from: https://aka.ms/installazurecliwindows"
    exit 1
}

Write-Host "=== Azure IAC Deployment ===" -ForegroundColor Cyan
Write-Host "Resource Group: $ResourceGroup"
Write-Host "Location: $Location"
Write-Host ""

# Prompt for secrets
$postgresPassword = Read-Host "Enter PostgreSQL admin password" -AsSecureString
$postgresPasswordPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($postgresPassword))

$deployFoundry = $true
$foundryApiKeyPlain = ""
$foundryEndpoint = ""

if ($UseExistingFoundry) {
    $deployFoundry = $false
    $foundryApiKey = Read-Host "Enter existing Microsoft Foundry API key" -AsSecureString
    $foundryApiKeyPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($foundryApiKey))
    $foundryEndpoint = Read-Host "Enter existing Microsoft Foundry endpoint (e.g., https://your-resource.openai.azure.com/)"
}

# Create resource group if not exists
$rgExists = az group exists --name $ResourceGroup
if ($rgExists -eq "false") {
    Write-Host "Creating resource group..." -ForegroundColor Yellow
    az group create --name $ResourceGroup --location $Location
} else {
    Write-Host "Resource group already exists." -ForegroundColor Green
}

# Deploy infrastructure
Write-Host ""
Write-Host "Deploying infrastructure..." -ForegroundColor Yellow
Write-Host "(This may take 10-15 minutes)" -ForegroundColor Gray

function Invoke-InfraDeployment {
    param(
        [string]$ModelName,
        [bool]$IncludeContainerApps = $false
    )

    az deployment group create `
        --resource-group $ResourceGroup `
        --template-file $TemplateFile `
        --parameters @$ParametersFile `
        --parameters postgresAdminPassword="$postgresPasswordPlain" `
                      deployFoundry="$deployFoundry" `
                      deployFoundryModel="true" `
                      foundryModel="$FoundryModelDeploymentName" `
                      foundryModelName="$ModelName" `
                      foundryModelSkuCapacity="$FoundryModelCapacity" `
                      foundryApiKey="$foundryApiKeyPlain" `
                      foundryEndpoint="$foundryEndpoint" `
                      deployContainerApps="$IncludeContainerApps" `
        --output json
}

# --- Phase 1: Deploy infrastructure (without container apps) ---
Write-Host ""
Write-Host "=== Phase 1: Deploying infrastructure ===" -ForegroundColor Cyan
Write-Host "(ACR, PostgreSQL, Storage, Monitor, Foundry)" -ForegroundColor Gray

$infraOutput = $null
$successfulModelName = $null

if (-not $UseExistingFoundry) {
    $modelCandidates = @($FoundryModelName) + $FoundryModelFallbackNames
    $modelCandidates = $modelCandidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

    foreach ($candidateModel in $modelCandidates) {
        Write-Host "Trying Foundry model: $candidateModel" -ForegroundColor Yellow
        $infraOutput = Invoke-InfraDeployment -ModelName $candidateModel -IncludeContainerApps $false

        if ($LASTEXITCODE -eq 0) {
            $successfulModelName = $candidateModel
            break
        }

        $errorText = $infraOutput | Out-String
        $isModelError = $errorText -match '"code"\s*:\s*"DeploymentModelNotSupported"' -or
                        $errorText -match '"code"\s*:\s*"ModelNotFound"' -or
                        $errorText -match '"code"\s*:\s*"ModelCapacityExceeded"' -or
                        $errorText -match '"code"\s*:\s*"QuotaExceeded"'

        if (-not $isModelError) {
            Write-Host ""
            Write-Host "=== Infrastructure Deployment Failed ===" -ForegroundColor Red
            Write-Host $errorText
            exit 1
        }

        Write-Host "Model '$candidateModel' not available, trying next fallback..." -ForegroundColor DarkYellow
    }
} else {
    $infraOutput = Invoke-InfraDeployment -ModelName $FoundryModelName -IncludeContainerApps $false
}

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "=== Infrastructure Deployment Failed ===" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=== Phase 1 Complete: Infrastructure deployed ===" -ForegroundColor Green

$infraOutputs = ($infraOutput | ConvertFrom-Json).properties.outputs
$acrLoginServer = $infraOutputs.acrLoginServer.value
$acrName        = $infraOutputs.acrName.value

# --- Phase 2: Build and push container images ---
Write-Host ""
Write-Host "=== Phase 2: Building and pushing container images ===" -ForegroundColor Cyan

# --- Phase 2: Build and push container images ---
Write-Host ""
Write-Host "=== Phase 2: Building and pushing container images ===" -ForegroundColor Cyan

$dockerAvailable = $null
try {
    $dockerVersion = docker --version 2>$null
    if ($LASTEXITCODE -eq 0 -and $dockerVersion) {
        $dockerAvailable = $true
    }
} catch {
    $dockerAvailable = $false
}

if (-not $dockerAvailable) {
    Write-Host "Docker is not running or not installed." -ForegroundColor DarkYellow
    Write-Host ""
    Write-Host "Push images manually using these commands:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "# Option 1: Using Docker (if you have it running)"
    Write-Host "docker build -t $acrLoginServer/ui:latest ./sample-app/ui"
    Write-Host "docker build -t $acrLoginServer/backend:latest ./sample-app/backend"
    Write-Host "docker build -t $acrLoginServer/agents:latest ./sample-app/agents"
    Write-Host "docker push $acrLoginServer/ui:latest"
    Write-Host "docker push $acrLoginServer/backend:latest"
    Write-Host "docker push $acrLoginServer/agents:latest"
    Write-Host ""
    Write-Host "# Option 2: Using Azure CLI (without Docker)"
    Write-Host "az acr build -r $acrName -t ui:latest ./sample-app/ui"
    Write-Host "az acr build -r $acrName -t backend:latest ./sample-app/backend"
    Write-Host "az acr build -r $acrName -t agents:latest ./sample-app/agents"
    Write-Host ""
    Write-Host "After pushing images, re-run:"
    Write-Host ".\scripts\deploy.ps1"
    Write-Host ""
    exit 0
}

Write-Host "Logging into ACR: $acrLoginServer" -ForegroundColor Yellow
az acr login --name $acrName 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "ACR login via Docker failed. Try using az acr build instead:" -ForegroundColor DarkYellow
    Write-Host ""
    Write-Host "az acr build -r $acrName -t ui:latest ./sample-app/ui"
    Write-Host "az acr build -r $acrName -t backend:latest ./sample-app/backend"
    Write-Host "az acr build -r $acrName -t agents:latest ./sample-app/agents"
    Write-Host ""
    exit 0
}

$images = @(
    @{ Tag = "$acrLoginServer/ui:latest";      Context = "./sample-app/ui" },
    @{ Tag = "$acrLoginServer/backend:latest"; Context = "./sample-app/backend" },
    @{ Tag = "$acrLoginServer/agents:latest";  Context = "./sample-app/agents" }
)

foreach ($img in $images) {
    Write-Host "Building $($img.Tag)..." -ForegroundColor Yellow
    docker build -t $img.Tag $img.Context
    if ($LASTEXITCODE -ne 0) { Write-Host "Build failed for $($img.Tag)" -ForegroundColor Red; exit 1 }

    Write-Host "Pushing $($img.Tag)..." -ForegroundColor Yellow
    docker push $img.Tag
    if ($LASTEXITCODE -ne 0) { Write-Host "Push failed for $($img.Tag)" -ForegroundColor Red; exit 1 }
}

Write-Host ""
Write-Host "=== Phase 2 Complete: Images pushed to ACR ===" -ForegroundColor Green

# --- Phase 3: Deploy container apps ---
Write-Host ""
Write-Host "=== Phase 3: Deploying Container Apps ===" -ForegroundColor Cyan

$deployOutput = Invoke-InfraDeployment -ModelName $successfulModelName -IncludeContainerApps $true

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "=== Deployment Successful ===" -ForegroundColor Green
    Write-Host ""

    # Extract and display outputs
    $outputs = ($deployOutput | ConvertFrom-Json).properties.outputs

    Write-Host "Container Registry:" -ForegroundColor Cyan
    Write-Host "  Login Server: $($outputs.acrLoginServer.value)"
    Write-Host "  Name: $($outputs.acrName.value)"
    Write-Host ""

    Write-Host "Container Apps:" -ForegroundColor Cyan
    Write-Host "  UI+Backend URL: https://$($outputs.uiAppURL.value)"
    Write-Host "  Agents internal FQDN: $($outputs.agentsInternalFqdn.value)"
    Write-Host "  Note: Agents ingress is internal only and is not browser-accessible." -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "PostgreSQL:" -ForegroundColor Cyan
    Write-Host "  Hostname: $($outputs.postgresHost.value)"
    Write-Host ""

    Write-Host "Storage Account:" -ForegroundColor Cyan
    Write-Host "  Name: $($outputs.storageAccountName.value)"
    Write-Host ""

    Write-Host "Application Insights:" -ForegroundColor Cyan
    Write-Host "  Instrumentation Key: $($outputs.appInsightsInstrumentationKey.value)"
    Write-Host ""

    Write-Host "Foundry:" -ForegroundColor Cyan
    Write-Host "  Account: $($outputs.foundryAccountName.value)"
    Write-Host "  Endpoint: $($outputs.foundryEndpoint.value)"
    Write-Host "  Model deployment: $($outputs.foundryModelDeploymentName.value)"
    if ($successfulModelName) {
        Write-Host "  Model name: $successfulModelName"
    }
    Write-Host ""

} else {
    Write-Host ""
    Write-Host "=== Container Apps Deployment Failed ===" -ForegroundColor Red
    exit 1
}
