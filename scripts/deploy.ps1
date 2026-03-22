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
    [switch]$UseExternalFoundry,
    [string]$ExternalFoundryEndpoint = '',
    [string]$ExternalFoundryApiKey = '',
    [switch]$PurgeDeletedFoundryAccount
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

function New-GeneratedPassword {
    param([int]$Length = 32)

    $alphabet = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()-_=+'
    $bytes = New-Object byte[] $Length
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($bytes)
    $chars = for ($i = 0; $i -lt $Length; $i++) { $alphabet[$bytes[$i] % $alphabet.Length] }
    return -join $chars
}

function Get-CurrentPrincipalObjectId {
    $account = az account show --output json 2>$null | ConvertFrom-Json
    if (-not $account) {
        return ''
    }

    if ($account.user.type -eq 'user') {
        return az ad signed-in-user show --query id --output tsv 2>$null
    }

    if ($account.user.type -eq 'servicePrincipal') {
        return az ad sp show --id $account.user.name --query id --output tsv 2>$null
    }

    return ''
}

function Get-CurrentPrincipalType {
    $account = az account show --output json 2>$null | ConvertFrom-Json
    if (-not $account) {
        return ''
    }

    if ($account.user.type -eq 'user') {
        return 'User'
    }

    if ($account.user.type -eq 'servicePrincipal') {
        return 'ServicePrincipal'
    }

    return ''
}

function Get-KeyVaultSecretValue {
    param(
        [string]$VaultName,
        [string]$SecretName
    )

    return az keyvault secret show --vault-name $VaultName --name $SecretName --query value --output tsv 2>$null
}

function Test-KeyVaultExists {
    param([string]$VaultName)

    $existingName = az keyvault show --name $VaultName --resource-group $ResourceGroup --query name --output tsv 2>$null
    return -not [string]::IsNullOrWhiteSpace($existingName)
}

function Get-KeyVaultId {
    param([string]$VaultName)

    return az keyvault show --name $VaultName --resource-group $ResourceGroup --query id --output tsv 2>$null
}

