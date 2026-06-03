[CmdletBinding()]
param(
    [string] $PackageUrl = $env:YULIEAI_PACKAGE_URL,
    [switch] $AcceptIbmLicense
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not $PackageUrl) {
    throw "Set YULIEAI_PACKAGE_URL or pass -PackageUrl. Example: powershell -ep Bypass -File bootstrap.ps1 -PackageUrl http://PC-ADMIN:8787/yulieai-windows.zip"
}

$tempRoot = Join-Path $env:TEMP ("yulieai-install-" + [Guid]::NewGuid().ToString("N"))
$zipPath = Join-Path $tempRoot "yulieai-windows.zip"
$extractRoot = Join-Path $tempRoot "package"
$logPath = Join-Path $env:TEMP "yulieai-install.log"

New-Item -ItemType Directory -Path $tempRoot | Out-Null

try {
    "YulieAI bootstrap started: $(Get-Date -Format o)" | Set-Content -LiteralPath $logPath -Encoding UTF8
    Write-Host "Downloading YulieAI package..." -ForegroundColor Cyan
    "PackageUrl: $PackageUrl" | Add-Content -LiteralPath $logPath -Encoding UTF8
    Invoke-WebRequest -Uri $PackageUrl -OutFile $zipPath
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractRoot -Force

    $installer = Get-ChildItem -Path $extractRoot -Filter "install.ps1" -Recurse | Select-Object -First 1
    if (-not $installer) {
        throw "install.ps1 was not found in the package."
    }

    $oldPackageRoot = $env:YULIEAI_PACKAGE_ROOT
    $env:YULIEAI_PACKAGE_ROOT = Split-Path -Parent $installer.FullName
    $installCode = 0
    try {
        $installScript = Get-Content -LiteralPath $installer.FullName -Raw
        $installBlock = [ScriptBlock]::Create($installScript)
        if ($AcceptIbmLicense) {
            & $installBlock -AcceptIbmLicense 2>&1 | Tee-Object -FilePath $logPath -Append
        }
        else {
            & $installBlock 2>&1 | Tee-Object -FilePath $logPath -Append
        }
        $installCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
    }
    finally {
        if ($null -eq $oldPackageRoot) {
            Remove-Item Env:\YULIEAI_PACKAGE_ROOT -ErrorAction SilentlyContinue
        }
        else {
            $env:YULIEAI_PACKAGE_ROOT = $oldPackageRoot
        }
    }

    if ($installCode -ne 0) {
        throw "YulieAI installer exited with code $installCode"
    }

    Write-Host "YulieAI install finished. Open a new terminal and run: yulieai doctor" -ForegroundColor Green
    Write-Host "Log: $logPath" -ForegroundColor DarkGray
}
catch {
    Write-Host ""
    Write-Host "YulieAI install failed:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host "Log: $logPath" -ForegroundColor Yellow
    $_ | Out-String | Add-Content -LiteralPath $logPath -Encoding UTF8
    $global:LASTEXITCODE = 1
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
