# Dialex no-profile PowerShell shim for Codex CLI.
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
& (Join-Path $root 'codex-audio.ps1') @args
exit $LASTEXITCODE
