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

function Get-EasyGateHome {
  if (-not [string]::IsNullOrWhiteSpace($env:EASYGATE_HOME)) {
    return $env:EASYGATE_HOME
  }
  return Join-Path $env:LOCALAPPDATA "EasyGate"
}

$EasyGateHome = Get-EasyGateHome
$ComposeDir = Join-Path $EasyGateHome "compose"
$ComposeFile = Join-Path $ComposeDir "docker-compose.yml"
$ComposeEnv = Join-Path $ComposeDir ".env"
$env:EASYGATE_HOME = $EasyGateHome
$env:PATH = (Join-Path $EasyGateHome "bin") + [System.IO.Path]::PathSeparator + $env:PATH

$CloudflaredHome = if (-not [string]::IsNullOrWhiteSpace($env:EASYGATE_CLOUDFLARED_HOME)) {
  $env:EASYGATE_CLOUDFLARED_HOME
}
else {
  Join-Path $HOME ".cloudflared"
}

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
  $InstallDir = Join-Path $EasyGateHome "bin"
  $Target = Join-Path $InstallDir "cloudflared.exe"

  if (Test-Path $Target -PathType Leaf) {
    $env:PATH = "$InstallDir;$env:PATH"
    Write-Info "已找到项目内 cloudflared：$Target"
    return
  }

  if (Get-Command cloudflared -ErrorAction SilentlyContinue) {
    if ($NoInstallCloudflared) {
      Write-Info "已找到 cloudflared：$((Get-Command cloudflared).Source)"
      return
    }

    Write-Info "将安装项目内最新 cloudflared，避免系统旧版本产生部署警告"
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

  New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

  $Asset = "cloudflared-windows-$CloudflaredArch.exe"
  $Url = "https://github.com/cloudflare/cloudflared/releases/latest/download/$Asset"

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

function Prepare-TunnelCredentials {
  $CredentialTarget = Join-Path (Join-Path $EasyGateHome "cloudflared") "$Tunnel.json"
  if (Test-Path $CredentialTarget -PathType Leaf) {
    Write-Info "复用已有 tunnel 凭据：$CredentialTarget"
    return
  }

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
    Fail "未找到 tunnel 凭据 JSON。请确认 cloudflared tunnel create 是否成功，或将已有凭据保存为 $CredentialTarget。"
  }

  Copy-Item $CredentialSource.FullName $CredentialTarget -Force
  Write-Info "已复制 tunnel 凭据到 $CredentialTarget"
}

function Test-NativeDeploymentActive {
  @(
    (Join-Path $EasyGateHome "run\native-cloudflared.pid")
    (Join-Path $EasyGateHome "run\native-traefik.pid")
    (Join-Path $EasyGateHome "run\native-demo-api.pid")
    (Join-Path $EasyGateHome "run\native-demo-test-api.pid")
  ) | ForEach-Object {
    if (-not (Test-Path $_)) {
      return
    }

    $PidText = (Get-Content -Raw $_).Trim()
    if ([string]::IsNullOrWhiteSpace($PidText)) {
      return
    }

    $Process = Get-Process -Id ([int]$PidText) -ErrorAction SilentlyContinue
    if ($Process) {
      Fail "检测到原生模式进程正在运行：$_。请先执行 .\scripts\cleanup-native.ps1，再部署 Docker Compose 模式。"
    }
  }
}

function Invoke-EasyGateCompose {
  # Use $args directly to avoid PowerShell consuming flags like -d as
  # common parameters (e.g. -Debug) when ValueFromRemainingArguments is used.
  & docker compose -p easygate -f $ComposeFile --env-file $ComposeEnv @args
}

