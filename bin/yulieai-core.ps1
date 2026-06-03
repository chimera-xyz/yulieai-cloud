[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $RemainingArgs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
$host.UI.RawUI.WindowTitle = "YulieAI - Yulie Sekuritas Indonesia Tbk"
$env:TERM = "xterm-256color"
$env:FORCE_COLOR = "1"
Remove-Item Env:\NO_COLOR -ErrorAction SilentlyContinue

if ($null -eq $RemainingArgs) {
    $RemainingArgs = @()
}
else {
    $RemainingArgs = @($RemainingArgs)
}

$ProductName = "YulieAI"
$ProductVersion = "0.6.4"
$InstallRoot = if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot } else { Join-Path $env:LOCALAPPDATA "Programs\YulieAI" }
$DataRoot = Join-Path $env:LOCALAPPDATA "YulieAI"
$ProfileRoot = Join-Path $DataRoot "profile"
$SecureKeyPath = Join-Path $DataRoot "secure\bobshell_api_key.dpapi"
$script:YulieLastExitCode = 0

function Limit-Text {
    param(
        [string] $Text,
        [int] $MaxLength
    )

    if ($null -eq $Text) {
        return ""
    }

    if ($MaxLength -le 0) {
        return ""
    }

    if ($Text.Length -le $MaxLength) {
        return $Text
    }

    if ($MaxLength -le 3) {
        return $Text.Substring(0, $MaxLength)
    }

    return "..." + $Text.Substring($Text.Length - ($MaxLength - 3))
}

function Get-SafeConsoleWidth {
    try {
        if ([Console]::WindowWidth -gt 0) {
            return [Console]::WindowWidth
        }
    }
    catch {
    }

    return 82
}

function Get-ArgumentValue {
    param(
        [string[]] $Arguments,
        [string] $Name,
        [string] $Default
    )

    if (-not $Arguments) {
        return $Default
    }

    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        $arg = $Arguments[$i]
        if ($arg -eq $Name -and $i + 1 -lt $Arguments.Count) {
            return $Arguments[$i + 1]
        }
        if ($arg.StartsWith("$Name=")) {
            return $arg.Substring($Name.Length + 1)
        }
    }

    return $Default
}

function Get-DisplayDirectory {
    $path = (Get-Location).Path
    if ($env:USERPROFILE -and $path.StartsWith($env:USERPROFILE, [StringComparison]::OrdinalIgnoreCase)) {
        $path = "~" + $path.Substring($env:USERPROFILE.Length)
    }
    return $path
}

