param(
  [Parameter(Mandatory = $true)]
  [string] $Root
)

$ErrorActionPreference = 'Stop'
. (Join-Path $Root 'dialex-core.ps1')

if (Test-DialexMuted) { return }

$sessionsRoot = Join-Path $env:USERPROFILE '.codex\sessions'
if (-not (Test-Path $sessionsRoot)) {
  New-Item -ItemType Directory -Force -Path $sessionsRoot | Out-Null
}

$logPath = Join-Path (Get-DialexStateRoot) 'watcher.log'

function Write-WatcherLog {
  param([string] $Message)
  try {
    $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
    Add-Content -Path $logPath -Value "$stamp $Message" -Encoding utf8 -ErrorAction SilentlyContinue
  } catch {}
}

Write-WatcherLog "watcher start root=$Root pid=$PID"

$soundMap = Get-DialexSoundMap -Root $Root
$lastPlayed = @{}
$cooldownMs = 200
$cueCooldowns = @{ loading = 8000 }
$script:DialexPlayers = @{}
$script:ambientActive = $false

function Should-PlayCue {
  param([string] $Name)
  $now = [DateTime]::UtcNow
  $cd = if ($cueCooldowns.ContainsKey($Name)) { $cueCooldowns[$Name] } else { $cooldownMs }
  if ($lastPlayed.ContainsKey($Name)) {
    $elapsed = ($now - $lastPlayed[$Name]).TotalMilliseconds
    if ($elapsed -lt $cd) { return $false }
  }
  $lastPlayed[$Name] = $now
  return $true
}

function Play-Cue {
  param([string] $Name)
  if (Test-DialexMuted) { return }
  if (-not (Should-PlayCue -Name $Name)) { return }
  $path = $soundMap[$Name]
  if (-not $path -or -not (Test-Path $path)) { return }
  try {
    if (-not $script:DialexPlayers.ContainsKey($Name)) {
      $p = [System.Media.SoundPlayer]::new($path)
      $p.Load()
      $script:DialexPlayers[$Name] = $p
    }
    $script:DialexPlayers[$Name].Play()
    Write-WatcherLog "cue $Name"
  } catch {
    Write-WatcherLog "cue $Name failed: $($_.Exception.Message)"
  }
}

function Handle-RolloutEvent {
  param([string] $Line)
  if ([string]::IsNullOrWhiteSpace($Line)) { return }
  try {
    $event = $Line | ConvertFrom-Json -Depth 24 -ErrorAction Stop
  } catch { return }

  $rootType = $event.PSObject.Properties['type']
  if (-not $rootType) { return }

  switch ($event.type) {
    'event_msg' {
      $payload = $event.payload
      if (-not $payload) { return }
      if ($script:ambientActive -and $payload.type -ne 'token_count') {
        Stop-DialexAmbient
        $script:ambientActive = $false
        Write-WatcherLog "ambient stop"
      }
      switch ($payload.type) {
        'task_started'          { Play-Cue -Name 'launch' }
        'user_message'          { Play-Cue -Name 'prompt' }
        'agent_message'         { Play-Cue -Name 'review' }
        'mcp_tool_call_end'     { Play-Cue -Name 'action' }
        'patch_apply_end' {
          if ($payload.success -eq $true) { Play-Cue -Name 'apply' }
          else { Play-Cue -Name 'error' }
        }
        'exec_command_end' {
          $exit = 0
          if ($payload.PSObject.Properties['exit_code'] -and $null -ne $payload.exit_code) {
            $exit = [int]$payload.exit_code
          }
          if ($exit -eq 0) { Play-Cue -Name 'success' }
          else { Play-Cue -Name 'error' }
        }
        'task_complete'            { Play-Cue -Name 'done' }
        'collab_agent_spawn_end'   { Play-Cue -Name 'fork' }
        'collab_close_end'         { Play-Cue -Name 'resume' }
        'turn_aborted'             { Play-Cue -Name 'error' }
      }
    }
    'response_item' {
      $payload = $event.payload
      if (-not $payload) { return }

      if ($payload.type -eq 'reasoning') {
        if (-not $script:ambientActive) {
          Start-DialexAmbient -Root $Root
          $script:ambientActive = $true
          Write-WatcherLog "ambient start"
        }
        return
      }

      if ($script:ambientActive) {
        Stop-DialexAmbient
        $script:ambientActive = $false
        Write-WatcherLog "ambient stop"
      }

      switch ($payload.type) {
        'function_call' {
          switch ($payload.name) {
            'shell_command' { Play-Cue -Name 'exec' }
            'execute_sql'   { Play-Cue -Name 'exec' }
            'apply_patch'   { Play-Cue -Name 'apply' }
            'update_plan'   { Play-Cue -Name 'action' }
            'spawn_agent'   { Play-Cue -Name 'fork' }
            'wait_agent'    { Play-Cue -Name 'resume' }
            'close_agent'   { Play-Cue -Name 'resume' }
            default {
              if ($payload.name -match '(?i)write|edit|create|delete|push') {
                Play-Cue -Name 'apply'
              } elseif ($payload.name -match '(?i)read|search|list|get|query|fetch') {
                Play-Cue -Name 'action'
              } elseif ($payload.name -match '(?i)pull_request|review') {
                Play-Cue -Name 'review'
              }
            }
          }
        }
        'function_call_output' {
          if ($payload.output -match '^Exit code:\s*(\d+)') {
            $code = [int]$Matches[1]
            if ($code -eq 0) { Play-Cue -Name 'success' }
            else { Play-Cue -Name 'error' }
          }
        }
        'custom_tool_call' {
          if ($payload.name -eq 'apply_patch') { Play-Cue -Name 'apply' }
        }
        'web_search_call'  { Play-Cue -Name 'action' }
        'tool_search_call' { Play-Cue -Name 'action' }
      }
    }
  }
}

