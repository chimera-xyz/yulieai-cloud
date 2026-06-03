$PackageCandidates = @(
    "http://192.168.80.6:8787/yulieai-windows.zip",
    "http://192.168.1.24:8787/yulieai-windows.zip"
)
$PackageUrl = $null
$TempRoot = Join-Path $env:TEMP ("yulieai-install-" + [Guid]::NewGuid().ToString("N"))
$ZipPath = Join-Path $TempRoot "yulieai-windows.zip"
$ExtractRoot = Join-Path $TempRoot "package"
$LogPath = Join-Path $env:TEMP "yulieai-install.log"

$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Path $TempRoot | Out-Null

try {
    "YulieAI install started: $(Get-Date -Format o)" | Set-Content -LiteralPath $LogPath -Encoding UTF8

    foreach ($Candidate in $PackageCandidates) {
        try {
            Invoke-WebRequest -Uri $Candidate -Method Head -UseBasicParsing -TimeoutSec 3 | Out-Null
            $PackageUrl = $Candidate
            break
        }
        catch {
            continue
        }
    }

    if (-not $PackageUrl) {
        throw "YulieAI package was not reachable. Check that the Mac server is running and the Windows PC is on the same network."
    }

    Write-Host "Downloading YulieAI..." -ForegroundColor Cyan
    Write-Host $PackageUrl -ForegroundColor DarkCyan
    "PackageUrl: $PackageUrl" | Add-Content -LiteralPath $LogPath -Encoding UTF8
    Invoke-WebRequest -Uri $PackageUrl -OutFile $ZipPath -UseBasicParsing
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $ExtractRoot -Force

    $Installer = Get-ChildItem -Path $ExtractRoot -Filter "install.ps1" -Recurse | Select-Object -First 1
    if (-not $Installer) {
        throw "install.ps1 was not found in the YulieAI package."
    }

    Write-Host "Installing YulieAI..." -ForegroundColor Cyan
    "Installer: $($Installer.FullName)" | Add-Content -LiteralPath $LogPath -Encoding UTF8
    $oldPackageRoot = $env:YULIEAI_PACKAGE_ROOT
    $env:YULIEAI_PACKAGE_ROOT = Split-Path -Parent $Installer.FullName
    $installCode = 0
    try {
        $installScript = Get-Content -LiteralPath $Installer.FullName -Raw
        $installBlock = [ScriptBlock]::Create($installScript)
        & $installBlock -AcceptIbmLicense 2>&1 | Tee-Object -FilePath $LogPath -Append
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

    Write-Host ""
    Write-Host "YulieAI install finished. Open a new terminal and run: yulieai doctor" -ForegroundColor Green
    Write-Host "Log: $LogPath" -ForegroundColor DarkGray
}
catch {
    Write-Host ""
    Write-Host "YulieAI install failed:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host "Log: $LogPath" -ForegroundColor Yellow
    $_ | Out-String | Add-Content -LiteralPath $LogPath -Encoding UTF8
    $global:LASTEXITCODE = 1
}
finally {
    Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