function Test-PathUnder {
    param(
        [string] $Path,
        [string] $Parent
    )

    if (-not $Path -or -not $Parent) {
        return $false
    }

    try {
        $fullPath = [System.IO.Path]::GetFullPath($Path).TrimEnd("\")
        $fullParent = [System.IO.Path]::GetFullPath($Parent).TrimEnd("\")
        return $fullPath.Equals($fullParent, [StringComparison]::OrdinalIgnoreCase) -or
            $fullPath.StartsWith($fullParent + "\", [StringComparison]::OrdinalIgnoreCase)
    }
    catch {
        return $false
    }
}

function Resolve-SafeWorkingDirectory {
    param([string] $RealUserProfile)

    $current = (Get-Location).Path
    if (Test-PathUnder -Path $current -Parent $env:WINDIR) {
        $desktop = [Environment]::GetFolderPath("Desktop")
        if ($desktop -and (Test-Path -LiteralPath $desktop)) {
            return $desktop
        }

        if ($RealUserProfile -and (Test-Path -LiteralPath $RealUserProfile)) {
            return $RealUserProfile
        }
    }

    return $current
}

function Write-BoxLine {
    param(
        [string] $Text,
        [int] $Width,
        [ConsoleColor] $Color = [ConsoleColor]::Gray
    )

    $innerWidth = $Width - 4
    $clean = Limit-Text -Text $Text -MaxLength $innerWidth
    $padding = " " * ($innerWidth - $clean.Length)

    Write-Host -NoNewline "| " -ForegroundColor DarkGray
    Write-Host -NoNewline $clean -ForegroundColor $Color
    Write-Host -NoNewline $padding
    Write-Host " |" -ForegroundColor DarkGray
}

function Write-YulieBanner {
    param([string[]] $EngineArgs = @())

    if ([Console]::IsOutputRedirected) {
        return
    }

    $mode = Get-ArgumentValue -Arguments $EngineArgs -Name "--chat-mode" -Default "advanced"
    $directory = Get-DisplayDirectory
    $width = [Math]::Min([Math]::Max((Get-SafeConsoleWidth) - 2, 62), 88)
    $rule = "+" + ("-" * ($width - 2)) + "+"

    Write-Host ""
    Write-Host $rule -ForegroundColor DarkGray
    Write-BoxLine -Width $width -Text (">_ YulieAI (v$ProductVersion)") -Color Cyan
    Write-BoxLine -Width $width -Text "" -Color Gray
    Write-BoxLine -Width $width -Text ("model:     YulieAI Agent        mode: " + $mode) -Color Gray
    Write-BoxLine -Width $width -Text ("directory: " + $directory) -Color Gray
    Write-Host $rule -ForegroundColor DarkGray
    Write-Host ""
}

function Write-YulieSplash {
    if ([Console]::IsOutputRedirected) {
        return
    }

    Write-Host ""
    Write-Host "    YULIEAI" -ForegroundColor Yellow
    Write-Host "    Yulie Sekuritas Indonesia Tbk AI" -ForegroundColor Cyan
    Write-Host "    v$ProductVersion" -ForegroundColor DarkGray
    Write-Host ""
}

function Show-YulieHelp {
    Write-Host @"
YulieAI - Asisten AI Internal Yulie Sekuritas

Usage:
  yulieai
  yulieai "jelaskan error ini"
  yulieai --chat-mode code
  yulieai --approval-mode auto_edit
  yulieai --yolo
  yulieai doctor
  yulieai version

Shell commands:
  /help      Show help
  /clear     Clear screen
  /exit      Exit YulieAI

Common options are forwarded to the YulieAI engine:
  --chat-mode ask|plan|code|advanced
  --approval-mode default|auto_edit|yolo
  --yolo
  --sandbox
  --include-directories <path>
  --output-format text|json|stream-json
  --resume latest

Diagnostics:
  yulieai doctor

Advanced diagnostics:
  yulieai engine --help
  yulieai lite
"@
}

function ConvertFrom-DpapiSecret {
    param([Parameter(Mandatory = $true)][string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "YulieAI credential is not installed. Re-run the YulieAI installer."
    }

    $encrypted = Get-Content -LiteralPath $Path -Raw
    $secure = ConvertTo-SecureString -String $encrypted
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    }
    finally {
        if ($ptr -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
        }
    }
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

function Get-BundledNodeRoot {
    return Join-Path $InstallRoot "nodejs"
}

function Resolve-NodeRuntime {
    $bundled = Join-Path (Get-BundledNodeRoot) "node.exe"
    if (Test-Path -LiteralPath $bundled) {
        return $bundled
    }

    $cmd = Get-CommandSource -Names @("node.exe", "node")
    if (-not $cmd) {
        throw "Node.js is not installed or not available in PATH. Install Node.js 22.15+ and re-run the YulieAI installer."
    }

    return $cmd
}

function Resolve-NpmRuntime {
    $bundled = Join-Path (Get-BundledNodeRoot) "npm.cmd"
    if (Test-Path -LiteralPath $bundled) {
        return $bundled
    }

    return Get-CommandSource -Names @("npm.cmd", "npm.exe", "npm")
}

function Resolve-YulieEngineScript {
    if ($env:YULIEAI_ENGINE_JS) {
        if (Test-Path -LiteralPath $env:YULIEAI_ENGINE_JS) {
            return $env:YULIEAI_ENGINE_JS
        }
        throw "YULIEAI_ENGINE_JS is set but does not exist: $env:YULIEAI_ENGINE_JS"
    }

    $npm = Resolve-NpmRuntime
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

    throw "YulieAI engine bundle was not found. Re-run the YulieAI installer."
}

function Test-Argument {
    param(
        [string[]] $Arguments,
        [string] $Name
    )

    foreach ($arg in $Arguments) {
        if ($arg -eq $Name -or $arg.StartsWith("$Name=")) {
            return $true
        }
    }
    return $false
}

function Add-CleanOutputDefaults {
    param([string[]] $Arguments)

    $result = @()
    if ($Arguments) {
        $result += $Arguments
    }

    if (-not (Test-Argument -Arguments $result -Name "--output-format")) {
        $result += @("--output-format", "text")
    }

    if (-not (Test-Argument -Arguments $result -Name "--hide-intermediary-output")) {
        $result += "--hide-intermediary-output"
    }

    return $result
}

function Test-ContainsPromptText {
    param([string[]] $Arguments)

    if (-not $Arguments) {
        return $false
    }

    $valueOptions = @(
        "--chat-mode",
        "--model",
        "-m",
        "--prompt",
        "-p",
        "--prompt-interactive",
        "-i",
        "--approval-mode",
        "--resume",
        "-r",
        "--delete-session",
        "--include-directories",
        "--allowed-mcp-server-names",
        "--allowed-tools",
        "--output-format",
        "-o",
        "--max-coins",
        "--instance-id",
        "--team-id"
    )

    $expectValue = $false
    foreach ($arg in $Arguments) {
        if ($expectValue) {
            $expectValue = $false
            continue
        }

        if ($arg.StartsWith("--") -and $arg.Contains("=")) {
            continue
        }

        if ($valueOptions -contains $arg) {
            $expectValue = $true
            continue
        }

        if ($arg.StartsWith("-")) {
            continue
        }

        return $true
    }

    return $false
}

function Invoke-YulieEngine {
    param([string[]] $Arguments)

    $node = Resolve-NodeRuntime
    $engineScript = Resolve-YulieEngineScript
    $apiKey = ConvertFrom-DpapiSecret -Path $SecureKeyPath

    $oldLocation = (Get-Location).Path
    $oldBobKey = $env:BOBSHELL_API_KEY
    $oldUserProfile = $env:USERPROFILE
    $oldHome = $env:HOME
    $oldCli = $env:BOBSHELL_CLI
    $oldErrorActionPreference = $ErrorActionPreference

    try {
        $safeWorkingDirectory = Resolve-SafeWorkingDirectory -RealUserProfile $oldUserProfile
        if ($safeWorkingDirectory -and (Test-Path -LiteralPath $safeWorkingDirectory)) {
            Set-Location -LiteralPath $safeWorkingDirectory
        }

        $env:BOBSHELL_API_KEY = $apiKey
        $env:USERPROFILE = $ProfileRoot
        $env:HOME = $ProfileRoot
        $env:BOBSHELL_CLI = "yulieai"

        $baseArgs = @("--auth-method", "api-key")
        if (-not (Test-Argument -Arguments $Arguments -Name "--chat-mode")) {
            $baseArgs += @("--chat-mode", "yulieai")
        }

        $ErrorActionPreference = "Continue"
        & $node $engineScript @baseArgs @Arguments 2>&1 | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) {
                $line = $_.ToString()
                if ($line -notmatch '^(Authenticated via|Instance and team selected successfully|Initializing\.{0,3}|Debug Console|\[WARN\] Skipping unreadable directory:)') {
                    Write-Host $line -ForegroundColor Red
                }
            }
            else {
                $line = [string] $_
                if ($line -notmatch '^(Authenticated via|Instance and team selected successfully|Initializing\.{0,3}|Debug Console|\[WARN\] Skipping unreadable directory:)') {
                    Write-Host $line
                }
            }
        }
        $script:YulieLastExitCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
    }
    finally {
        $ErrorActionPreference = $oldErrorActionPreference
        if ($oldLocation -and (Test-Path -LiteralPath $oldLocation)) { Set-Location -LiteralPath $oldLocation }
        if ($null -eq $oldBobKey) { Remove-Item Env:\BOBSHELL_API_KEY -ErrorAction SilentlyContinue } else { $env:BOBSHELL_API_KEY = $oldBobKey }
        if ($null -eq $oldUserProfile) { Remove-Item Env:\USERPROFILE -ErrorAction SilentlyContinue } else { $env:USERPROFILE = $oldUserProfile }
        if ($null -eq $oldHome) { Remove-Item Env:\HOME -ErrorAction SilentlyContinue } else { $env:HOME = $oldHome }
        if ($null -eq $oldCli) { Remove-Item Env:\BOBSHELL_CLI -ErrorAction SilentlyContinue } else { $env:BOBSHELL_CLI = $oldCli }
    }
}

function Invoke-YuliePrompt {
    param(
        [string[]] $EngineArgs,
        [string] $Prompt,
        [switch] $ResumeLatest
    )

    $args = Add-CleanOutputDefaults -Arguments $EngineArgs
    if ($ResumeLatest -and -not (Test-Argument -Arguments $args -Name "--resume")) {
        $args += @("--resume", "latest")
    }

    $identity = "Kamu adalah YulieAI, asisten AI internal Yulie Sekuritas. Gunakan bahasa Indonesia kecuali user meminta bahasa lain. Jika ditanya model apa, jawab bahwa kamu adalah YulieAI."
    $args += "$identity`n`nUser: $Prompt"

    Invoke-YulieEngine -Arguments $args
    return $script:YulieLastExitCode
}

function Invoke-YulieShell {
    param([string[]] $EngineArgs)

    Write-YulieBanner -EngineArgs $EngineArgs
    Write-Host "Tip: ketik bebas seperti chat. Gunakan /help, /clear, atau /exit." -ForegroundColor DarkGray
    Write-Host ""

    $hasSession = $false
    while ($true) {
        Write-Host -NoNewline "> " -ForegroundColor Cyan
        $prompt = [Console]::ReadLine()
        if ($null -eq $prompt) {
            Write-Host ""
            break
        }

        $prompt = $prompt.Trim()
        if ($prompt.Length -eq 0) {
            continue
        }

        if ($prompt -ieq "exit" -or $prompt -ieq "quit" -or $prompt -ieq "keluar" -or $prompt -ieq "/exit" -or $prompt -ieq "/quit") {
            break
        }

        if ($prompt -ieq "help" -or $prompt -ieq "?" -or $prompt -ieq "/help") {
            Show-YulieHelp
            continue
        }

        if ($prompt -ieq "clear" -or $prompt -ieq "cls" -or $prompt -ieq "/clear") {
            Clear-Host
            Write-YulieBanner -EngineArgs $EngineArgs
            continue
        }

        if ($prompt -match '(?i)^yulieai\s+engine\b' -or $prompt -ieq "engine") {
            Write-Host "Mode engine hanya untuk debugging. Dari terminal biasa jalankan: yulieai engine --help" -ForegroundColor DarkGray
            Write-Host ""
            continue
        }

        if ($prompt -match '(?i)^yulieai\s+(.+)$') {
            $prompt = $Matches[1].Trim()
        }

        Write-Host ""
        Write-Host "YulieAI sedang memproses..." -ForegroundColor DarkGray
        Write-Host ""
        $code = Invoke-YuliePrompt -EngineArgs $EngineArgs -Prompt $prompt -ResumeLatest:$hasSession
        $hasSession = $true

        if ($code -ne 0) {
            Write-Host ""
            Write-Host "YulieAI selesai dengan error code $code." -ForegroundColor Yellow
        }

        Write-Host ""
    }
}

function Invoke-Doctor {
    Write-Host "YulieAI diagnostics" -ForegroundColor Cyan
    Write-Host "Version: $ProductVersion"
    Write-Host "Profile: $ProfileRoot"
    Write-Host "Credential protected: $(Test-Path -LiteralPath $SecureKeyPath)"

    try {
        $node = Resolve-NodeRuntime
        $engine = Resolve-YulieEngineScript
        Write-Host "Engine: installed"
        Write-Host "Node path: $node"
        Write-Host "Engine path: $engine"
    }
    catch {
        Write-Host "Engine: missing" -ForegroundColor Red
        Write-Host $_.Exception.Message
        exit 1
    }

    try {
        $null = ConvertFrom-DpapiSecret -Path $SecureKeyPath
        Write-Host "Credential: installed"
    }
    catch {
        Write-Host "Credential: missing or unreadable" -ForegroundColor Red
        Write-Host $_.Exception.Message
        exit 1
    }

    Write-Host "Status: ready" -ForegroundColor Green
}

if (@($RemainingArgs).Count -eq 0) {
    Write-YulieSplash
    Invoke-YulieEngine -Arguments @("--hide-intermediary-output")
    exit $script:YulieLastExitCode
}

$first = $RemainingArgs[0].ToLowerInvariant()
switch ($first) {
    "help" {
        Show-YulieHelp
        exit 0
    }
    "--help" {
        Show-YulieHelp
        exit 0
    }
    "-h" {
        Show-YulieHelp
        exit 0
    }
    "version" {
        Write-Host "$ProductName $ProductVersion"
        exit 0
    }
    "--version" {
        Write-Host "$ProductName $ProductVersion"
        exit 0
    }
    "doctor" {
        Invoke-Doctor
        exit 0
    }
    "engine" {
        $engineArgs = if (@($RemainingArgs).Count -gt 1) { $RemainingArgs[1..(@($RemainingArgs).Count - 1)] } else { @() }
        Invoke-YulieEngine -Arguments $engineArgs
        exit $script:YulieLastExitCode
    }
    "lite" {
        $liteArgs = if (@($RemainingArgs).Count -gt 1) { $RemainingArgs[1..(@($RemainingArgs).Count - 1)] } else { @() }
        Invoke-YulieShell -EngineArgs $liteArgs
        exit 0
    }
    default {
        if (Test-ContainsPromptText -Arguments $RemainingArgs) {
            Write-YulieSplash
            Invoke-YulieEngine -Arguments (Add-CleanOutputDefaults -Arguments $RemainingArgs)
            exit $script:YulieLastExitCode
        }

        $interactiveArgs = @()
        if ($RemainingArgs) {
            $interactiveArgs += $RemainingArgs
        }
        if (-not (Test-Argument -Arguments $interactiveArgs -Name "--hide-intermediary-output")) {
            $interactiveArgs += "--hide-intermediary-output"
        }
        Write-YulieSplash
        Invoke-YulieEngine -Arguments $interactiveArgs
        exit $script:YulieLastExitCode
    }
}
