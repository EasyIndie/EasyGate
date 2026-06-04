param(
  [switch]$Purge
)

$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $RootDir

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
docker compose down --remove-orphans

if (-not $Purge) {
  Write-Info "清理完成。本地配置和 tunnel 凭据已保留。"
  exit 0
}

Write-Warn "即将删除本地生成配置和 tunnel 凭据。该操作不会删除 Cloudflare 上的 DNS 记录或 tunnel。"
$Confirm = Read-Host "确认继续？输入 yes"
if ($Confirm -ne "yes") {
  Write-Warn "已取消彻底清理"
  exit 0
}

@(
  ".env",
  ".easygate",
  "cloudflared/config.yml"
) | ForEach-Object {
  if (Test-Path $_) {
    Remove-Item $_ -Recurse -Force
    Write-Info "已删除 $_"
  }
}

Get-ChildItem "cloudflared" -Filter "*.json" -File -ErrorAction SilentlyContinue | ForEach-Object {
  Remove-Item $_.FullName -Force
  Write-Info "已删除 $($_.FullName)"
}

Write-Info "彻底清理完成。Cloudflare 侧资源如需删除，请使用 cloudflared CLI 或 Cloudflare Dashboard 手动处理。"
