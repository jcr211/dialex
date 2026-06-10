param()

$ErrorActionPreference = 'Stop'

$sourceRoot = $PSScriptRoot
$installRoot = Join-Path $env:USERPROFILE '.codex\dialex'
$profilePath = $PROFILE.CurrentUserCurrentHost
$markerStart = '# Dialex start'
$markerEnd = '# Dialex end'

New-Item -ItemType Directory -Force -Path $installRoot, (Join-Path $installRoot 'assets'), (Join-Path $installRoot 'bin') | Out-Null
Copy-Item -Path (Join-Path $sourceRoot 'codex-audio.ps1') -Destination $installRoot -Force
Copy-Item -Path (Join-Path $sourceRoot 'dialex-core.ps1') -Destination $installRoot -Force
Copy-Item -Path (Join-Path $sourceRoot 'dialex-hook.ps1') -Destination $installRoot -Force
Copy-Item -Path (Join-Path $sourceRoot 'dialex-tailer.ps1') -Destination $installRoot -Force
Copy-Item -Path (Join-Path $sourceRoot 'dialex-watcher.ps1') -Destination $installRoot -Force
Copy-Item -Path (Join-Path $sourceRoot 'assets\*') -Destination (Join-Path $installRoot 'assets') -Force
if (Test-Path (Join-Path $sourceRoot 'bin')) {
  Copy-Item -Path (Join-Path $sourceRoot 'bin\*') -Destination (Join-Path $installRoot 'bin') -Force
}

$shimRoot = Join-Path $installRoot 'bin'

$snippet = @'
# Dialex start
$script:DialexRoot = Join-Path $env:USERPROFILE '.codex\dialex'
$script:DialexAudioScript = Join-Path $script:DialexRoot 'codex-audio.ps1'
if (Test-Path $script:DialexAudioScript) {
  $script:DialexNativeCodex = Join-Path $env:APPDATA 'npm\codex.cmd'

  function global:codex {
    param(
      [Parameter(ValueFromRemainingArguments = $true)]
      [string[]] $CliArgs
    )

    & $script:DialexAudioScript @CliArgs
  }

  function global:codex-native {
    param(
      [Parameter(ValueFromRemainingArguments = $true)]
      [string[]] $CliArgs
    )

    & $script:DialexNativeCodex @CliArgs
  }

  . (Join-Path $script:DialexRoot 'dialex-core.ps1')
  Start-DialexWatcher -Root $script:DialexRoot
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

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$pathEntries = if ([string]::IsNullOrWhiteSpace($userPath)) { @() } else { $userPath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } }
$normalizedShimRoot = [System.IO.Path]::GetFullPath($shimRoot).TrimEnd('\')
$pathEntries = @($pathEntries | Where-Object {
  try { [System.IO.Path]::GetFullPath($_).TrimEnd('\') -ne $normalizedShimRoot } catch { $_ -ne $shimRoot }
})
$npmRoot = Join-Path $env:APPDATA 'npm'
$normalizedNpmRoot = [System.IO.Path]::GetFullPath($npmRoot).TrimEnd('\')
$newPathEntries = [System.Collections.Generic.List[string]]::new()
$insertedShim = $false
foreach ($entry in $pathEntries) {
  try {
    $normalizedEntry = [System.IO.Path]::GetFullPath($entry).TrimEnd('\')
  } catch {
    $normalizedEntry = $entry
  }

  if (-not $insertedShim -and $normalizedEntry -eq $normalizedNpmRoot) {
    $newPathEntries.Add($shimRoot)
    $insertedShim = $true
  }
  $newPathEntries.Add($entry)
}
if (-not $insertedShim) {
  $newPathEntries.Insert(0, $shimRoot)
}
[Environment]::SetEnvironmentVariable('Path', ($newPathEntries -join ';'), 'User')

Write-Host "Installed Dialex to $installRoot"
Write-Host "Updated profile: $profilePath"
Write-Host "Added Dialex shim to user PATH before npm: $shimRoot"
