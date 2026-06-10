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

$shimRoot = Join-Path $installRoot 'bin'
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (-not [string]::IsNullOrWhiteSpace($userPath)) {
  $normalizedShimRoot = [System.IO.Path]::GetFullPath($shimRoot).TrimEnd('\')
  $pathEntries = $userPath -split ';' | Where-Object {
    if ([string]::IsNullOrWhiteSpace($_)) { return $false }
    try {
      [System.IO.Path]::GetFullPath($_).TrimEnd('\') -ne $normalizedShimRoot
    } catch {
      $_ -ne $shimRoot
    }
  }
  [Environment]::SetEnvironmentVariable('Path', ($pathEntries -join ';'), 'User')
}

if (Test-Path $installRoot) {
  Remove-Item -Path $installRoot -Recurse -Force
}

Write-Host 'Dialex removed.'