function Grant-KeyVaultSecretReadAccess {
    param(
        [string]$VaultName,
        [string]$PrincipalObjectId,
        [string]$PrincipalType
    )

    if ([string]::IsNullOrWhiteSpace($PrincipalObjectId) -or [string]::IsNullOrWhiteSpace($PrincipalType)) {
        return $false
    }

    $keyVaultId = Get-KeyVaultId -VaultName $VaultName
    if ([string]::IsNullOrWhiteSpace($keyVaultId)) {
        return $false
    }

    $existingAssignment = az role assignment list --scope $keyVaultId --assignee-object-id $PrincipalObjectId --query "[?roleDefinitionId=='/subscriptions/$((az account show --query id -o tsv 2>$null))/providers/Microsoft.Authorization/roleDefinitions/4633458b-17de-408a-b874-0445c86b69e6'] | [0].id" --output tsv 2>$null
    if (-not [string]::IsNullOrWhiteSpace($existingAssignment)) {
        return $true
    }

    az role assignment create --role 4633458b-17de-408a-b874-0445c86b69e6 --assignee-object-id $PrincipalObjectId --assignee-principal-type $PrincipalType --scope $keyVaultId --output none 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Test-DeletedFoundryAccount {
    param(
        [string]$AccountName,
        [string]$AccountLocation
    )

    $deletedAccount = az cognitiveservices account list-deleted --query "[?name=='$AccountName' && location=='$AccountLocation'] | [0].name" --output tsv 2>$null
    return -not [string]::IsNullOrWhiteSpace($deletedAccount)
}

function Remove-DeletedFoundryAccount {
    param(
        [string]$AccountName,
        [string]$AccountLocation
    )

    az cognitiveservices account purge --name $AccountName --location $AccountLocation --resource-group $ResourceGroup --output none
    return ($LASTEXITCODE -eq 0)
}

function New-DeploymentOverrideFile {
    param(
        [hashtable]$ParameterValues
    )

    $overrideParameters = @{}
    foreach ($key in $ParameterValues.Keys) {
        $overrideParameters[$key] = @{ value = $ParameterValues[$key] }
    }

    $overrideContent = @{
        '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
        contentVersion = '1.0.0.0'
        parameters = $overrideParameters
    }

    $tempPath = Join-Path ([System.IO.Path]::GetTempPath()) ("deploy-overrides-{0}.json" -f ([System.Guid]::NewGuid().ToString('N')))
    $overrideContent | ConvertTo-Json -Depth 10 | Set-Content -Path $tempPath -Encoding utf8
    return $tempPath
}

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

$parameterData = Get-Content $ParametersFile | ConvertFrom-Json
$resourceNamePrefix = $parameterData.parameters.resourceNamePrefix.value
$keyVaultName = ("{0}kv" -f $resourceNamePrefix).ToLower()
if ($keyVaultName.Length -gt 24) {
    $keyVaultName = $keyVaultName.Substring(0, 24)
}
$foundryAccountName = ("{0}foundry" -f $resourceNamePrefix).ToLower()
if ($foundryAccountName.Length -gt 24) {
    $foundryAccountName = $foundryAccountName.Substring(0, 24)
}
$postgresPasswordSecretName = 'postgres-admin-password'
$deploymentPrincipalObjectId = Get-CurrentPrincipalObjectId
$deploymentPrincipalType = Get-CurrentPrincipalType

$keyVaultExists = Test-KeyVaultExists -VaultName $keyVaultName
$postgresPasswordPlain = ''

if ($keyVaultExists) {
    $postgresPasswordPlain = Get-KeyVaultSecretValue -VaultName $keyVaultName -SecretName $postgresPasswordSecretName
    if ([string]::IsNullOrWhiteSpace($postgresPasswordPlain)) {
        Write-Host "Key Vault '$keyVaultName' exists but the PostgreSQL secret is not currently readable. Attempting to grant this deployment identity Key Vault secret read access..." -ForegroundColor Yellow
        if (Grant-KeyVaultSecretReadAccess -VaultName $keyVaultName -PrincipalObjectId $deploymentPrincipalObjectId -PrincipalType $deploymentPrincipalType) {
            Start-Sleep -Seconds 15
            $postgresPasswordPlain = Get-KeyVaultSecretValue -VaultName $keyVaultName -SecretName $postgresPasswordSecretName
        }

        if ([string]::IsNullOrWhiteSpace($postgresPasswordPlain)) {
            Write-Error "Key Vault '$keyVaultName' already exists, but secret '$postgresPasswordSecretName' could not be read. Confirm your identity can read Key Vault secrets before redeploying."
            exit 1
        }
    }
    Write-Host "Reusing existing PostgreSQL admin password from Key Vault '$keyVaultName'." -ForegroundColor Green
} else {
    $postgresPasswordPlain = New-GeneratedPassword
    Write-Host "Generated a new PostgreSQL admin password for Key Vault secret '$postgresPasswordSecretName'." -ForegroundColor Yellow
}

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
} elseif (Test-DeletedFoundryAccount -AccountName $foundryAccountName -AccountLocation $Location) {
    if ($PurgeDeletedFoundryAccount) {
        Write-Host "Purging soft-deleted Foundry account '$foundryAccountName' in '$Location'..." -ForegroundColor Yellow
        if (-not (Remove-DeletedFoundryAccount -AccountName $foundryAccountName -AccountLocation $Location)) {
            Write-Error "Failed to purge soft-deleted Foundry account '$foundryAccountName'."
            exit 1
        }
        Write-Host "Purged soft-deleted Foundry account '$foundryAccountName'." -ForegroundColor Green
    } else {
        Write-Error "Foundry account name '$foundryAccountName' is still reserved by a soft-deleted account in '$Location'. Re-run with -PurgeDeletedFoundryAccount or change resourceNamePrefix in config/parameters.dev.json."
        exit 1
    }
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

    $overridePath = New-DeploymentOverrideFile -ParameterValues @{
        postgresAdminPassword = $postgresPasswordPlain
        postgresPasswordSecretName = $postgresPasswordSecretName
        deployFoundry = $deployFoundry
        deployFoundryModel = $true
        foundryModel = $FoundryModelDeploymentName
        foundryModelName = $ModelName
        foundryModelSkuCapacity = $FoundryModelCapacity
        foundryApiKey = $foundryApiKeyPlain
        foundryEndpoint = $foundryEndpoint
        deployContainerApps = $IncludeContainerApps
    }

    try {
        $azArgs = @(
            'deployment', 'group', 'create',
            '--resource-group', $ResourceGroup,
            '--template-file', $TemplateFile,
            '--parameters', "@$ParametersFile",
            '--parameters', "@$overridePath",
            '--output', 'json'
        )

        & az @azArgs
    }
    finally {
        if (Test-Path $overridePath) {
            Remove-Item $overridePath -Force -ErrorAction SilentlyContinue
        }
    }
}

# --- Phase 1: Deploy infrastructure (without container apps) ---
Write-Host ""
Write-Host "=== Phase 1: Deploying infrastructure ===" -ForegroundColor Cyan
Write-Host "(ACR, PostgreSQL, Storage, Monitor, Foundry)" -ForegroundColor Gray

$infraOutput = $null
$successfulModelName = $null

if (-not $UseExternalFoundry) {
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
    Write-Host "  Password secret: $($outputs.keyVaultName.value)/$($outputs.postgresCredentialName.value)"
    Write-Host ""

    Write-Host "Key Vault:" -ForegroundColor Cyan
    Write-Host "  Name: $($outputs.keyVaultName.value)"
    Write-Host "  URL: $($outputs.keyVaultUrl.value)"
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
