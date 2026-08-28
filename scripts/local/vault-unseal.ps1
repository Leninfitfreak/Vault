# LOCAL MINIKUBE DEVELOPMENT HELPER ONLY.
#
# This script exists to simplify Shamir unseal operations in the local Vault POC.
# Production/cloud environments must use the approved auto-unseal/KMS architecture
# rather than this helper.

[CmdletBinding()]
param(
    [string]$Context = "vault-primary",
    [string]$Namespace = "vault",
    [string]$Selector = "app.kubernetes.io/name=vault,component=server"
)

$ErrorActionPreference = "Stop"

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

function Get-UnsealShare {
    param(
        [Parameter(Mandatory = $true)][int]$Index,
        [Parameter(Mandatory = $true)][string]$EnvironmentVariable
    )

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

    $json = Invoke-Kubectl -Arguments @(
        "--context", $Context,
        "-n", $Namespace,
        "exec", $PodName,
        "--", "vault", "status", "-format=json"
    )

    return ($json | Out-String | ConvertFrom-Json)
}

function Submit-UnsealShare {
    param(
        [Parameter(Mandatory = $true)][string]$PodName,
        [Parameter(Mandatory = $true)][securestring]$Share
    )

    $plainText = Convert-SecureStringToPlainText $Share
    try {
        $plainText | & kubectl --context $Context -n $Namespace exec -i $PodName -- vault operator unseal -format=json 1>$null
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
    (Get-UnsealShare -Index 1 -EnvironmentVariable "VAULT_UNSEAL_KEY_1"),
    (Get-UnsealShare -Index 2 -EnvironmentVariable "VAULT_UNSEAL_KEY_2"),
    (Get-UnsealShare -Index 3 -EnvironmentVariable "VAULT_UNSEAL_KEY_3")
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
