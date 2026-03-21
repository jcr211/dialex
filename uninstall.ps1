param()

$ErrorActionPreference = 'Stop'

$installRoot = Join-Path $env:USERPROFILE '.codex\dialex'
$profilePath = $PROFILE.CurrentUserCurrentHost

if (Test-Path $profilePath) {
  $content = Get-Content -Path $profilePath -Raw
  $pattern = '(?s)# Dialex start.*?# Dialex end\r?\n?'
  $content = [regex]::Replace($content, $pattern, '')
  Set-Content -Path $profilePath -Value $content.TrimEnd() -Encoding utf8
}

if (Test-Path $installRoot) {
  Remove-Item -Path $installRoot -Recurse -Force
}

Write-Host 'Dialex removed.'

