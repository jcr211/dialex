param(
  [Parameter(Mandatory = $true)]
  [string] $Event
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'dialex-core.ps1')

Invoke-DialexHookEvent -Root $PSScriptRoot -EventName $Event