function Write-RuntimeComposeFile {
  $TraefikConfig = (Join-Path $EasyGateHome "traefik\traefik.yml").Replace("\", "/")
  $TraefikDynamic = (Join-Path $EasyGateHome "traefik\dynamic").Replace("\", "/")
  $CloudflaredDir = (Join-Path $EasyGateHome "cloudflared").Replace("\", "/")
  @(
    "services:"
    "  traefik:"
    "    image: traefik:v3.1"
    "    container_name: easygate-traefik"
    "    restart: unless-stopped"
    "    command:"
    "      - --configFile=/etc/traefik/traefik.yml"
    "    ports:"
    "      - ""${Port}:80"""
    "    networks:"
    "      - easygate-proxy"
    "    extra_hosts:"
    "      - ""host.docker.internal:host-gateway"""
    "    volumes:"
    "      - ""/var/run/docker.sock:/var/run/docker.sock:ro"""
    "      - ""${TraefikConfig}:/etc/traefik/traefik.yml:ro"""
    "      - ""${TraefikDynamic}:/etc/traefik/dynamic:ro"""
    "    labels:"
    "      - traefik.enable=true"
    "      - traefik.docker.network=easygate-proxy"
    "      - traefik.http.routers.traefik-dashboard.rule=Host(``$Dashboard``)"
    "      - traefik.http.routers.traefik-dashboard.entrypoints=web"
    "      - traefik.http.routers.traefik-dashboard.service=api@internal"
    ""
    "  cloudflared:"
    "    image: cloudflare/cloudflared:latest"
    "    container_name: easygate-cloudflared"
    "    restart: unless-stopped"
    "    command: tunnel --config /etc/cloudflared/config.yml run"
    "    networks:"
    "      - easygate-proxy"
    "    volumes:"
    "      - ""${CloudflaredDir}:/etc/cloudflared:ro"""
    "    depends_on:"
    "      - traefik"
    ""
    "  demo-api:"
    "    image: traefik/whoami:v1.10"
    "    profiles: [""demo""]"
    "    restart: unless-stopped"
    "    networks:"
    "      - easygate-proxy"
    "    labels:"
    "      - traefik.enable=true"
    "      - traefik.docker.network=easygate-proxy"
    "      - traefik.http.routers.demo-api.rule=Host(``api.$Domain``)"
    "      - traefik.http.routers.demo-api.entrypoints=web"
    "      - traefik.http.services.demo-api.loadbalancer.server.port=80"
    ""
    "  demo-test-api:"
    "    image: traefik/whoami:v1.10"
    "    profiles: [""demo""]"
    "    restart: unless-stopped"
    "    networks:"
    "      - easygate-proxy"
    "    labels:"
    "      - traefik.enable=true"
    "      - traefik.docker.network=easygate-proxy"
    "      - traefik.http.routers.demo-test-api.rule=Host(``test-api.$Domain``)"
    "      - traefik.http.routers.demo-test-api.entrypoints=web"
    "      - traefik.http.services.demo-test-api.loadbalancer.server.port=80"
    ""
    "networks:"
    "  easygate-proxy:"
    "    name: easygate-proxy"
  ) | Set-Content -Path $ComposeFile -Encoding UTF8
}

Test-NativeDeploymentActive
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

$CertFile = Join-Path $CloudflaredHome "cert.pem"

Write-Info "确认 cloudflared 登录状态"
if (-not (Test-Path $CertFile)) {
  Write-Warn "未找到 $CertFile，将执行 cloudflared tunnel login"
  cloudflared tunnel login
}
else {
  Write-Info "已找到 cloudflared 登录凭据"
}

New-Item -ItemType Directory -Force -Path (Join-Path $EasyGateHome "cloudflared"), (Join-Path $EasyGateHome "traefik\dynamic"), $ComposeDir | Out-Null

Prepare-TunnelCredentials

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
  "EASYGATE_HOME=$EasyGateHome"
) | Set-Content -Path $ComposeEnv -Encoding UTF8

Copy-Item (Join-Path $RootDir "traefik\traefik.yml") (Join-Path $EasyGateHome "traefik\traefik.yml") -Force
Copy-Item -Recurse -Force (Join-Path $RootDir "traefik\dynamic\*") (Join-Path $EasyGateHome "traefik\dynamic")

@(
  "tunnel: $Tunnel"
  "credentials-file: /etc/cloudflared/$Tunnel.json"
  ""
  "ingress:"
  "  - hostname: ""*.$Domain"""
  "    service: http://traefik:80"
  "  - service: http_status:404"
) | Set-Content -Path (Join-Path $EasyGateHome "cloudflared\config.yml") -Encoding UTF8

Write-RuntimeComposeFile

Write-Info "检查 Compose 配置"
Invoke-EasyGateCompose config | Out-Null

Write-Info "启动 EasyGate"
Invoke-EasyGateCompose up -d

if ($Demo) {
  Write-Info "启动演示服务"
  Invoke-EasyGateCompose --profile demo up -d demo-api demo-test-api
}

Write-Info "部署完成"
Write-Host ""
Write-Host "后续检查："
Write-Host "  docker compose -p easygate -f ""$ComposeFile"" --env-file ""$ComposeEnv"" ps"
Write-Host "  docker compose -p easygate -f ""$ComposeFile"" --env-file ""$ComposeEnv"" logs -f traefik cloudflared"
Write-Host "  运行时目录：$EasyGateHome"
Write-Host "  本地调试入口：http://127.0.0.1:$Port"
Write-Host "  https://api.$Domain"
Write-Host "  https://test-api.$Domain"