$tracked = @{}
$knownFiles = @{}
$startUtc = [DateTime]::UtcNow

function Scan-NewRollouts {
  $dir = Join-Path $sessionsRoot (Get-Date -Format 'yyyy/MM/dd')
  if (-not (Test-Path $dir)) { return }

  $files = Get-ChildItem -Path $dir -Filter 'rollout-*.jsonl' -File -ErrorAction SilentlyContinue
  foreach ($f in $files) {
    if ($knownFiles.ContainsKey($f.FullName)) { continue }
    $knownFiles[$f.FullName] = $true

    # Skip files that were inactive before the watcher started.
    if ($f.CreationTimeUtc -lt $startUtc.AddSeconds(-60) -and
        $f.LastWriteTimeUtc -lt $startUtc.AddSeconds(-60)) {
      continue
    }

    try {
      $stream = [System.IO.FileStream]::new(
        $f.FullName,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::ReadWrite
      )
      $stream.Seek(0, [System.IO.SeekOrigin]::End) | Out-Null
      $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8)
      $tracked[$f.FullName] = @{
        Reader       = $reader
        Stream       = $stream
        LastActivity = [DateTime]::UtcNow
      }
      Write-WatcherLog "tracking $($f.Name)"
    } catch {
      Write-WatcherLog "open failed $($f.Name): $($_.Exception.Message)"
    }
  }
}

try {
  while ($true) {
    Scan-NewRollouts

    $anyProgress = $false
    $staleKeys = @()

    foreach ($key in @($tracked.Keys)) {
      $info = $tracked[$key]
      if ($null -eq $info.Reader) { $staleKeys += $key; continue }

      try {
        $line = $info.Reader.ReadLine()
        while ($null -ne $line) {
          Handle-RolloutEvent -Line $line
          $info.LastActivity = [DateTime]::UtcNow
          $anyProgress = $true
          $line = $info.Reader.ReadLine()
        }
      } catch {
        $staleKeys += $key
        continue
      }

      if (([DateTime]::UtcNow - $info.LastActivity).TotalSeconds -gt 600) {
        $staleKeys += $key
      }
    }

    foreach ($key in $staleKeys) {
      try {
        $tracked[$key].Reader.Dispose()
        $tracked[$key].Stream.Dispose()
      } catch {}
      $tracked.Remove($key)
      Write-WatcherLog "untracked $([System.IO.Path]::GetFileName($key))"
    }

    if (-not $anyProgress) {
      Start-Sleep -Milliseconds 500
    }
  }
} finally {
  foreach ($key in @($tracked.Keys)) {
    try {
      $tracked[$key].Reader.Dispose()
      $tracked[$key].Stream.Dispose()
    } catch {}
  }
  if ($script:ambientActive) { Stop-DialexAmbient }
  Write-WatcherLog "watcher exit"
}
