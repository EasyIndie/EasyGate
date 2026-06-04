param(
  [switch]$Demo
)

$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$EnvFile = Join-Path $RootDir ".env"
$EnvExample = Join-Path $RootDir ".env.example"

function Write-Info {
  param([string]$Message)
  Write-Host "[EasyGate] $Message" -ForegroundColor Blue
}

function Write-Warn {
  param([string]$Message)
  Write-Host "[EasyGate] $Message" -ForegroundColor Yellow
}

function Write-Err {
  param([string]$Message)
  Write-Host "[EasyGate] $Message" -ForegroundColor Red
}

function Require-Command {
  param([string]$Name)
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "缺少命令：$Name"
  }
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

function Prompt-Secret {
  param([string]$Prompt)
  $SecureValue = Read-Host $Prompt -AsSecureString
  $Bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureValue)
  try {
    return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($Bstr)
  }
  finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($Bstr)
  }
}

function Write-EnvFile {
  param(
    [string]$BaseDomain,
    [string]$TunnelToken,
    [string]$DashboardHost
  )
  $Lines = @(
    "BASE_DOMAIN=$BaseDomain"
    "CLOUDFLARE_TUNNEL_TOKEN=$TunnelToken"
    "TRAEFIK_DASHBOARD_HOST=$DashboardHost"
  )
  $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllLines($EnvFile, $Lines, $Utf8NoBom)
}

function Read-EnvFile {
  $Values = @{}
  Get-Content $EnvFile | ForEach-Object {
    $Line = $_.Trim()
    if ($Line -eq "" -or $Line.StartsWith("#")) {
      return
    }
    $Parts = $Line.Split("=", 2)
    if ($Parts.Length -eq 2) {
      $Values[$Parts[0]] = $Parts[1]
    }
  }
  return $Values
}

function Validate-Env {
  param([hashtable]$Values)
  $Failed = $false

  if (-not $Values.ContainsKey("BASE_DOMAIN") -or $Values["BASE_DOMAIN"] -eq "" -or $Values["BASE_DOMAIN"] -eq "example.com") {
    Write-Err ".env 中的 BASE_DOMAIN 还没有设置为真实域名"
    $Failed = $true
  }

  if (-not $Values.ContainsKey("CLOUDFLARE_TUNNEL_TOKEN") -or $Values["CLOUDFLARE_TUNNEL_TOKEN"] -eq "" -or $Values["CLOUDFLARE_TUNNEL_TOKEN"] -eq "replace-with-cloudflare-tunnel-token") {
    Write-Err ".env 中的 CLOUDFLARE_TUNNEL_TOKEN 还没有设置"
    $Failed = $true
  }

  if (-not $Values.ContainsKey("TRAEFIK_DASHBOARD_HOST") -or $Values["TRAEFIK_DASHBOARD_HOST"] -eq "") {
    Write-Err ".env 中的 TRAEFIK_DASHBOARD_HOST 不能为空"
    $Failed = $true
  }

  if ($Failed) {
    throw "请修正 .env 后重新运行"
  }
}

Set-Location $RootDir

Write-Info "开始部署 EasyGate"

try {
  Require-Command "docker"
  docker compose version | Out-Null
}
catch {
  Write-Err "请先安装 Docker Desktop，并确认 Docker Compose 可用"
  throw
}

if (-not (Test-Path $EnvFile)) {
  if (-not (Test-Path $EnvExample)) {
    throw "缺少 .env.example，无法生成 .env"
  }

  Write-Info "首次运行，正在生成 .env"
  $BaseDomain = Prompt-Default "请输入主域名" "example.com"
  $DashboardHost = Prompt-Default "请输入 Traefik dashboard 域名" "traefik.$BaseDomain"
  $TunnelToken = Prompt-Secret "请输入 Cloudflare Tunnel token"
  Write-EnvFile -BaseDomain $BaseDomain -TunnelToken $TunnelToken -DashboardHost $DashboardHost
  Write-Info ".env 已生成"
}
else {
  Write-Warn ".env 已存在，本脚本不会覆盖现有配置"
}

$EnvValues = Read-EnvFile
Validate-Env $EnvValues

Write-Info "检查 Compose 配置"
docker compose --env-file $EnvFile config | Out-Null

Write-Info "启动 Traefik 和 cloudflared"
docker compose --env-file $EnvFile up -d traefik cloudflared

if (-not $Demo) {
  $BaseDomain = $EnvValues["BASE_DOMAIN"]
  $Answer = Read-Host "是否启动演示服务 api.$BaseDomain 和 test-api.$BaseDomain？[y/N]"
  if ($Answer -match "^(y|Y|yes|YES)$") {
    $Demo = $true
  }
}

if ($Demo) {
  Write-Info "启动演示服务"
  docker compose --env-file $EnvFile --profile demo up -d demo-api demo-test-api
}
else {
  Write-Info "跳过演示服务"
}

Write-Info "部署完成"
$DashboardHost = $EnvValues["TRAEFIK_DASHBOARD_HOST"]
Write-Host ""
Write-Host "后续检查："
Write-Host "  docker compose ps"
Write-Host "  docker compose logs -f traefik cloudflared"
Write-Host "  https://$DashboardHost"
