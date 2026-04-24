param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]] $CliArgs
)

$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
. (Join-Path $root 'dialex-core.ps1')
$node = (Get-Command node).Source
$codexJs = Join-Path (Join-Path (npm root -g) '@openai\codex') 'bin\codex.js'

function Get-PrimaryCommand {
  param([string[]] $CommandArgs)

  foreach ($arg in $CommandArgs) {
    if (-not $arg.StartsWith('-')) {
      return $arg
    }
  }

  return $null
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
            Invoke-DialexSound -Root $root -Name 'exec'
            $state.HasCommandExecution = $true
          }
        }
        'item.completed' {
          if ($event.item -and $event.item.type -eq 'command_execution') {
            $exitCode = if ($null -ne $event.item.exit_code) { [int]$event.item.exit_code } else { 0 }
            if ($exitCode -eq 0) {
              if (-not $state.SuccessPlayed) {
                Invoke-DialexSound -Root $root -Name 'success'
                $state.SuccessPlayed = $true
              }
            } elseif (-not $state.ErrorPlayed) {
              Invoke-DialexSound -Root $root -Name 'error'
              $state.ErrorPlayed = $true
            }
          } elseif ($event.item -and $event.item.type -eq 'agent_message') {
            $state.SawAssistantMessage = $true
          }
        }
        'turn.completed' {
          if (-not $state.HasCommandExecution -and $state.SawAssistantMessage -and -not $state.SuccessPlayed) {
            Invoke-DialexSound -Root $root -Name 'review'
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
    Invoke-DialexSound -Root $root -Name 'error'
  }

  return $process.ExitCode
}

$cue = Get-StartCue -CommandArgs $CliArgs
Invoke-DialexSound -Root $root -Name $cue

$useJsonStream = $false
foreach ($arg in $CliArgs) {
  if ($arg -eq '--json') {
    $useJsonStream = $true
    break
  }
}

if ($useJsonStream) {
  $exitCode = Invoke-CodexProcess -CommandArgs $CliArgs
} else {
  Start-DialexTailer -Root $root
  try {
    & (Join-Path $env:APPDATA 'npm\codex.cmd') @CliArgs
    $exitCode = $LASTEXITCODE
  } finally {
    Stop-DialexTailer
  }

  if ($exitCode -eq 0) {
    Invoke-DialexSound -Root $root -Name 'success'
  } else {
    Invoke-DialexSound -Root $root -Name 'error'
  }
}

exit $exitCode
