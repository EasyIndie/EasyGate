param(
  [string]$Domain = "",
  [string]$Tunnel = "easygate-home",
  [string]$Dashboard = "",
  [string]$Port = "18080",
  [string]$ApiPort = "19080",
  [string]$TestApiPort = "19081",
  [switch]$NoInstallCloudflared,
  [switch]$NoInstallTraefik,
  [switch]$SkipRoute,
  [switch]$Demo,
  [switch]$LocalOnly
)

$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $RootDir
$env:PATH = (Join-Path $RootDir ".easygate\bin") + [System.IO.Path]::PathSeparator + $env:PATH

$TraefikVersion = if (-not [string]::IsNullOrWhiteSpace($env:EASYGATE_TRAEFIK_VERSION)) {
  $env:EASYGATE_TRAEFIK_VERSION
}
else {
  "3.1.7"
}

$CloudflaredHome = if (-not [string]::IsNullOrWhiteSpace($env:EASYGATE_CLOUDFLARED_HOME)) {
  $env:EASYGATE_CLOUDFLARED_HOME
}
else {
  Join-Path $HOME ".cloudflared"
}

function Write-Info {
  param([string]$Message)
  Write-Host "[deploy-native] $Message" -ForegroundColor Blue
}

function Write-Warn {
  param([string]$Message)
  Write-Host "[deploy-native] $Message" -ForegroundColor Yellow
}

