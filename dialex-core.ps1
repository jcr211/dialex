Set-StrictMode -Version Latest

function Get-DialexAssetsRoot {
  param([string] $Root)

  $assets = Join-Path $Root 'assets'
  if (-not (Test-Path $assets)) {
    throw "Dialex assets folder not found: $assets"
  }

  return $assets
}

function Get-DialexStateRoot {
  $root = Join-Path $env:USERPROFILE '.codex\dialex'
  New-Item -ItemType Directory -Force -Path $root | Out-Null
  return $root
}

function Get-DialexSoundMap {
  param([string] $Root)

  $assets = Get-DialexAssetsRoot -Root $Root
  return @{
    launch = Join-Path $assets 'launch.wav'
    exec = Join-Path $assets 'exec.wav'
    review = Join-Path $assets 'review.wav'
    fork = Join-Path $assets 'fork.wav'
    resume = Join-Path $assets 'resume.wav'
    success = Join-Path $assets 'success.wav'
    error = Join-Path $assets 'error.wav'
    apply = Join-Path $assets 'apply.wav'
    prompt = Join-Path $assets 'prompt.wav'
    loading = Join-Path $assets 'loading.wav'
    action = Join-Path $assets 'action.wav'
    done = Join-Path $assets 'done.wav'
  }
}

function Invoke-DialexSound {
  param(
    [string] $Root,
    [string] $Name
  )

  if ($env:CODEX_AUDIO_DISABLED -eq '1') {
    return
  }

  $sounds = Get-DialexSoundMap -Root $Root
  $path = $sounds[$Name]
  if (-not $path -or -not (Test-Path $path)) {
    return
  }

  try {
    $player = [System.Media.SoundPlayer]::new($path)
    $player.PlaySync()
  } catch {
    # Audio should never block Codex execution.
  }
}

function Stop-DialexAmbient {
  $stateRoot = Get-DialexStateRoot
  $pidFile = Join-Path $stateRoot 'ambient.pid'

  if (-not (Test-Path $pidFile)) {
    return
  }

  try {
    $ambientPid = [int](Get-Content -Path $pidFile -Raw)
    $proc = Get-Process -Id $ambientPid -ErrorAction SilentlyContinue
    if ($proc) {
      Stop-Process -Id $ambientPid -Force -ErrorAction SilentlyContinue
    }
  } catch {
  }

  Remove-Item -Path $pidFile -Force -ErrorAction SilentlyContinue
}

function Start-DialexAmbient {
  param([string] $Root)

  if ($env:CODEX_AUDIO_DISABLED -eq '1') {
    return
  }

  Stop-DialexAmbient

  $sounds = Get-DialexSoundMap -Root $Root
  $loading = $sounds['loading']
  if (-not (Test-Path $loading)) {
    return
  }

  $stateRoot = Get-DialexStateRoot
  $pidFile = Join-Path $stateRoot 'ambient.pid'
  $ps = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
  if (-not $ps) {
    $ps = (Get-Command powershell).Source
  }

  $loopScript = @"
`$player = [System.Media.SoundPlayer]::new('$loading')
while (`$true) {
  try {
    `$player.PlaySync()
    Start-Sleep -Milliseconds 120
  } catch {
    Start-Sleep -Milliseconds 250
  }
}
"@

  $proc = Start-Process -FilePath $ps -ArgumentList @('-NoProfile', '-Command', $loopScript) -PassThru -WindowStyle Hidden
  Set-Content -Path $pidFile -Value $proc.Id -Encoding ascii
}

function Invoke-DialexHookEvent {
  param(
    [string] $Root,
    [string] $EventName
  )

  switch ($EventName) {
    'prompt-submit' {
      Stop-DialexAmbient
      Invoke-DialexSound -Root $Root -Name 'prompt'
    }
    'thinking-start' {
      Start-DialexAmbient -Root $Root
    }
    'thinking-stop' {
      Stop-DialexAmbient
    }
    'tool-action' {
      Stop-DialexAmbient
      Invoke-DialexSound -Root $Root -Name 'action'
    }
    'turn-complete' {
      Stop-DialexAmbient
      Invoke-DialexSound -Root $Root -Name 'done'
    }
    'error' {
      Stop-DialexAmbient
      Invoke-DialexSound -Root $Root -Name 'error'
    }
    default {
    }
  }
}
