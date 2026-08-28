# LOCAL MINIKUBE DEVELOPMENT HELPER ONLY.
#
# This script exists to simplify Shamir unseal operations in the local Vault POC.
# Production/cloud environments must use the approved auto-unseal/KMS architecture
# rather than this helper.

[CmdletBinding()]
param(
    [string]$Context = "vault-primary",
    [string]$Namespace = "vault",
    [string]$Selector = "app.kubernetes.io/name=vault,component=server",
    [string]$CredentialFile = $env:VAULT_LOCAL_CREDENTIAL_FILE
)

$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

function Assert-CommandExists {
    param([Parameter(Mandatory = $true)][string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found on PATH."
    }
}

function Convert-SecureStringToPlainText {
    param([Parameter(Mandatory = $true)][securestring]$SecureValue)

    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureValue)
    try {
        [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        if ($bstr -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
}

function Get-ShareFromCredentialFile {
    param(
        [Parameter(Mandatory = $true)][int]$Index,
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Credential file was configured but does not exist."
    }

    $credentialData = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    $shares = @()

    if ($credentialData.unseal_keys_b64) {
        $shares = @($credentialData.unseal_keys_b64)
    }
    elseif ($credentialData.unseal_keys) {
        $shares = @($credentialData.unseal_keys)
    }

    if ($shares.Count -lt $Index) {
        throw "Credential file does not contain enough unseal shares."
    }

    return (ConvertTo-SecureString ([string]$shares[$Index - 1]) -AsPlainText -Force)
}

function Get-UnsealShare {
    param(
        [Parameter(Mandatory = $true)][int]$Index,
        [Parameter(Mandatory = $true)][string]$EnvironmentVariable,
        [string]$CredentialFilePath
    )

    $fileShare = Get-ShareFromCredentialFile -Index $Index -Path $CredentialFilePath
    if ($fileShare) {
        return $fileShare
    }

    $envValue = [Environment]::GetEnvironmentVariable($EnvironmentVariable)
    if (-not [string]::IsNullOrWhiteSpace($envValue)) {
        return (ConvertTo-SecureString $envValue -AsPlainText -Force)
    }

    return (Read-Host "Enter Vault unseal share $Index" -AsSecureString)
}

function Invoke-Kubectl {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $output = & kubectl @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw ($output | Out-String).Trim()
    }

    return $output
}

function Get-VaultStatus {
    param([Parameter(Mandatory = $true)][string]$PodName)

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $json = & kubectl `
            --context $Context `
            -n $Namespace `
            exec $PodName `
            -- vault status -format=json 2>&1
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    $jsonText = $json | Out-String

    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 2) {
        throw $jsonText.Trim()
    }

    $jsonStart = $jsonText.IndexOf("{")
    $jsonEnd = $jsonText.LastIndexOf("}")
    if ($jsonStart -lt 0 -or $jsonEnd -lt $jsonStart) {
        throw "Vault status did not return parseable JSON for $PodName."
    }

    return ($jsonText.Substring($jsonStart, $jsonEnd - $jsonStart + 1) | ConvertFrom-Json)
}

function Get-VaultStatusText {
    param([Parameter(Mandatory = $true)][string]$PodName)

    $status = Invoke-Kubectl -Arguments @(
        "--context", $Context,
        "-n", $Namespace,
        "exec", $PodName,
        "--", "vault", "status"
    )

    return ($status | Out-String)
}

function Submit-UnsealShare {
    param(
        [Parameter(Mandatory = $true)][string]$PodName,
        [Parameter(Mandatory = $true)][securestring]$Share
    )

    $plainText = Convert-SecureStringToPlainText $Share
    try {
        & kubectl --context $Context -n $Namespace exec $PodName -- vault operator unseal -format=json $plainText 1>$null
        if ($LASTEXITCODE -ne 0) {
            throw "Unseal operation failed for $PodName."
        }
    }
    finally {
        $plainText = $null
    }
}

Assert-CommandExists "kubectl"

$contexts = Invoke-Kubectl -Arguments @("config", "get-contexts", "-o", "name")
if ($contexts -notcontains $Context) {
    throw "Kubernetes context '$Context' was not found."
}

Invoke-Kubectl -Arguments @("--context", $Context, "get", "namespace", $Namespace, "-o", "name") | Out-Null

$podNames = Invoke-Kubectl -Arguments @(
    "--context", $Context,
    "-n", $Namespace,
    "get", "pods",
    "-l", $Selector,
    "-o", "jsonpath={range .items[*]}{.metadata.name}{'\n'}{end}"
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

if (-not $podNames -or $podNames.Count -eq 0) {
    throw "No Vault server pods were found in namespace '$Namespace' with selector '$Selector'."
}

$shares = @(
    (Get-UnsealShare -Index 1 -EnvironmentVariable "VAULT_UNSEAL_KEY_1" -CredentialFilePath $CredentialFile),
    (Get-UnsealShare -Index 2 -EnvironmentVariable "VAULT_UNSEAL_KEY_2" -CredentialFilePath $CredentialFile),
    (Get-UnsealShare -Index 3 -EnvironmentVariable "VAULT_UNSEAL_KEY_3" -CredentialFilePath $CredentialFile)
)

if (($shares | Where-Object { $_ -ne $null }).Count -lt 3) {
    throw "Three unseal shares are required."
}

foreach ($podName in $podNames) {
    $status = Get-VaultStatus $podName

    if (-not $status.initialized) {
        throw "Vault is not initialized. Automatic initialization is intentionally not performed."
    }

    if (-not $status.sealed) {
        Write-Output "${podName}: already unsealed"
        continue
    }

    Write-Output "${podName}: sealed -> unsealing"

    foreach ($share in $shares) {
        Submit-UnsealShare -PodName $podName -Share $share
        $status = Get-VaultStatus $podName

        if (-not $status.sealed) {
            Write-Output "${podName}: unsealed"
            break
        }
    }

    $status = Get-VaultStatus $podName
    if ($status.sealed) {
        throw "$podName remains sealed after the provided shares were submitted."
    }
}

$finalStatuses = foreach ($podName in $podNames) {
    Get-VaultStatus $podName
}

$unsealedCount = ($finalStatuses | Where-Object { -not $_.sealed }).Count
$haEnabled = ($finalStatuses | Where-Object { $_.ha_enabled } | Select-Object -First 1) -ne $null

Write-Output ""
Write-Output "Vault cluster:"
Write-Output "$unsealedCount/$($podNames.Count) unsealed"
Write-Output "HA enabled: $haEnabled"
