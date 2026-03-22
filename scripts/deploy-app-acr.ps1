# Azure Container Apps Application-Only Deployment Script (ACR Build)
# Run: .\scripts\deploy-app-acr.ps1

param(
    [string]$ResourceGroup = "rg-agentic-poc-dev",
    [string]$Location = "eastus2",
    [string]$TemplateFile = "app-update.bicep",
    [string]$ParametersFile = "config/parameters.dev.json",
    [switch]$UseExternalFoundry,
    [string]$ExternalFoundryEndpoint = '',
    [string]$ExternalFoundryApiKey = ''
)

function Convert-SecureStringToPlainText {
    param([Security.SecureString]$SecureValue)

    if (-not $SecureValue) {
        return ''
    }

    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureValue)
    try {
        return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        if ($bstr -ne [IntPtr]::Zero) {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
}

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

Write-Host "=== Azure App-Only Deployment (ACR Build) ===" -ForegroundColor Cyan
Write-Host "Resource Group: $ResourceGroup"
Write-Host "Location: $Location"
Write-Host "ACR: $acrName"
Write-Host ""

$deployFoundry = $true
$foundryApiKeyPlain = ""
$foundryEndpoint = ""

if ($UseExternalFoundry) {
    $deployFoundry = $false
    $foundryApiKeyPlain = $ExternalFoundryApiKey.Trim()
    $foundryEndpoint = $ExternalFoundryEndpoint.Trim()

    if ([string]::IsNullOrWhiteSpace($foundryApiKeyPlain)) {
        Write-Error "-ExternalFoundryApiKey is required when -UseExternalFoundry is specified."
        exit 1
    }

    if ([string]::IsNullOrWhiteSpace($foundryEndpoint)) {
        Write-Error "-ExternalFoundryEndpoint is required when -UseExternalFoundry is specified."
        exit 1
    }
}

Write-Host ""
Write-Host "=== Phase 1: Building and pushing application images in ACR ===" -ForegroundColor Cyan

# Use a unique timestamped tag so ARM detects a change and forces Container Apps to pull the new image.
# Without this, passing the same ':latest' tag causes ARM to treat the resource as unchanged (idempotent no-op).
$imageTag = Get-Date -Format 'yyyyMMddHHmm'
Write-Host "Image tag: $imageTag" -ForegroundColor DarkGray

$acrBuilds = @(
    @{ Name = "ui";      Context = "./sample-app/ui" },
    @{ Name = "backend"; Context = "./sample-app/backend" },
    @{ Name = "agents";  Context = "./sample-app/agents" }
)

foreach ($img in $acrBuilds) {
    Write-Host "Building $($img.Name):$imageTag in ACR..." -ForegroundColor Yellow
    az acr build -r $acrName -t "$($img.Name):$imageTag" -t "$($img.Name):latest" $img.Context
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ACR build failed for $($img.Name)" -ForegroundColor Red
        exit 1
    }
}

# Override image params with timestamped tags for the Bicep deployment
$uiImage      = "ui:$imageTag"
$backendImage = "backend:$imageTag"
$agentsImage  = "agents:$imageTag"

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
                 postgresPasswordSecretName="postgres-admin-password" `
                 deployFoundry="$deployFoundry" `
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
Write-Host "Key Vault:" -ForegroundColor Cyan
Write-Host "  Name: $($outputs.keyVaultName.value)"
Write-Host "  URL: $($outputs.keyVaultUrl.value)"
Write-Host "  PostgreSQL password secret: $($outputs.postgresCredentialName.value)"
Write-Host ""
Write-Host "Foundry:" -ForegroundColor Cyan
Write-Host "  Account: $($outputs.foundryAccountName.value)"
Write-Host "  Endpoint: $($outputs.foundryEndpoint.value)"
Write-Host "  Model deployment: $($outputs.foundryModelDeploymentName.value)"