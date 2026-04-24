param()

$ErrorActionPreference = 'Stop'

$sourceRoot = $PSScriptRoot
$installRoot = Join-Path $env:USERPROFILE '.codex\dialex'
$profilePath = $PROFILE.CurrentUserCurrentHost
$markerStart = '# Dialex start'
$markerEnd = '# Dialex end'

New-Item -ItemType Directory -Force -Path $installRoot, (Join-Path $installRoot 'assets') | Out-Null
Copy-Item -Path (Join-Path $sourceRoot 'codex-audio.ps1') -Destination $installRoot -Force
Copy-Item -Path (Join-Path $sourceRoot 'dialex-core.ps1') -Destination $installRoot -Force
Copy-Item -Path (Join-Path $sourceRoot 'dialex-hook.ps1') -Destination $installRoot -Force
Copy-Item -Path (Join-Path $sourceRoot 'dialex-tailer.ps1') -Destination $installRoot -Force
Copy-Item -Path (Join-Path $sourceRoot 'assets\*') -Destination (Join-Path $installRoot 'assets') -Force

$snippet = @'
# Dialex start
$script:DialexAudioScript = Join-Path $env:USERPROFILE '.codex\dialex\codex-audio.ps1'
if (Test-Path $script:DialexAudioScript) {
  function global:codex {
    param(
      [Parameter(ValueFromRemainingArguments = $true)]
      [string[]] $Args
    )

    & $script:DialexAudioScript @Args
  }

  function global:codex-native {
    param(
      [Parameter(ValueFromRemainingArguments = $true)]
      [string[]] $Args
    )

    & (Join-Path $env:APPDATA 'npm\codex.cmd') @Args
  }
}
# Dialex end
'@

$profileDir = Split-Path -Parent $profilePath
New-Item -ItemType Directory -Force -Path $profileDir | Out-Null

if (Test-Path $profilePath) {
  $content = Get-Content -Path $profilePath -Raw
  if ($content -match [regex]::Escape($markerStart) -and $content -match [regex]::Escape($markerEnd)) {
    $pattern = '(?s)# Dialex start.*?# Dialex end\r?\n?'
    $content = [regex]::Replace($content, $pattern, '')
  }
  $content = $content.TrimEnd()
  if ($content.Length -gt 0) {
    $content += "`r`n`r`n"
  }
  $content += $snippet + "`r`n"
} else {
  $content = $snippet + "`r`n"
}

Set-Content -Path $profilePath -Value $content -Encoding utf8

Write-Host "Installed Dialex to $installRoot"
Write-Host "Updated profile: $profilePath"
