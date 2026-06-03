@echo off
setlocal
title YulieAI - Yulie Sekuritas Indonesia Tbk
set "YULIEAI_SCRIPT=%~dp0yulieai-core.ps1"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$OutputEncoding=[Console]::OutputEncoding=[Console]::InputEncoding=[Text.UTF8Encoding]::new($false); $host.UI.RawUI.WindowTitle='YulieAI - Yulie Sekuritas Indonesia Tbk'; $env:TERM='xterm-256color'; $env:FORCE_COLOR='1'; $env:NO_COLOR=$null; $script = Get-Content -LiteralPath '%YULIEAI_SCRIPT%' -Raw; $block = [ScriptBlock]::Create($script); & $block @args" %*
exit /b %ERRORLEVEL%
