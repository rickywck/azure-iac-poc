# Azure Container Apps Application-Only Deployment Script for Windows
# Run: .\scripts\deploy-app.ps1

param(
    [string]$ResourceGroup = "rg-agentic-poc-dev",
    [string]$Location = "eastus2",
    [string]$TemplateFile = "app-update.bicep",
    [string]$ParametersFile = "config/parameters.dev.json",
    [switch]$UseExistingFoundry
)

# Check if Azure CLI is installed
$azVersion = az version --output json 2>$null | ConvertFrom-Json
if (-not $azVersion) {
    Write-Error "Azure CLI not found. Install from: https://aka.ms/installazurecliwindows"
    exit 1
}

if ((az group exists --name $ResourceGroup) -ne "true") {
    Write-Error "Resource group '$ResourceGroup' does not exist. Deploy infrastructure first with .\scripts\deploy.ps1"
    exit 1
}

$parameterData = Get-Content $ParametersFile | ConvertFrom-Json
$resourceNamePrefix = $parameterData.parameters.resourceNamePrefix.value
$postgresAdminUsername = $parameterData.parameters.postgresAdminUsername.value
$postgresDatabaseName = $parameterData.parameters.postgresDatabaseName.value
$storageContainerName = $parameterData.parameters.storageContainerName.value
$uiImage = $parameterData.parameters.uiImage.value
$backendImage = $parameterData.parameters.backendImage.value
$agentsImage = $parameterData.parameters.agentsImage.value
$foundryModel = $parameterData.parameters.foundryModel.value

$acrName = "${resourceNamePrefix}acr"
if ($acrName.Length -gt 50) {
    $acrName = $acrName.Substring(0, 50)
}

$acrLoginServer = az acr show --name $acrName --resource-group $ResourceGroup --query loginServer --output tsv 2>$null
if (-not $acrLoginServer) {
    Write-Error "Could not resolve ACR '$acrName'. Make sure infrastructure is already deployed."
    exit 1
}

Write-Host "=== Azure App-Only Deployment ===" -ForegroundColor Cyan
Write-Host "Resource Group: $ResourceGroup"
Write-Host "Location: $Location"
Write-Host "ACR: $acrName"
Write-Host ""

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

Write-Host ""
Write-Host "=== Phase 1: Building and pushing application images ===" -ForegroundColor Cyan

$dockerAvailable = $null
try {
    $dockerVersion = docker --version 2>$null
    if ($LASTEXITCODE -eq 0 -and $dockerVersion) {
        $dockerAvailable = $true
    }
} catch {
    $dockerAvailable = $false
}

$images = @(
    @{ Tag = "$acrLoginServer/ui:latest";      Context = "./sample-app/ui" },
    @{ Tag = "$acrLoginServer/backend:latest"; Context = "./sample-app/backend" },
    @{ Tag = "$acrLoginServer/agents:latest";  Context = "./sample-app/agents" }
)

if ($dockerAvailable) {
    Write-Host "Logging into ACR: $acrLoginServer" -ForegroundColor Yellow
    az acr login --name $acrName 2>&1 | Out-Null

    if ($LASTEXITCODE -eq 0) {
        foreach ($img in $images) {
            Write-Host "Building $($img.Tag)..." -ForegroundColor Yellow
            docker build -t $img.Tag $img.Context
            if ($LASTEXITCODE -ne 0) { Write-Host "Build failed for $($img.Tag)" -ForegroundColor Red; exit 1 }

            Write-Host "Pushing $($img.Tag)..." -ForegroundColor Yellow
            docker push $img.Tag
            if ($LASTEXITCODE -ne 0) { Write-Host "Push failed for $($img.Tag)" -ForegroundColor Red; exit 1 }
        }
    } else {
        $dockerAvailable = $false
    }
}

if (-not $dockerAvailable) {
    Write-Host "Docker is not available for local build/push. Falling back to az acr build..." -ForegroundColor DarkYellow

    $acrBuilds = @(
        @{ Tag = "ui:latest";      Context = "./sample-app/ui" },
        @{ Tag = "backend:latest"; Context = "./sample-app/backend" },
        @{ Tag = "agents:latest";  Context = "./sample-app/agents" }
    )

    foreach ($img in $acrBuilds) {
        Write-Host "Building $($img.Tag) in ACR..." -ForegroundColor Yellow
        az acr build -r $acrName -t $img.Tag $img.Context
        if ($LASTEXITCODE -ne 0) { Write-Host "ACR build failed for $($img.Tag)" -ForegroundColor Red; exit 1 }
    }
}

Write-Host ""
Write-Host "=== Phase 2: Updating Azure Container Apps ===" -ForegroundColor Cyan

$deployOutput = az deployment group create `
    --resource-group $ResourceGroup `
    --template-file $TemplateFile `
    --parameters location="$Location" `
                 resourceNamePrefix="$resourceNamePrefix" `
                 postgresAdminUsername="$postgresAdminUsername" `
                 postgresDatabaseName="$postgresDatabaseName" `
                 storageContainerName="$storageContainerName" `
                 uiImage="$uiImage" `
                 backendImage="$backendImage" `
                 agentsImage="$agentsImage" `
                 foundryModel="$foundryModel" `
                 deployFoundry="$deployFoundry" `
                 postgresAdminPassword="$postgresPasswordPlain" `
                 foundryApiKey="$foundryApiKeyPlain" `
                 foundryEndpoint="$foundryEndpoint" `
    --output json

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "=== App Deployment Failed ===" -ForegroundColor Red
    exit 1
}

$outputs = ($deployOutput | ConvertFrom-Json).properties.outputs

Write-Host ""
Write-Host "=== App Deployment Successful ===" -ForegroundColor Green
Write-Host ""
Write-Host "Container Registry:" -ForegroundColor Cyan
Write-Host "  Login Server: $($outputs.acrLoginServer.value)"
Write-Host "  Name: $($outputs.acrName.value)"
Write-Host ""
Write-Host "Container Apps:" -ForegroundColor Cyan
Write-Host "  UI+Backend URL: https://$($outputs.uiAppURL.value)"
Write-Host "  Agents internal FQDN: $($outputs.agentsInternalFqdn.value)"
Write-Host "  Note: Agents ingress is internal only and is not browser-accessible." -ForegroundColor DarkGray
Write-Host ""
Write-Host "Foundry:" -ForegroundColor Cyan
Write-Host "  Account: $($outputs.foundryAccountName.value)"
Write-Host "  Endpoint: $($outputs.foundryEndpoint.value)"
Write-Host "  Model deployment: $($outputs.foundryModelDeploymentName.value)"