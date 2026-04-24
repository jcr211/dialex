param(
  [Parameter(Mandatory = $true)]
  [string] $Root,
  [Parameter(Mandatory = $true)]
  [datetime] $StartTime,
  [int] $MaxWaitSeconds = 30
)

$ErrorActionPreference = 'Stop'
. (Join-Path $Root 'dialex-core.ps1')

if (Test-DialexMuted) { return }

$sessionsRoot = Join-Path $env:USERPROFILE '.codex\sessions'
if (-not (Test-Path $sessionsRoot)) {
  return
}

$soundMap = Get-DialexSoundMap -Root $Root
$lastPlayed = @{}
$cooldownMs = 200
$script:DialexPlayers = @{}

$logPath = Join-Path (Get-DialexStateRoot) 'tailer.log'
function Write-TailerLog {
  param([string] $Message)
  try {
    $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
    Add-Content -Path $logPath -Value "$stamp $Message" -Encoding utf8 -ErrorAction SilentlyContinue
  } catch {}
}
Write-TailerLog "tailer start root=$Root startTime=$($StartTime.ToString('o'))"

function Should-PlayCue {
  param([string] $Name)

  $now = [DateTime]::UtcNow
  if ($lastPlayed.ContainsKey($Name)) {
    $elapsed = ($now - $lastPlayed[$Name]).TotalMilliseconds
    if ($elapsed -lt $cooldownMs) {
      return $false
    }
  }
  $lastPlayed[$Name] = $now
  return $true
}

function Play-Cue {
  param([string] $Name)

  if (Test-DialexMuted) { return }
  if (-not (Should-PlayCue -Name $Name)) {
    return
  }
  $path = $soundMap[$Name]
  if (-not $path -or -not (Test-Path $path)) {
    return
  }
  try {
    if (-not $script:DialexPlayers.ContainsKey($Name)) {
      $p = [System.Media.SoundPlayer]::new($path)
      $p.Load()
      $script:DialexPlayers[$Name] = $p
    }
    $script:DialexPlayers[$Name].Play()
    Write-TailerLog "cue $Name"
  } catch {
    Write-TailerLog "cue $Name failed: $($_.Exception.Message)"
  }
}

$startUtc = $StartTime.ToUniversalTime()

function Find-LatestRollout {
  $candidates = @()
  $today = Get-Date -Format 'yyyy/MM/dd'
  $yesterday = (Get-Date).AddDays(-1).ToString('yyyy/MM/dd')

  foreach ($rel in @($today, $yesterday)) {
    $dir = Join-Path $sessionsRoot $rel
    if (Test-Path $dir) {
      $candidates += Get-ChildItem -Path $dir -Filter 'rollout-*.jsonl' -File -ErrorAction SilentlyContinue
    }
  }

  if ($candidates.Count -eq 0) {
    return $null
  }

  $cutoff = $startUtc.AddSeconds(-2)
  $newest = $candidates |
    Where-Object { $_.LastWriteTimeUtc -ge $cutoff } |
    Sort-Object LastWriteTimeUtc -Descending |
    Select-Object -First 1

  return $newest
}

# Wait for a rollout file to appear.
$rollout = $null
$waitDeadline = (Get-Date).AddSeconds($MaxWaitSeconds)
while (-not $rollout -and (Get-Date) -lt $waitDeadline) {
  $rollout = Find-LatestRollout
  if (-not $rollout) {
    Start-Sleep -Milliseconds 250
  }
}

if (-not $rollout) {
  Write-TailerLog "no rollout file found within ${MaxWaitSeconds}s, exiting"
  return
}

Write-TailerLog "tailing $($rollout.FullName)"

function Handle-Event {
  param([string] $Line)

  if ([string]::IsNullOrWhiteSpace($Line)) {
    return
  }

  try {
    $event = $Line | ConvertFrom-Json -Depth 24 -ErrorAction Stop
  } catch {
    return
  }

  $rootType = $event.PSObject.Properties['type']
  if (-not $rootType) {
    return
  }

  switch ($event.type) {
    'event_msg' {
      $payload = $event.payload
      if (-not $payload) { return }
      switch ($payload.type) {
        'task_started'        { Play-Cue -Name 'launch' }
        'user_message'        { Play-Cue -Name 'prompt' }
        'agent_message'       { Play-Cue -Name 'review' }
        'mcp_tool_call_end'   { Play-Cue -Name 'action' }
        'patch_apply_end' {
          if ($payload.success -eq $true) {
            Play-Cue -Name 'apply'
          } else {
            Play-Cue -Name 'error'
          }
        }
        'exec_command_end' {
          $exit = 0
          if ($payload.PSObject.Properties['exit_code'] -and $null -ne $payload.exit_code) {
            $exit = [int]$payload.exit_code
          }
          if ($exit -eq 0) {
            Play-Cue -Name 'success'
          } else {
            Play-Cue -Name 'error'
          }
        }
        'task_complete'         { Play-Cue -Name 'done' }
        'collab_agent_spawn_end' { Play-Cue -Name 'fork' }
        'collab_close_end'       { Play-Cue -Name 'resume' }
      }
    }
    'response_item' {
      $payload = $event.payload
      if (-not $payload) { return }
      if ($payload.type -eq 'function_call') {
        switch ($payload.name) {
          'shell_command' { Play-Cue -Name 'exec' }
          'search'        { Play-Cue -Name 'action' }
          'fetch'         { Play-Cue -Name 'action' }
          'update_plan'   { Play-Cue -Name 'action' }
          'spawn_agent'   { Play-Cue -Name 'fork' }
          'wait_agent'    { Play-Cue -Name 'resume' }
          'close_agent'   { Play-Cue -Name 'resume' }
        }
      }
    }
  }
}

# Tail the rollout file. Skip pre-existing content (only react to new events).
$stream = $null
$reader = $null
try {
  $stream = [System.IO.FileStream]::new(
    $rollout.FullName,
    [System.IO.FileMode]::Open,
    [System.IO.FileAccess]::Read,
    [System.IO.FileShare]::ReadWrite
  )
  $stream.Seek(0, [System.IO.SeekOrigin]::End) | Out-Null
  $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8)

  while ($true) {
    $line = $reader.ReadLine()
    if ($null -eq $line) {
      Start-Sleep -Milliseconds 100
      continue
    }
    Handle-Event -Line $line
  }
} catch {
  # Tailer must never crash the wrapper.
} finally {
  if ($reader) { $reader.Dispose() }
  if ($stream) { $stream.Dispose() }
}
