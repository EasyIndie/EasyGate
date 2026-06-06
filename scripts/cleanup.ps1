param(
  [switch]$Purge
)

$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $RootDir

function Get-EasyGateHome {
  if (-not [string]::IsNullOrWhiteSpace($env:EASYGATE_HOME)) {
    return $env:EASYGATE_HOME
  }
  return Join-Path $env:LOCALAPPDATA "EasyGate"
}

$EasyGateHome = Get-EasyGateHome
$ComposeFile = Join-Path $EasyGateHome "compose\docker-compose.yml"
$ComposeEnv = Join-Path $EasyGateHome "compose\.env"

function Write-Info {
  param([string]$Message)
  Write-Host "[cleanup] $Message" -ForegroundColor Blue
}

function Write-Warn {
  param([string]$Message)
  Write-Host "[cleanup] $Message" -ForegroundColor Yellow
}

function Write-Err {
  param([string]$Message)
  Write-Host "[cleanup] $Message" -ForegroundColor Red
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  Write-Err "未找到 docker，无法清理 Compose 部署"
  exit 1
}

try {
  docker compose version | Out-Null
}
catch {
  Write-Err "当前 Docker 未提供 docker compose"
  throw
}

Write-Info "停止并移除 EasyGate 容器和网络"
if ((Test-Path $ComposeFile) -and (Test-Path $ComposeEnv)) {
  docker compose -p easygate -f $ComposeFile --env-file $ComposeEnv --profile demo down --remove-orphans
}
else {
  Write-Warn "未找到运行时 Compose 配置：$ComposeFile，跳过 docker compose down"
}

if (-not $Purge) {
  Write-Info "清理完成。本地配置和 tunnel 凭据已保留。"
  exit 0
}

Write-Warn "即将删除运行时目录 $EasyGateHome，包括本地配置、二进制和 tunnel 凭据。该操作不会删除 Cloudflare 上的 DNS 记录或 tunnel。"
$Confirm = $env:EASYGATE_CONFIRM_PURGE
if ([string]::IsNullOrWhiteSpace($Confirm)) {
  $Confirm = Read-Host "确认继续？输入 yes"
}
if ($Confirm -ne "yes") {
  Write-Warn "已取消彻底清理"
  exit 0
}

if (Test-Path $EasyGateHome) {
  Remove-Item $EasyGateHome -Recurse -Force
  Write-Info "已删除 $EasyGateHome"
}

Write-Info "彻底清理完成。Cloudflare 侧资源如需删除，请使用 cloudflared CLI 或 Cloudflare Dashboard 手动处理。"
