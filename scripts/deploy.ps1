param(
  [string]$Domain = "",
  [string]$Tunnel = "easygate-home",
  [string]$Dashboard = "",
  [string]$Port = "18080",
  [switch]$NoInstallCloudflared,
  [switch]$SkipRoute,
  [switch]$Demo
)

$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $RootDir

function Write-Info {
  param([string]$Message)
  Write-Host "[deploy] $Message" -ForegroundColor Blue
}

function Write-Warn {
  param([string]$Message)
  Write-Host "[deploy] $Message" -ForegroundColor Yellow
}

function Fail {
  param([string]$Message)
  Write-Host "[deploy] $Message" -ForegroundColor Red
  exit 1
}

function Require-Command {
  param([string]$Name)
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    Fail "缺少命令：$Name"
  }
}

function Install-Cloudflared {
  if (Get-Command cloudflared -ErrorAction SilentlyContinue) {
    Write-Info "已找到 cloudflared：$((Get-Command cloudflared).Source)"
    return
  }

  if ($NoInstallCloudflared) {
    Fail "缺少命令：cloudflared"
  }

  $Arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
  switch ($Arch) {
    "X64" { $CloudflaredArch = "amd64" }
    "X86" { $CloudflaredArch = "386" }
    default { Fail "暂不支持的 CPU 架构：$Arch" }
  }

  if (-not [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)) {
    Fail "deploy.ps1 仅支持 Windows 自动安装 cloudflared；macOS/Linux 请使用 scripts/deploy.sh"
  }

  $InstallDir = Join-Path $RootDir ".easygate\bin"
  New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

  $Asset = "cloudflared-windows-$CloudflaredArch.exe"
  $Url = "https://github.com/cloudflare/cloudflared/releases/latest/download/$Asset"
  $Target = Join-Path $InstallDir "cloudflared.exe"

  Write-Info "下载 cloudflared：$Asset"
  Invoke-WebRequest -Uri $Url -OutFile $Target

  $env:PATH = "$InstallDir;$env:PATH"
  cloudflared --version | Out-Null
  Write-Info "cloudflared 已安装到 $Target"
}

function Prompt-Default {
  param(
    [string]$Prompt,
    [string]$Default
  )
  $Value = Read-Host "$Prompt [$Default]"
  if ([string]::IsNullOrWhiteSpace($Value)) {
    return $Default
  }
  return $Value
}

function Find-LatestCredential {
  param([string]$Dir)
  if (-not (Test-Path $Dir)) {
    return $null
  }
  return Get-ChildItem $Dir -Filter "*.json" -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
}

Require-Command "docker"
Install-Cloudflared

try {
  docker compose version | Out-Null
}
catch {
  Fail "当前 Docker 未提供 docker compose"
}

try {
  docker info | Out-Null
}
catch {
  Fail "Docker daemon 不可用，请先启动 Docker"
}

if ([string]::IsNullOrWhiteSpace($Domain)) {
  $Domain = Prompt-Default "请输入主域名" "example.com"
}

if ($Domain -eq "example.com") {
  Fail "请使用真实域名，不要使用 example.com"
}

if ([string]::IsNullOrWhiteSpace($Dashboard)) {
  $Dashboard = "traefik.$Domain"
}

$CloudflaredHome = Join-Path $HOME ".cloudflared"
$CertFile = Join-Path $CloudflaredHome "cert.pem"

Write-Info "确认 cloudflared 登录状态"
if (-not (Test-Path $CertFile)) {
  Write-Warn "未找到 $CertFile，将执行 cloudflared tunnel login"
  cloudflared tunnel login
}
else {
  Write-Info "已找到 cloudflared 登录凭据"
}

New-Item -ItemType Directory -Force -Path "cloudflared" | Out-Null

$BeforeCredential = Find-LatestCredential $CloudflaredHome

Write-Info "创建 Cloudflare Tunnel：$Tunnel"
try {
  cloudflared tunnel create $Tunnel
}
catch {
  Write-Warn "创建 tunnel 失败。若 tunnel 已存在，将尝试复用本地最新凭据文件。"
}

$AfterCredential = Find-LatestCredential $CloudflaredHome
$CredentialSource = $AfterCredential
if (-not $CredentialSource) {
  $CredentialSource = $BeforeCredential
}

if (-not $CredentialSource) {
  Fail "未找到 tunnel 凭据 JSON。请确认 cloudflared tunnel create 是否成功。"
}

$CredentialTarget = Join-Path "cloudflared" "$Tunnel.json"
Copy-Item $CredentialSource.FullName $CredentialTarget -Force
Write-Info "已复制 tunnel 凭据到 $CredentialTarget"

if (-not $SkipRoute) {
  Write-Info "创建通配 DNS 路由：*.$Domain"
  try {
    cloudflared tunnel route dns $Tunnel "*.$Domain"
  }
  catch {
    Write-Warn "自动创建 DNS 路由失败。请在 Cloudflare DNS 中手动添加 *.$Domain -> tunnel。"
  }
}
else {
  Write-Warn "已跳过 DNS 路由创建"
}

@(
  "BASE_DOMAIN=$Domain"
  "TRAEFIK_HTTP_PORT=$Port"
  "TRAEFIK_DASHBOARD_HOST=$Dashboard"
) | Set-Content -Path ".env" -Encoding UTF8

@(
  "tunnel: $Tunnel"
  "credentials-file: /etc/cloudflared/$Tunnel.json"
  ""
  "ingress:"
  "  - hostname: ""*.$Domain"""
  "    service: http://traefik:80"
  "  - service: http_status:404"
) | Set-Content -Path "cloudflared/config.yml" -Encoding UTF8

Write-Info "检查 Compose 配置"
docker compose --env-file .env config | Out-Null

Write-Info "启动 EasyGate"
docker compose up -d

if ($Demo) {
  Write-Info "启动演示服务"
  docker compose --profile demo up -d demo-api demo-test-api
}

Write-Info "部署完成"
Write-Host ""
Write-Host "后续检查："
Write-Host "  docker compose ps"
Write-Host "  docker compose logs -f traefik cloudflared"
Write-Host "  本地调试入口：http://127.0.0.1:$Port"
Write-Host "  https://api.$Domain"
Write-Host "  https://test-api.$Domain"
