param(
  [switch]$Purge
)

$RootDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
& (Join-Path $RootDir "scripts/cleanup.ps1") -Purge:$Purge
