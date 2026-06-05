param(
  [switch]$Purge
)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

function Get-EasyGateHome {
  if (-not [string]::IsNullOrWhiteSpace($env:EASYGATE_HOME)) {
    return $env:EASYGATE_HOME
  }
  return Join-Path $env:LOCALAPPDATA "EasyGate"
}

$EasyGateHome = Get-EasyGateHome
$Target = Join-Path $EasyGateHome "bin\easygate.ps1"

Write-Host "[uninstall] 停止 EasyGate 服务" -ForegroundColor Blue

if ($Purge) {
  & (Join-Path $RootDir "scripts\cleanup.ps1") -Purge
} else {
  & (Join-Path $RootDir "scripts\cleanup.ps1")
}

if (Test-Path $Target) {
  Remove-Item $Target -Force
  Write-Host "[uninstall] 已删除 CLI：$Target" -ForegroundColor Blue
} else {
  Write-Host "[uninstall] CLI 未安装或已删除：$Target" -ForegroundColor Blue
}

Write-Host "[uninstall] 卸载完成" -ForegroundColor Blue
