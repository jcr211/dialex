param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]] $Args
)

$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$assets = Join-Path $root 'assets'
$node = (Get-Command node).Source
$codexJs = Join-Path (Join-Path (npm root -g) '@openai\codex') 'bin\codex.js'

$sounds = @{
  launch = Join-Path $assets 'launch.wav'
  exec = Join-Path $assets 'exec.wav'
  review = Join-Path $assets 'review.wav'
  fork = Join-Path $assets 'fork.wav'
  resume = Join-Path $assets 'resume.wav'
  success = Join-Path $assets 'success.wav'
  error = Join-Path $assets 'error.wav'
  apply = Join-Path $assets 'apply.wav'
}

function Get-PrimaryCommand {
  param([string[]] $CommandArgs)

  foreach ($arg in $CommandArgs) {
    if (-not $arg.StartsWith('-')) {
      return $arg
    }
  }

  return $null
}

function Invoke-CodexSound {
  param([string] $Name)

  if ($env:CODEX_AUDIO_DISABLED -eq '1') {
    return
  }

  $path = $sounds[$Name]
  if (-not $path -or -not (Test-Path $path)) {
    return
  }

  try {
    $player = [System.Media.SoundPlayer]::new($path)
    $player.PlaySync()
  } catch {
    # Sound should never block Codex execution.
  }
}

function Get-StartCue {
  param([string[]] $CommandArgs)

  $primary = Get-PrimaryCommand -CommandArgs $CommandArgs

  if (-not $primary) {
    return 'launch'
  }

  switch ($primary) {
    'exec' { return 'exec' }
    'review' { return 'review' }
    'fork' { return 'fork' }
    'resume' { return 'resume' }
    'apply' { return 'apply' }
    default { return 'launch' }
  }
}

function Invoke-CodexProcess {
  param([string[]] $CommandArgs)

  $state = [hashtable]::Synchronized(@{
    HasCommandExecution = $false
    SawAssistantMessage = $false
    SuccessPlayed = $false
    ErrorPlayed = $false
    TurnCompleted = $false
  })

  function Handle-CodexJsonLine {
    param([string] $Line)

    try {
      if ([string]::IsNullOrWhiteSpace($Line)) {
        return
      }

      [Console]::Out.WriteLine($Line)

      $event = $Line | ConvertFrom-Json -Depth 16

      switch ($event.type) {
        'turn.started' {
          $state.HasCommandExecution = $false
          $state.SawAssistantMessage = $false
          $state.SuccessPlayed = $false
          $state.ErrorPlayed = $false
          $state.TurnCompleted = $false
        }
        'item.started' {
          if ($event.item -and $event.item.type -eq 'command_execution' -and -not $state.HasCommandExecution) {
            Invoke-CodexSound -Name 'exec'
            $state.HasCommandExecution = $true
          }
        }
        'item.completed' {
          if ($event.item -and $event.item.type -eq 'command_execution') {
            $exitCode = if ($null -ne $event.item.exit_code) { [int]$event.item.exit_code } else { 0 }
            if ($exitCode -eq 0) {
              if (-not $state.SuccessPlayed) {
                Invoke-CodexSound -Name 'success'
                $state.SuccessPlayed = $true
              }
            } elseif (-not $state.ErrorPlayed) {
              Invoke-CodexSound -Name 'error'
              $state.ErrorPlayed = $true
            }
          } elseif ($event.item -and $event.item.type -eq 'agent_message') {
            $state.SawAssistantMessage = $true
          }
        }
        'turn.completed' {
          if (-not $state.HasCommandExecution -and $state.SawAssistantMessage -and -not $state.SuccessPlayed) {
            Invoke-CodexSound -Name 'review'
            $state.SuccessPlayed = $true
          }
          $state.TurnCompleted = $true
        }
      }
    } catch {
      # Parsing or cue playback should never terminate Codex.
    }
  }

  $psi = [System.Diagnostics.ProcessStartInfo]::new()
  $psi.FileName = $node
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
  $psi.StandardErrorEncoding = [System.Text.UTF8Encoding]::new($false)
  $psi.ArgumentList.Add($codexJs)
  foreach ($arg in $CommandArgs) {
    $psi.ArgumentList.Add($arg)
  }

  $process = [System.Diagnostics.Process]::new()
  $process.StartInfo = $psi

  if (-not $process.Start()) {
    throw 'Failed to start Codex process.'
  }

  while (-not $process.HasExited -or $process.StandardOutput.Peek() -ge 0 -or $process.StandardError.Peek() -ge 0) {
    $progress = $false

    while ($process.StandardOutput.Peek() -ge 0) {
      Handle-CodexJsonLine -Line $process.StandardOutput.ReadLine()
      $progress = $true
    }

    while ($process.StandardError.Peek() -ge 0) {
      $line = $process.StandardError.ReadLine()
      if ($null -ne $line) {
        [Console]::Error.WriteLine($line)
      }
      $progress = $true
    }

    if (-not $progress) {
      Start-Sleep -Milliseconds 50
    }
  }

  $process.WaitForExit()

  if ($process.ExitCode -ne 0 -and -not $state.ErrorPlayed) {
    Invoke-CodexSound -Name 'error'
  }

  return $process.ExitCode
}

$cue = Get-StartCue -CommandArgs $Args
Invoke-CodexSound -Name $cue

$useJsonStream = $false
foreach ($arg in $Args) {
  if ($arg -eq '--json') {
    $useJsonStream = $true
    break
  }
}

if ($useJsonStream) {
  $exitCode = Invoke-CodexProcess -CommandArgs $Args
} else {
  & (Join-Path $env:APPDATA 'npm\codex.cmd') @Args
  $exitCode = $LASTEXITCODE

  if ($exitCode -eq 0) {
    Invoke-CodexSound -Name 'success'
  } else {
    Invoke-CodexSound -Name 'error'
  }
}

exit $exitCode

