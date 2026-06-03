[CmdletBinding()]
param(
    [string] $InstallRoot = (Join-Path $env:LOCALAPPDATA "Programs\YulieAI"),
    [string] $ProfileRoot = (Join-Path $env:LOCALAPPDATA "YulieAI\profile"),
    [string] $CredentialPath,
    [switch] $ForceEngineInstall,
    [switch] $SkipEngineInstall,
    [switch] $SkipEnginePatch,
    [switch] $AcceptIbmLicense
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProductName = "YulieAI"
$InstallScriptRoot = if ($env:YULIEAI_PACKAGE_ROOT) { $env:YULIEAI_PACKAGE_ROOT } elseif ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }

function Write-Step {
    param([string] $Message)
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function New-Directory {
    param([string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Assert-LocalPackage {
    if (-not $InstallScriptRoot -or -not (Test-Path -LiteralPath $InstallScriptRoot)) {
        throw "Run this installer from the extracted YulieAI package. For one-line installs, use bootstrap.ps1."
    }

    foreach ($relative in @("bin\yulieai-core.ps1", "bin\yulieai.cmd", "config\settings.json", "config\rules\yulieai.md")) {
        $path = Join-Path $InstallScriptRoot $relative
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Missing package file: $relative"
        }
    }
}

function Get-BundledNodeRoot {
    return Join-Path $InstallRoot "nodejs"
}

function Get-CommandSource {
    param([string[]] $Names)

    foreach ($name in $Names) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd -and $cmd.Source) {
            return $cmd.Source
        }
    }

    return $null
}

function Resolve-NpmRuntime {
    param([switch] $AllowMissing)

    $bundled = Join-Path (Get-BundledNodeRoot) "npm.cmd"
    if (Test-Path -LiteralPath $bundled) {
        return $bundled
    }

    $npm = Get-CommandSource -Names @("npm.cmd", "npm.exe", "npm")
    if ($npm) {
        return $npm
    }

    if ($AllowMissing) {
        return $null
    }

    throw "npm was not found. Re-run the installer so YulieAI can install its local Node.js runtime."
}

function Add-PathForCurrentProcess {
    param([string] $PathToAdd)

    if ($PathToAdd -and (Test-Path -LiteralPath $PathToAdd)) {
        $parts = $env:Path -split ";" | Where-Object { $_ -and $_.Trim().Length -gt 0 }
        $alreadyPresent = $false
        foreach ($part in $parts) {
            if ($part.TrimEnd("\") -ieq $PathToAdd.TrimEnd("\")) {
                $alreadyPresent = $true
                break
            }
        }

        if (-not $alreadyPresent) {
            $env:Path = "$PathToAdd;$env:Path"
        }
    }
}

function Add-NpmGlobalBinToPath {
    $npmBin = Join-Path $env:APPDATA "npm"
    if (Test-Path -LiteralPath $npmBin) {
        Add-PathForCurrentProcess -PathToAdd $npmBin
        Add-UserPath -PathToAdd $npmBin
    }
}

function Ensure-NodeRuntime {
    $node = Get-CommandSource -Names @("node.exe", "node")
    $npm = Get-CommandSource -Names @("npm.cmd", "npm.exe", "npm")
    if ($node -and $npm) {
        return
    }

    $nodeRoot = Get-BundledNodeRoot
    $nodeExe = Join-Path $nodeRoot "node.exe"
    $npmCmd = Join-Path $nodeRoot "npm.cmd"
    if ((Test-Path -LiteralPath $nodeExe) -and (Test-Path -LiteralPath $npmCmd)) {
        Add-PathForCurrentProcess -PathToAdd $nodeRoot
        Add-UserPath -PathToAdd $nodeRoot
        return
    }

    Write-Step "Installing local Node.js runtime"
    $nodeVersion = "22.20.0"
    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64" -or $env:PROCESSOR_ARCHITEW6432 -eq "ARM64") { "win-arm64" } else { "win-x64" }
    $zipName = "node-v$nodeVersion-$arch.zip"
    $nodeUrl = "https://nodejs.org/dist/v$nodeVersion/$zipName"
    $zipPath = Join-Path $env:TEMP $zipName
    $extractRoot = Join-Path $env:TEMP "yulieai-node-$nodeVersion"
    $expandedRoot = Join-Path $extractRoot "node-v$nodeVersion-$arch"

    Remove-Item -LiteralPath $extractRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
    Invoke-WebRequest -Uri $nodeUrl -OutFile $zipPath -UseBasicParsing
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractRoot -Force

    if (-not (Test-Path -LiteralPath $expandedRoot)) {
        throw "Downloaded Node.js package could not be extracted correctly: $zipName"
    }

    New-Directory -Path (Split-Path -Parent $nodeRoot)
    Remove-Item -LiteralPath $nodeRoot -Recurse -Force -ErrorAction SilentlyContinue
    Move-Item -LiteralPath $expandedRoot -Destination $nodeRoot -Force
    Remove-Item -LiteralPath $extractRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue

    if (-not ((Test-Path -LiteralPath $nodeExe) -and (Test-Path -LiteralPath $npmCmd))) {
        throw "Local Node.js runtime was installed, but node.exe or npm.cmd was not found."
    }

    Add-PathForCurrentProcess -PathToAdd $nodeRoot
    Add-UserPath -PathToAdd $nodeRoot
}

function Install-YulieEngine {
    if ($SkipEngineInstall) {
        return
    }

    Add-NpmGlobalBinToPath
    if (-not $ForceEngineInstall) {
        try {
            $existing = Resolve-YulieEngineScript
            if ($existing) {
                Write-Step "YulieAI engine already installed"
                return
            }
        }
        catch {
        }
    }

    Write-Step "Installing YulieAI engine"
    $engineInstaller = Join-Path $env:TEMP "yulieai-engine-installer.ps1"
    Invoke-WebRequest -Uri "https://bob.ibm.com/download/bobshell.ps1" -OutFile $engineInstaller -UseBasicParsing

    # Equivalent to:
    # powershell -ep Bypass 'irm -Uri "https://bob.ibm.com/download/bobshell.ps1" | iex'
    # but with npm preselected so office users are not asked to choose a package manager.
    $engineInstallLog = Join-Path $env:TEMP "yulieai-engine-install.log"
    $engineInstallOutput = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $engineInstaller -pm npm 2>&1
    $engineInstallCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
    Set-Content -LiteralPath $engineInstallLog -Value ($engineInstallOutput | Out-String) -Encoding UTF8
    Remove-Item -LiteralPath $engineInstaller -Force -ErrorAction SilentlyContinue

    if ($engineInstallCode -ne 0) {
        throw "YulieAI engine installation failed. See log: $engineInstallLog"
    }

    Add-NpmGlobalBinToPath
    try {
        [void] (Resolve-YulieEngineScript)
    }
    catch {
        throw "YulieAI engine installation finished, but the engine bundle was not found. See log: $engineInstallLog"
    }
}

function Patch-YulieEngineBranding {
    if ($SkipEnginePatch) {
        return
    }

    $npm = Resolve-NpmRuntime -AllowMissing
    if (-not $npm) {
        Write-Host "Skipping engine branding patch: npm was not found." -ForegroundColor Yellow
        return
    }

    $globalRoot = (& $npm root -g | Select-Object -Last 1).Trim()
    if (-not $globalRoot) {
        Write-Host "Skipping engine branding patch: npm global root was not detected." -ForegroundColor Yellow
        return
    }

    $bundlePath = Join-Path $globalRoot "bobshell\bundle\bob.js"
    if (-not (Test-Path -LiteralPath $bundlePath)) {
        Write-Host "Skipping engine branding patch: engine bundle was not found." -ForegroundColor Yellow
        return
    }

    $backupPath = "$bundlePath.yulieai-original"
    if (-not (Test-Path -LiteralPath $backupPath)) {
        Copy-Item -LiteralPath $bundlePath -Destination $backupPath -Force
    }
    else {
        Copy-Item -LiteralPath $backupPath -Destination $bundlePath -Force
    }

    $encoding = New-Object System.Text.UTF8Encoding($false)
    $content = [System.IO.File]::ReadAllText($bundlePath, $encoding)
    $patched = $content
    $wideBanner = @'
__   __ _   _  _      ___  ___     _     ___
\ \ / /| | | || |    |_ _|| __|   /_\   |_ _|
 \ V / | |_| || |__   | | | _|   / _ \   | |
  |_|   \___/ |____| |___||___| /_/ \_\ |___|
'@.Trim("`r", "`n")
    $narrowBanner = @'
__   __     _ _       _   ___
\ \ / /   _| (_) ___ / \ |_ _|
 \ V / | | | | |/ _ / _ \ | |
  | || |_| | | |  __/ ___ \| |
  |_| \__,_|_|_|\___/_/   \_\___|
'@.Trim("`r", "`n")
    $brandLine = "Yulie Sekuritas Indonesia Tbk AI"
    $goldTheme = @'
var txi={name:"Yulie Gold",type:"custom",Background:"#14110B",Foreground:"#F4E8D0",LightBlue:"#F6E3B1",AccentBlue:"#D6A84F",AccentPurple:"#A66A2A",AccentCyan:"#E7C66B",AccentGreen:"#8FBF73",AccentYellow:"#F2C14E",AccentRed:"#E05A47",Comment:"#7A6A52",Gray:"#A89675",DiffAdded:exi("#1F3A20","ansi256(22)"),DiffRemoved:exi("#4A1712","ansi256(52)"),DiffModified:"#3A2B12",GradientColors:["#F2C14E","#8A5A1E"],DarkGray:"#2B2418"};var rxi=
'@.Trim("`r", "`n")
    $replacements = @(
        @("Bob Shell", "YulieAI"),
        @("Bob shell", "YulieAI"),
        @("Bob-Shell", "YulieAI"),
        @("IBM Bob", "YulieAI"),
        @(" Welcome to ", " YulieAI "),
        @("Usage: bob", "Usage: yulieai"),
        @("scriptName(`"bob`")", "scriptName(`"yulieai`")"),
        @("Here are some helpful commands to get started:", "Yulie Sekuritas Indonesia Tbk AI"),
        @("Users should independently verify accuracy of AI-generated content.", "YulieAI siap membantu pekerjaan Anda."),
        @("Enter your prompt, / for commands, @ for files, ! for Shell mode", "Tulis permintaan Anda, / perintah, @ file, ! shell"),
        @("Enter your prompt", "Tulis permintaan Anda"),
        @("You are running YulieAI in your home directory. It is recommended to run in a project-specific directory.", "YulieAI berjalan di direktori home. Untuk pekerjaan file/proyek, buka folder terkait terlebih dahulu.")
    )

    foreach ($item in $replacements) {
        $patched = $patched.Replace([string] $item[0], [string] $item[1])
    }

    $pJReplacement = "pJ=String.raw``$wideBanner``"
    $j3Replacement = "J3=String.raw``$wideBanner``"
    $sieReplacement = "SIe=String.raw``$narrowBanner``"
    $rprReplacement = "Rpr=String.raw``$brandLine``;function"
    $patched = ([regex]::new('pJ=String\.raw`[\s\S]*?`,J3=String\.raw`')).Replace(
        $patched,
        [System.Text.RegularExpressions.MatchEvaluator] { param($match) "$pJReplacement,J3=String.raw``" },
        1
    )
    $patched = ([regex]::new('J3=String\.raw`[\s\S]*?`,SIe=String\.raw`')).Replace(
        $patched,
        [System.Text.RegularExpressions.MatchEvaluator] { param($match) "$j3Replacement,SIe=String.raw``" },
        1
    )
    $patched = ([regex]::new('SIe=String\.raw`[\s\S]*?`,Rpr=String\.raw`')).Replace(
        $patched,
        [System.Text.RegularExpressions.MatchEvaluator] { param($match) "$sieReplacement,Rpr=String.raw``" },
        1
    )
    $patched = ([regex]::new('Rpr=String\.raw`[\s\S]*?`;function')).Replace(
        $patched,
        [System.Text.RegularExpressions.MatchEvaluator] { param($match) $rprReplacement },
        1
    )
    $patched = ([regex]::new('var txi=\{name:"IBM Carbon Dark"[\s\S]*?\};var rxi=')).Replace(
        $patched,
        [System.Text.RegularExpressions.MatchEvaluator] { param($match) $goldTheme },
        1
    )
    $patched = $patched.Replace('t.merged.ui.customThemes={"IBM Carbon Dark":txi,"IBM Carbon Light":rxi}', 't.merged.ui.customThemes={"Yulie Gold":txi,"IBM Carbon Dark":txi,"IBM Carbon Light":rxi}')
    $patched = $patched.Replace('t.merged.ui.theme||(t.merged.ui.theme="IBM Carbon Dark")', 't.merged.ui.theme||(t.merged.ui.theme="Yulie Gold")')
    $patched = $patched.Replace('["#0F62FE","#A56EFF"]', '["#D6A84F","#8A5A1E"]')
    $patched = $patched.Replace('"#D0E2FF","#78A9FF"', '"#F6E3B1","#D6A84F"')

    if ($patched -ne $content) {
        [System.IO.File]::WriteAllText($bundlePath, $patched, $encoding)
        Write-Step "Applied YulieAI branding patch to the local engine"
    }
    else {
        Write-Host "Engine branding patch had no matching strings to replace." -ForegroundColor Yellow
    }
}

function Resolve-NodeRuntime {
    $bundled = Join-Path (Get-BundledNodeRoot) "node.exe"
    if (Test-Path -LiteralPath $bundled) {
        return $bundled
    }

    $cmd = Get-CommandSource -Names @("node.exe", "node")
    if (-not $cmd) {
        throw "Node.js is not installed or not available in PATH."
    }
    return $cmd
}

function Resolve-YulieEngineScript {
    $npm = Resolve-NpmRuntime -AllowMissing
    if ($npm) {
        $globalRoot = (& $npm root -g | Select-Object -Last 1).Trim()
        if ($globalRoot) {
            $candidate = Join-Path $globalRoot "bobshell\bundle\bob.js"
            if (Test-Path -LiteralPath $candidate) {
                return $candidate
            }
        }
    }

    $bob = Get-Command "bob.cmd" -ErrorAction SilentlyContinue
    if (-not $bob) {
        $bob = Get-Command "bob" -ErrorAction SilentlyContinue
    }

    if ($bob -and $bob.Source) {
        $npmBin = Split-Path -Parent $bob.Source
        $candidate = Join-Path $npmBin "node_modules\bobshell\bundle\bob.js"
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    throw "YulieAI engine bundle was not found."
}

function Install-Credential {
    param(
        [string] $SourcePath,
        [string] $TargetPath
    )

    if (-not (Test-Path -LiteralPath $SourcePath)) {
        throw "Credential file not found: $SourcePath"
    }

    $json = Get-Content -LiteralPath $SourcePath -Raw | ConvertFrom-Json
    if (-not $json.apikey) {
        throw "Credential JSON must contain an 'apikey' field."
    }

    $secure = ConvertTo-SecureString -String ([string] $json.apikey) -AsPlainText -Force
    $encrypted = $secure | ConvertFrom-SecureString

    New-Directory -Path (Split-Path -Parent $TargetPath)
    Set-Content -LiteralPath $TargetPath -Value $encrypted -NoNewline -Encoding UTF8
}

function Add-UserPath {
    param([string] $PathToAdd)

    $current = [Environment]::GetEnvironmentVariable("Path", "User")
    $parts = @()
    if ($current) {
        $parts = $current -split ";" | Where-Object { $_ -and $_.Trim().Length -gt 0 }
    }

    $alreadyPresent = $false
    foreach ($part in $parts) {
        if ($part.TrimEnd("\") -ieq $PathToAdd.TrimEnd("\")) {
            $alreadyPresent = $true
            break
        }
    }

    if (-not $alreadyPresent) {
        $newPath = (@($PathToAdd) + $parts) -join ";"
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    }

    if (($env:Path -split ";") -notcontains $PathToAdd) {
        $env:Path = "$PathToAdd;$env:Path"
    }
}

function Enable-VirtualTerminalRendering {
    try {
        $consoleKeys = @(
            "HKCU:\Console",
            "HKCU:\Console\%SystemRoot%_System32_WindowsPowerShell_v1.0_powershell.exe",
            "HKCU:\Console\C:_Windows_System32_WindowsPowerShell_v1.0_powershell.exe",
            "HKCU:\Console\%SystemRoot%_System32_cmd.exe",
            "HKCU:\Console\C:_Windows_System32_cmd.exe"
        )

        foreach ($consoleKey in $consoleKeys) {
            if (-not (Test-Path -LiteralPath $consoleKey)) {
                New-Item -Path $consoleKey -Force | Out-Null
            }
            New-ItemProperty -Path $consoleKey -Name "VirtualTerminalLevel" -Value 1 -PropertyType DWord -Force | Out-Null
            New-ItemProperty -Path $consoleKey -Name "FaceName" -Value "Consolas" -PropertyType String -Force | Out-Null
            New-ItemProperty -Path $consoleKey -Name "FontFamily" -Value 54 -PropertyType DWord -Force | Out-Null
            New-ItemProperty -Path $consoleKey -Name "FontSize" -Value 917504 -PropertyType DWord -Force | Out-Null
            New-ItemProperty -Path $consoleKey -Name "FontWeight" -Value 400 -PropertyType DWord -Force | Out-Null
        }
    }
    catch {
        Write-Host "Skipping terminal rendering setup: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

function Install-Profile {
    param([string] $TargetProfileRoot)

    $bobRoot = Join-Path $TargetProfileRoot ".bob"
    New-Directory -Path $bobRoot
    New-Directory -Path (Join-Path $bobRoot "rules")

    Copy-Item -LiteralPath (Join-Path $InstallScriptRoot "config\settings.json") -Destination (Join-Path $bobRoot "settings.json") -Force
    Copy-Item -LiteralPath (Join-Path $InstallScriptRoot "config\custom_modes.yaml") -Destination (Join-Path $bobRoot "custom_modes.yaml") -Force
    Copy-Item -LiteralPath (Join-Path $InstallScriptRoot "config\rules\yulieai.md") -Destination (Join-Path $bobRoot "rules\yulieai.md") -Force
}

function Accept-EngineLicense {
    param([string] $TargetProfileRoot)

    if (-not $AcceptIbmLicense) {
        Write-Host ""
        Write-Host "YulieAI uses an IBM-provided engine. Continue only if your organization accepts the IBM license terms." -ForegroundColor Yellow
        $answer = Read-Host "Type ACCEPT to continue"
        if ($answer -ne "ACCEPT") {
            throw "Installation cancelled because license acceptance was not confirmed."
        }
    }

    $oldUserProfile = $env:USERPROFILE
    $oldHome = $env:HOME
    try {
        $env:USERPROFILE = $TargetProfileRoot
        $env:HOME = $TargetProfileRoot
        $node = Resolve-NodeRuntime
        $engineScript = Resolve-YulieEngineScript
        & $node $engineScript --accept-license --auth-method api-key --version | Out-Null
    }
    finally {
        if ($null -eq $oldUserProfile) { Remove-Item Env:\USERPROFILE -ErrorAction SilentlyContinue } else { $env:USERPROFILE = $oldUserProfile }
        if ($null -eq $oldHome) { Remove-Item Env:\HOME -ErrorAction SilentlyContinue } else { $env:HOME = $oldHome }
    }
}

Assert-LocalPackage

if (-not $CredentialPath) {
    $CredentialPath = Join-Path $InstallScriptRoot "credentials\yulieai.json"
}

$BinRoot = Join-Path $InstallRoot "bin"
$DataRoot = Join-Path $env:LOCALAPPDATA "YulieAI"
$SecureKeyPath = Join-Path $DataRoot "secure\bobshell_api_key.dpapi"

Write-Step "Installing $ProductName files"
New-Directory -Path $InstallRoot
New-Directory -Path $BinRoot
Copy-Item -LiteralPath (Join-Path $InstallScriptRoot "bin\yulieai.cmd") -Destination (Join-Path $BinRoot "yulieai.cmd") -Force
Copy-Item -LiteralPath (Join-Path $InstallScriptRoot "bin\yulieai-core.ps1") -Destination (Join-Path $BinRoot "yulieai-core.ps1") -Force
Remove-Item -LiteralPath (Join-Path $BinRoot "yulieai.ps1") -Force -ErrorAction SilentlyContinue

Write-Step "Installing $ProductName profile"
Install-Profile -TargetProfileRoot $ProfileRoot

Write-Step "Protecting credential with Windows DPAPI"
Install-Credential -SourcePath $CredentialPath -TargetPath $SecureKeyPath

Ensure-NodeRuntime

Install-YulieEngine

Patch-YulieEngineBranding

Write-Step "Accepting engine license for the YulieAI profile"
Accept-EngineLicense -TargetProfileRoot $ProfileRoot

Write-Step "Adding YulieAI to user PATH"
Add-UserPath -PathToAdd $BinRoot

Write-Step "Configuring terminal rendering"
Enable-VirtualTerminalRendering

Write-Host ""
Write-Host "YulieAI installed successfully." -ForegroundColor Green
Write-Host "Run now: yulieai doctor"
