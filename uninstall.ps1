[CmdletBinding()]
param(
    [switch] $KeepCredential,
    [switch] $KeepProfile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$InstallRoot = Join-Path $env:LOCALAPPDATA "Programs\YulieAI"
$DataRoot = Join-Path $env:LOCALAPPDATA "YulieAI"
$BinRoot = Join-Path $InstallRoot "bin"

function Remove-UserPath {
    param([string] $PathToRemove)

    $current = [Environment]::GetEnvironmentVariable("Path", "User")
    if (-not $current) { return }

    $remaining = $current -split ";" | Where-Object {
        $_ -and ($_.TrimEnd("\") -ine $PathToRemove.TrimEnd("\"))
    }
    [Environment]::SetEnvironmentVariable("Path", ($remaining -join ";"), "User")
}

Remove-UserPath -PathToRemove $BinRoot

if (Test-Path -LiteralPath $InstallRoot) {
    Remove-Item -LiteralPath $InstallRoot -Recurse -Force
}

if (Test-Path -LiteralPath $DataRoot) {
    if ($KeepCredential -or $KeepProfile) {
        if (-not $KeepCredential) {
            Remove-Item -LiteralPath (Join-Path $DataRoot "secure") -Recurse -Force -ErrorAction SilentlyContinue
        }
        if (-not $KeepProfile) {
            Remove-Item -LiteralPath (Join-Path $DataRoot "profile") -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    else {
        Remove-Item -LiteralPath $DataRoot -Recurse -Force
    }
}

Write-Host "YulieAI removed. Open a new terminal to refresh PATH." -ForegroundColor Green
