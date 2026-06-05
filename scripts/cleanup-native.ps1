param(
  [switch]$Purge
)

$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $RootDir

function Write-Info {
  param([string]$Message)
  Write-Host "[cleanup-native] $Message" -ForegroundColor Blue
}

function Stop-PidFile {
  param([string]$Path)
  if (-not (Test-Path $Path)) {
    return
  }

  $PidText = (Get-Content -Raw $Path).Trim()
  $Name = [System.IO.Path]::GetFileNameWithoutExtension($Path)
  if (-not [string]::IsNullOrWhiteSpace($PidText)) {
    $Process = Get-Process -Id ([int]$PidText) -ErrorAction SilentlyContinue
    if ($Process) {
      Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
      Write-Info "已停止 $Name"
    }
  }
  Remove-Item -Force $Path -ErrorAction SilentlyContinue
}

@(
  ".easygate\run\native-cloudflared.pid"
  ".easygate\run\native-traefik.pid"
  ".easygate\run\native-demo-api.pid"
  ".easygate\run\native-demo-test-api.pid"
) | ForEach-Object {
  Stop-PidFile $_
}

if ($Purge) {
  @(
    ".easygate\native"
    ".easygate\run"
    ".easygate\logs"
    "cloudflared\config.native.yml"
  ) | ForEach-Object {
    if (Test-Path $_) {
      Remove-Item -Recurse -Force $_
    }
  }
  Write-Info "已删除原生模式本地运行配置"
}
else {
  Write-Info "原生模式进程已停止，配置和凭据已保留"
}
