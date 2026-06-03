# YulieAI Windows

Windows-only internal CLI wrapper for YulieAI.

YulieAI installs a branded command named `yulieai`, stores the provided API key with Windows DPAPI for the current user, creates an isolated YulieAI profile, and installs the underlying engine using IBM's Windows installer command.

## Install From An Extracted Package

Run PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -AcceptIbmLicense
```

Then open a new terminal:

```powershell
yulieai doctor
yulieai
```

## Host From PC Admin

Serve `yulieai-windows.zip` from a local web server on the admin PC.

On a user PC:

```powershell
irm "http://PC-ADMIN:8787/install-yulieai.ps1" | iex
```

Or download the zip manually, extract it, and run `install.ps1`.

## Common Commands

```powershell
yulieai
yulieai "ringkas file laporan.pdf"
yulieai --chat-mode code
yulieai --approval-mode auto_edit
yulieai --yolo
yulieai engine --help
yulieai lite
```

By default, `yulieai` opens the full interactive YulieAI terminal interface. Use `yulieai lite` for the simpler wrapper shell, or `yulieai engine ...` only when raw engine troubleshooting is needed.

## Notes

- This private repository may include the internal credential file at `credentials/yulieai.json` for admin backup/distribution.
- Keep this repository private. If it ever becomes public or access is shared incorrectly, revoke the API key and replace it.
- During install, the raw key is converted into a per-user DPAPI secret at `%LOCALAPPDATA%\YulieAI\secure\bobshell_api_key.dpapi`.
- The raw credential is not copied into the installed application directory.
- The YulieAI profile is isolated at `%LOCALAPPDATA%\YulieAI\profile`.
- The installer applies a local branding patch to the Windows engine bundle after installation. If an engine update overwrites it, re-run `install.ps1`.
- The installer uses the official Windows engine installation flow:

```powershell
powershell -ep Bypass 'irm -Uri "https://bob.ibm.com/download/bobshell.ps1" | iex'
```