function Fail {
  param([string]$Message)
  Write-Host "[deploy-native] $Message" -ForegroundColor Red
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
    Fail "deploy-native.ps1 仅支持 Windows 自动安装 cloudflared；macOS/Linux 请使用 scripts/deploy-native.sh"
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

function Install-Traefik {
  if (Get-Command traefik -ErrorAction SilentlyContinue) {
    Write-Info "已找到 traefik：$((Get-Command traefik).Source)"
    return
  }

  if ($NoInstallTraefik) {
    Fail "缺少命令：traefik"
  }

  $Arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
  switch ($Arch) {
    "X64" { $TraefikArch = "amd64" }
    "X86" { $TraefikArch = "386" }
    "Arm64" { $TraefikArch = "arm64" }
    default { Fail "暂不支持的 CPU 架构：$Arch" }
  }

  if (-not [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)) {
    Fail "deploy-native.ps1 仅支持 Windows 自动安装 Traefik；macOS/Linux 请使用 scripts/deploy-native.sh"
  }

  $InstallDir = Join-Path $RootDir ".easygate\bin"
  $TmpDir = Join-Path $RootDir ".easygate\tmp\traefik"
  New-Item -ItemType Directory -Force -Path $InstallDir, $TmpDir | Out-Null

  $Asset = "traefik_v$TraefikVersion" + "_windows_$TraefikArch.zip"
  $Url = "https://github.com/traefik/traefik/releases/download/v$TraefikVersion/$Asset"
  $Archive = Join-Path $TmpDir $Asset
  $ExtractDir = Join-Path $TmpDir "extract"
  $Target = Join-Path $InstallDir "traefik.exe"

  Write-Info "下载 Traefik：$Asset"
  Invoke-WebRequest -Uri $Url -OutFile $Archive
  if (Test-Path $ExtractDir) {
    Remove-Item -Recurse -Force $ExtractDir
  }
  New-Item -ItemType Directory -Force -Path $ExtractDir | Out-Null
  Expand-Archive -Path $Archive -DestinationPath $ExtractDir -Force
  $Extracted = Get-ChildItem $ExtractDir -Recurse -Filter "traefik.exe" | Select-Object -First 1
  if (-not $Extracted) {
    Fail "未能从 $Asset 中找到 traefik.exe"
  }
  Copy-Item $Extracted.FullName $Target -Force
  $env:PATH = "$InstallDir;$env:PATH"
  traefik version | Out-Null
  Write-Info "Traefik 已安装到 $Target"
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

function Find-Python {
  $Python3 = Get-Command python3 -ErrorAction SilentlyContinue
  if ($Python3) {
    return $Python3.Source
  }
  $Python = Get-Command python -ErrorAction SilentlyContinue
  if ($Python) {
    return $Python.Source
  }
  return $null
}

function Test-ComposeDeploymentActive {
  if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    return
  }

  try {
    docker compose version | Out-Null
    docker info | Out-Null
    $Services = docker compose ps --services --status running 2>$null
  }
  catch {
    return
  }

  foreach ($Service in $Services) {
    if ($Service -eq "traefik" -or $Service -eq "cloudflared") {
      Fail "检测到 Docker Compose 模式正在运行。请先执行 docker compose down 或 make cleanup，再部署原生模式。"
    }
  }
}

function Stop-PidFile {
  param([string]$Path)
  if (-not (Test-Path $Path)) {
    return
  }

  $PidText = (Get-Content -Raw $Path).Trim()
  if (-not [string]::IsNullOrWhiteSpace($PidText)) {
    $Process = Get-Process -Id ([int]$PidText) -ErrorAction SilentlyContinue
    if ($Process) {
      Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
    }
  }
  Remove-Item -Force $Path -ErrorAction SilentlyContinue
}

function Start-NativeProcess {
  param(
    [string]$Name,
    [string]$FilePath,
    [string[]]$Arguments
  )
  $PidFile = Join-Path $RootDir ".easygate\run\$Name.pid"
  $LogFile = Join-Path $RootDir ".easygate\logs\$Name.log"
  $ErrFile = Join-Path $RootDir ".easygate\logs\$Name.err.log"
  Stop-PidFile $PidFile
  Write-Info "启动 $Name"
  $Process = Start-Process -FilePath $FilePath -ArgumentList $Arguments -RedirectStandardOutput $LogFile -RedirectStandardError $ErrFile -PassThru -WindowStyle Hidden
  Set-Content -Path $PidFile -Value $Process.Id -Encoding ASCII
}

Test-ComposeDeploymentActive
Install-Traefik
if (-not $LocalOnly) {
  Install-Cloudflared
}

if ([string]::IsNullOrWhiteSpace($Domain)) {
  $Domain = Prompt-Default "请输入主域名" "example.com"
}

if ($Domain -eq "example.com" -and -not $LocalOnly) {
  Fail "请使用真实域名，不要使用 example.com"
}

if ([string]::IsNullOrWhiteSpace($Dashboard)) {
  $Dashboard = "traefik.$Domain"
}

New-Item -ItemType Directory -Force -Path ".easygate\native\dynamic", ".easygate\run", ".easygate\logs", "cloudflared" | Out-Null

@(
  "BASE_DOMAIN=$Domain"
  "TRAEFIK_HTTP_PORT=$Port"
  "TRAEFIK_DASHBOARD_HOST=$Dashboard"
  "EASYGATE_DEPLOY_MODE=native"
  "EASYGATE_NATIVE_API_PORT=$ApiPort"
  "EASYGATE_NATIVE_TEST_API_PORT=$TestApiPort"
) | Set-Content -Path ".env" -Encoding UTF8

$NativeDynamicDir = (Join-Path $RootDir ".easygate\native\dynamic").Replace("\", "/")
@(
  "global:"
  "  checkNewVersion: false"
  "  sendAnonymousUsage: false"
  ""
  "api:"
  "  dashboard: true"
  ""
  "entryPoints:"
  "  web:"
  "    address: ""127.0.0.1:$Port"""
  ""
  "providers:"
  "  file:"
  "    directory: ""$NativeDynamicDir"""
  "    watch: true"
) | Set-Content -Path ".easygate\native\traefik.yml" -Encoding UTF8

$DynamicLines = @(
  "http:"
  "  routers:"
  "    traefik-dashboard:"
  "      rule: Host(``$Dashboard``)"
  "      entryPoints:"
  "        - web"
  "      service: api@internal"
)

if ($Demo) {
  $DynamicLines += @(
    "    demo-api:"
    "      rule: Host(``api.$Domain``)"
    "      entryPoints:"
    "        - web"
    "      service: demo-api"
    "    demo-test-api:"
    "      rule: Host(``test-api.$Domain``)"
    "      entryPoints:"
    "        - web"
    "      service: demo-test-api"
    ""
    "  services:"
    "    demo-api:"
    "      loadBalancer:"
    "        servers:"
    "          - url: http://127.0.0.1:$ApiPort"
    "    demo-test-api:"
    "      loadBalancer:"
    "        servers:"
    "          - url: http://127.0.0.1:$TestApiPort"
  )
}
else {
  $DynamicLines += @(
    ""
    "  services: {}"
  )
}

$DynamicLines | Set-Content -Path ".easygate\native\dynamic\services.yml" -Encoding UTF8

if (-not $LocalOnly) {
  $CertFile = Join-Path $CloudflaredHome "cert.pem"
  Write-Info "确认 cloudflared 登录状态"
  if (-not (Test-Path $CertFile)) {
    Write-Warn "未找到 $CertFile，将执行 cloudflared tunnel login"
    cloudflared tunnel login
  }
  else {
    Write-Info "已找到 cloudflared 登录凭据"
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

  $CredentialPath = (Join-Path $RootDir "cloudflared\$Tunnel.json").Replace("\", "/")
  @(
    "tunnel: $Tunnel"
    "credentials-file: $CredentialPath"
    ""
    "ingress:"
    "  - hostname: ""*.$Domain"""
    "    service: http://127.0.0.1:$Port"
    "  - service: http_status:404"
  ) | Set-Content -Path "cloudflared\config.native.yml" -Encoding UTF8
}

if ($Demo) {
  $Python = Find-Python
  if (-not $Python) {
    Fail "原生 demo 需要 python3 或 python"
  }
  Start-NativeProcess "native-demo-api" $Python @((Join-Path $RootDir "scripts\native-demo-server.py"), "--port", $ApiPort)
  Start-NativeProcess "native-demo-test-api" $Python @((Join-Path $RootDir "scripts\native-demo-server.py"), "--port", $TestApiPort)
}

Start-NativeProcess "native-traefik" (Get-Command traefik).Source @("--configFile=$RootDir\.easygate\native\traefik.yml")

if (-not $LocalOnly) {
  Start-NativeProcess "native-cloudflared" (Get-Command cloudflared).Source @("tunnel", "--config", "$RootDir\cloudflared\config.native.yml", "run")
}

Write-Info "原生部署完成"
Write-Host ""
Write-Host "后续检查："
Write-Host "  .\scripts\local-acceptance-native.ps1"
Write-Host "  Get-Content .easygate\logs\native-traefik.log -Tail 80"
if (-not $LocalOnly) {
  Write-Host "  Get-Content .easygate\logs\native-cloudflared.log -Tail 80"
  Write-Host "  https://api.$Domain"
  Write-Host "  https://test-api.$Domain"
}
