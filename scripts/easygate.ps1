# 不使用 param() 以避免 PS7 参数绑定问题。
# $args 捕获所有原始参数，由函数内部手动解析。
$CommandArgs = @($args)

# 手动解析子命令，避免 PS7 参数绑定问题
if ($CommandArgs.Count -eq 0) {
  Show-Usage
  exit 0
}
$Command = $CommandArgs[0]
$Rest = if ($CommandArgs.Count -gt 1) { $CommandArgs[1..($CommandArgs.Count - 1)] } else { @() }


$ErrorActionPreference = "Stop"
$Version = if ([string]::IsNullOrWhiteSpace($env:EASYGATE_VERSION)) { "dev" } else { $env:EASYGATE_VERSION }

function Get-EasyGateHome {
  if (-not [string]::IsNullOrWhiteSpace($env:EASYGATE_HOME)) {
    return $env:EASYGATE_HOME
  }
  return Join-Path $env:LOCALAPPDATA "EasyGate"
}

$EasyGateHome = Get-EasyGateHome
$env:EASYGATE_HOME = $EasyGateHome
$env:PATH = (Join-Path $EasyGateHome "bin") + [System.IO.Path]::PathSeparator + $env:PATH
$CloudflaredHome = if ([string]::IsNullOrWhiteSpace($env:EASYGATE_CLOUDFLARED_HOME)) {
  Join-Path $HOME ".cloudflared"
}
else {
  $env:EASYGATE_CLOUDFLARED_HOME
}
$TraefikVersion = if ([string]::IsNullOrWhiteSpace($env:EASYGATE_TRAEFIK_VERSION)) { "3.1.7" } else { $env:EASYGATE_TRAEFIK_VERSION }
$ComposeDir = Join-Path $EasyGateHome "compose"
$ComposeFile = Join-Path $ComposeDir "docker-compose.yml"
$ComposeEnv = Join-Path $ComposeDir ".env"

# 所有参数已由 $args 捕获，dispatch 函数从 $Rest 中手动解析。
# 不需要 $PSBoundParameters / $ForwardedOptions（PS7 兼容性）。

function Write-Info {
  param([string]$Message)
  Write-Host "[easygate] $Message" -ForegroundColor Blue
}

function Write-Warn {
  param([string]$Message)
  Write-Host "[easygate] $Message" -ForegroundColor Yellow
}

function Fail {
  param([string]$Message)
  Write-Host "[easygate] $Message" -ForegroundColor Red
  exit 1
}

function Show-Usage {
  @"
用法：
  easygate.ps1 deploy -Domain <domain> [选项]
  easygate.ps1 native deploy -Domain <domain> [选项]
  easygate.ps1 start|stop|restart      服务管理
  easygate.ps1 ps|logs|config          状态与日志
  easygate.ps1 demo start|stop|restart Demo 服务
  easygate.ps1 uninstall               卸载
  easygate.ps1 home|version            信息查询

常用选项：
  -Domain <domain>       主域名，例如 example.com
  -Tunnel <name>         tunnel 名称，默认 easygate-home
  -Dashboard <hostname>  Traefik dashboard 域名，默认 traefik.<domain>
  -Port <port>           本地调试端口，默认 18080
  -SkipRoute             不自动创建 *.domain 的 DNS 路由
  -Demo                  部署后启动 demo 服务
  -NoInstallCloudflared
  -NoInstallTraefik      仅 native deploy 支持
  -LocalOnly             仅 native deploy 支持
"@
}

function Get-OptionValue {
  param(
    [hashtable]$Options,
    [string]$Name,
    [string]$Default = ""
  )
  if ($Options.ContainsKey($Name)) {
    return [string]$Options[$Name]
  }
  return $Default
}

function Test-Option {
  param(
    [hashtable]$Options,
    [string]$Name
  )
  return $Options.ContainsKey($Name)
}

function Parse-Options {
  param([string[]]$Args)
  $Options = @{}
  for ($Index = 0; $Index -lt $Args.Count; $Index++) {
    $Arg = $Args[$Index]
    switch -Regex ($Arg) {
      '^--?domain$|^-Domain$' { $Index++; $Options["Domain"] = $Args[$Index]; continue }
      '^--?tunnel$|^-Tunnel$' { $Index++; $Options["Tunnel"] = $Args[$Index]; continue }
      '^--?dashboard$|^-Dashboard$' { $Index++; $Options["Dashboard"] = $Args[$Index]; continue }
      '^--?port$|^-Port$' { $Index++; $Options["Port"] = $Args[$Index]; continue }
      '^--?api-port$|^-ApiPort$' { $Index++; $Options["ApiPort"] = $Args[$Index]; continue }
      '^--?test-api-port$|^-TestApiPort$' { $Index++; $Options["TestApiPort"] = $Args[$Index]; continue }
      '^--?skip-route$|^-SkipRoute$' { $Options["SkipRoute"] = $true; continue }
      '^--?demo$|^-Demo$' { $Options["Demo"] = $true; continue }
      '^--?local-only$|^-LocalOnly$' { $Options["LocalOnly"] = $true; continue }
      '^--?no-install-cloudflared$|^-NoInstallCloudflared$' { $Options["NoInstallCloudflared"] = $true; continue }
      '^--?no-install-traefik$|^-NoInstallTraefik$' { $Options["NoInstallTraefik"] = $true; continue }
      '^--?purge$|^-Purge$' { $Options["Purge"] = $true; continue }
      '^--?help$|^-h$' { $Options["Help"] = $true; continue }
      default { Fail "未知参数：$Arg" }
    }
  }
  return $Options
}

function Prompt-Default {
  param([string]$Prompt, [string]$Default)
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

function Install-Cloudflared {
  param([bool]$Install)
  $InstallDir = Join-Path $EasyGateHome "bin"
  $Target = Join-Path $InstallDir "cloudflared.exe"

  if (Test-Path $Target -PathType Leaf) {
    Write-Info "已找到运行时 cloudflared：$Target"
    return
  }
  if (Get-Command cloudflared -ErrorAction SilentlyContinue) {
    if (-not $Install) {
      Write-Info "已找到 cloudflared：$((Get-Command cloudflared).Source)"
      return
    }
    Write-Info "将安装运行时 cloudflared，避免系统旧版本产生部署警告"
  }
  if (-not $Install) {
    Fail "缺少命令：cloudflared"
  }
  if (-not [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)) {
    Fail "easygate.ps1 仅支持 Windows 自动安装 cloudflared；macOS/Linux 请使用 scripts/easygate"
  }

  $Arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
  switch ($Arch) {
    "X64" { $CloudflaredArch = "amd64" }
    "X86" { $CloudflaredArch = "386" }
    default { Fail "暂不支持的 CPU 架构：$Arch" }
  }

  New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
  $Asset = "cloudflared-windows-$CloudflaredArch.exe"
  $Url = "https://github.com/cloudflare/cloudflared/releases/latest/download/$Asset"
  Write-Info "下载 cloudflared：$Asset"
  Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Target
  cloudflared --version | Out-Null
  Write-Info "cloudflared 已安装到 $Target"
}

function Install-Traefik {
  param([bool]$Install)
  if (Get-Command traefik -ErrorAction SilentlyContinue) {
    Write-Info "已找到 traefik：$((Get-Command traefik).Source)"
    return
  }
  if (-not $Install) {
    Fail "缺少命令：traefik"
  }
  if (-not [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)) {
    Fail "easygate.ps1 仅支持 Windows 自动安装 Traefik；macOS/Linux 请使用 scripts/easygate"
  }

  $Arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
  switch ($Arch) {
    "X64" { $TraefikArch = "amd64" }
    "X86" { $TraefikArch = "386" }
    "Arm64" { $TraefikArch = "arm64" }
    default { Fail "暂不支持的 CPU 架构：$Arch" }
  }

  $InstallDir = Join-Path $EasyGateHome "bin"
  $TmpDir = Join-Path $EasyGateHome "tmp\traefik"
  $ExtractDir = Join-Path $TmpDir "extract"
  New-Item -ItemType Directory -Force -Path $InstallDir, $TmpDir | Out-Null

  $Asset = "traefik_v$TraefikVersion" + "_windows_$TraefikArch.zip"
  $Archive = Join-Path $TmpDir $Asset
  $Target = Join-Path $InstallDir "traefik.exe"
  $Url = "https://github.com/traefik/traefik/releases/download/v$TraefikVersion/$Asset"
  Write-Info "下载 Traefik：$Asset"
  Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Archive
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
  traefik version | Out-Null
  Write-Info "Traefik 已安装到 $Target"
}

function Prepare-TunnelCredentials {
  param([string]$Tunnel)
  $CloudflaredDir = Join-Path $EasyGateHome "cloudflared"
  $CredentialTarget = Join-Path $CloudflaredDir "$Tunnel.json"
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
  $CredentialSource = if ($AfterCredential) { $AfterCredential } else { $BeforeCredential }
  if (-not $CredentialSource) {
    Fail "未找到 tunnel 凭据 JSON。请确认 cloudflared tunnel create 是否成功，或将已有凭据保存为 $CredentialTarget。"
  }
  Copy-Item $CredentialSource.FullName $CredentialTarget -Force
  Write-Info "已复制 tunnel 凭据到 $CredentialTarget"
}

function Write-TraefikTemplates {
  New-Item -ItemType Directory -Force -Path (Join-Path $EasyGateHome "traefik\dynamic") | Out-Null
  @'
global:
  checkNewVersion: false
  sendAnonymousUsage: false

api:
  dashboard: true

entryPoints:
  web:
    address: ":80"
    forwardedHeaders:
      trustedIPs:
        - "172.16.0.0/12"
        - "10.0.0.0/8"
        - "192.168.0.0/16"

providers:
  docker:
    exposedByDefault: false
    network: easygate-proxy
    watch: true
  file:
    directory: /etc/traefik/dynamic
    watch: true
'@ | Set-Content -Path (Join-Path $EasyGateHome "traefik\traefik.yml") -Encoding UTF8
  "# Local service examples can be added here." | Set-Content -Path (Join-Path $EasyGateHome "traefik\dynamic\localhost-services.yml") -Encoding UTF8
}

function Write-RuntimeComposeFile {
  param([string]$Domain, [string]$Dashboard, [string]$Port)
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
    "    image: cloudflare/cloudflared:2025.2.1"
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

function Invoke-EasyGateCompose {
  # Use $args directly to avoid PowerShell consuming flags like -d as
  # common parameters (e.g. -Debug).
  if (-not (Test-Path $ComposeFile) -or -not (Test-Path $ComposeEnv)) {
    Fail "未找到运行时 Compose 配置，请先执行 easygate.ps1 deploy。期望文件：$ComposeFile"
  }
  & docker compose -p easygate -f $ComposeFile --env-file $ComposeEnv @args
}

function Test-NativeProcessActive {
  param([string]$Path)
  if (-not (Test-Path $Path)) {
    return $false
  }
  $PidText = (Get-Content -Raw $Path).Trim()
  if ([string]::IsNullOrWhiteSpace($PidText)) {
    return $false
  }
  return [bool](Get-Process -Id ([int]$PidText) -ErrorAction SilentlyContinue)
}

function Assert-NoNativeDeployment {
  @(
    (Join-Path $EasyGateHome "run\native-cloudflared.pid")
    (Join-Path $EasyGateHome "run\native-traefik.pid")
    (Join-Path $EasyGateHome "run\native-demo-api.pid")
    (Join-Path $EasyGateHome "run\native-demo-test-api.pid")
  ) | ForEach-Object {
    if (Test-NativeProcessActive $_) {
      Fail "检测到原生模式进程正在运行：$_。请先执行 easygate.ps1 native cleanup。"
    }
  }
}

function Test-ComposeDeploymentActive {
  if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    return $false
  }
  try {
    docker compose version | Out-Null
    docker info | Out-Null
    if (-not (Test-Path $ComposeFile) -or -not (Test-Path $ComposeEnv)) {
      return $false
    }
    $Services = docker compose -p easygate -f $ComposeFile --env-file $ComposeEnv ps --services --status running 2>$null
    foreach ($Service in $Services) {
      if ($Service -eq "traefik" -or $Service -eq "cloudflared") {
        return $true
      }
    }
  }
  catch {
    return $false
  }
  return $false
}

function Assert-NoComposeDeployment {
  if (Test-ComposeDeploymentActive) {
    Fail "检测到 Docker Compose 模式正在运行。请先执行 easygate.ps1 cleanup，再部署原生模式。"
  }
}

function Deploy-Compose {
  param([string[]]$Args)
  $Options = Parse-Options $Args
  if (Test-Option $Options "Help") {
    Show-Usage
    return
  }
  Assert-NoNativeDeployment
  if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Fail "缺少命令：docker"
  }
  Install-Cloudflared (-not (Test-Option $Options "NoInstallCloudflared"))
  docker compose version | Out-Null
  docker info | Out-Null

  $Domain = Get-OptionValue $Options "Domain"
  if ([string]::IsNullOrWhiteSpace($Domain)) {
    $Domain = Prompt-Default "请输入主域名" "example.com"
  }
  if ($Domain -eq "example.com") {
    Fail "请使用真实域名，不要使用 example.com"
  }
  $Tunnel = Get-OptionValue $Options "Tunnel" "easygate-home"
  $Dashboard = Get-OptionValue $Options "Dashboard" "traefik.$Domain"
  $Port = Get-OptionValue $Options "Port" "18080"

  New-Item -ItemType Directory -Force -Path (Join-Path $EasyGateHome "cloudflared"), $ComposeDir | Out-Null
  Write-TraefikTemplates

  Write-Info "确认 cloudflared 登录状态"
  if (-not (Test-Path (Join-Path $CloudflaredHome "cert.pem"))) {
    Write-Warn "未找到 $CloudflaredHome\cert.pem，将执行 cloudflared tunnel login"
    cloudflared tunnel login
  }
  else {
    Write-Info "已找到 cloudflared 登录凭据"
  }
  Prepare-TunnelCredentials $Tunnel

  if (-not (Test-Option $Options "SkipRoute")) {
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

  @(
    "tunnel: $Tunnel"
    "credentials-file: /etc/cloudflared/$Tunnel.json"
    ""
    "ingress:"
    "  - hostname: ""*.$Domain"""
    "    service: http://traefik:80"
    "  - service: http_status:404"
  ) | Set-Content -Path (Join-Path $EasyGateHome "cloudflared\config.yml") -Encoding UTF8

  Write-RuntimeComposeFile $Domain $Dashboard $Port
  Write-Info "检查 Compose 配置"
  Invoke-EasyGateCompose config | Out-Null
  Write-Info "启动 EasyGate"
  Invoke-EasyGateCompose up -d
  if (Test-Option $Options "Demo") {
    Write-Info "启动演示服务"
    Invoke-EasyGateCompose --profile demo up -d demo-api demo-test-api
  }
  Write-Info "部署完成"
  Write-Host ""
  Write-Host "后续检查："
  Write-Host "  easygate.ps1 ps"
  Write-Host "  easygate.ps1 logs"
  Write-Host "  运行时目录：$EasyGateHome"
  Write-Host "  本地调试入口：http://127.0.0.1:$Port"
  Write-Host "  https://api.$Domain"
  Write-Host "  https://test-api.$Domain"
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
  $PidFile = Join-Path $EasyGateHome "run\$Name.pid"
  $LogFile = Join-Path $EasyGateHome "logs\$Name.log"
  $ErrFile = Join-Path $EasyGateHome "logs\$Name.err.log"
  Stop-PidFile $PidFile
  Write-Info "启动 $Name"
  $Process = Start-Process -FilePath $FilePath -ArgumentList $Arguments -RedirectStandardOutput $LogFile -RedirectStandardError $ErrFile -PassThru -WindowStyle Hidden
  Set-Content -Path $PidFile -Value $Process.Id -Encoding ASCII
}

function Write-NativeDemoServer {
  $LibDir = Join-Path $EasyGateHome "lib"
  New-Item -ItemType Directory -Force -Path $LibDir | Out-Null
  @'
import argparse
import socket
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        body = "\n".join([
            f"Hostname: {socket.gethostname()}",
            "IP: 127.0.0.1",
            f"RemoteAddr: {self.client_address[0]}:{self.client_address[1]}",
            f"Host: {self.headers.get('Host', '')}",
            f"Path: {self.path}",
            "",
        ]).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, _format, *_args):
        return

def main():
    parser = argparse.ArgumentParser(description="EasyGate native demo HTTP server")
    parser.add_argument("--port", type=int, required=True)
    args = parser.parse_args()
    ThreadingHTTPServer(("127.0.0.1", args.port), Handler).serve_forever()

if __name__ == "__main__":
    main()
'@ | Set-Content -Path (Join-Path $LibDir "native-demo-server.py") -Encoding UTF8
}

function Deploy-Native {
  param([string[]]$Args)
  $Options = Parse-Options $Args
  if (Test-Option $Options "Help") {
    Show-Usage
    return
  }
  Assert-NoComposeDeployment
  Install-Traefik (-not (Test-Option $Options "NoInstallTraefik"))
  $LocalOnly = Test-Option $Options "LocalOnly"
  if (-not $LocalOnly) {
    Install-Cloudflared (-not (Test-Option $Options "NoInstallCloudflared"))
  }

  $Domain = Get-OptionValue $Options "Domain"
  if ([string]::IsNullOrWhiteSpace($Domain)) {
    $Domain = Prompt-Default "请输入主域名" "example.com"
  }
  if ($Domain -eq "example.com" -and -not $LocalOnly) {
    Fail "请使用真实域名，不要使用 example.com"
  }
  $Tunnel = Get-OptionValue $Options "Tunnel" "easygate-home"
  $Dashboard = Get-OptionValue $Options "Dashboard" "traefik.$Domain"
  $Port = Get-OptionValue $Options "Port" "18080"
  $ApiPort = Get-OptionValue $Options "ApiPort" "19080"
  $TestApiPort = Get-OptionValue $Options "TestApiPort" "19081"

  New-Item -ItemType Directory -Force -Path (Join-Path $EasyGateHome "native\dynamic"), (Join-Path $EasyGateHome "run"), (Join-Path $EasyGateHome "logs"), (Join-Path $EasyGateHome "cloudflared") | Out-Null
  @(
    "BASE_DOMAIN=$Domain"
    "TRAEFIK_HTTP_PORT=$Port"
    "TRAEFIK_DASHBOARD_HOST=$Dashboard"
    "EASYGATE_DEPLOY_MODE=native"
    "EASYGATE_NATIVE_API_PORT=$ApiPort"
    "EASYGATE_NATIVE_TEST_API_PORT=$TestApiPort"
    "EASYGATE_HOME=$EasyGateHome"
  ) | Set-Content -Path (Join-Path $EasyGateHome "native\.env") -Encoding UTF8

  @"
global:
  checkNewVersion: false
  sendAnonymousUsage: false

api:
  dashboard: true

entryPoints:
  web:
    address: ":$Port"

providers:
  file:
    directory: "$((Join-Path $EasyGateHome "native\dynamic").Replace("\", "/"))"
    watch: true
"@ | Set-Content -Path (Join-Path $EasyGateHome "native\traefik.yml") -Encoding UTF8

  @"
http:
  routers:
    traefik-dashboard:
      rule: "Host(``$Dashboard``)"
      entryPoints:
        - web
      service: api@internal
    demo-api:
      rule: "Host(``api.$Domain``)"
      entryPoints:
        - web
      service: demo-api
    demo-test-api:
      rule: "Host(``test-api.$Domain``)"
      entryPoints:
        - web
      service: demo-test-api

  services:
    demo-api:
      loadBalancer:
        servers:
          - url: "http://127.0.0.1:$ApiPort"
    demo-test-api:
      loadBalancer:
        servers:
          - url: "http://127.0.0.1:$TestApiPort"
"@ | Set-Content -Path (Join-Path $EasyGateHome "native\dynamic\demo-services.yml") -Encoding UTF8

  if (-not $LocalOnly) {
    Write-Info "确认 cloudflared 登录状态"
    if (-not (Test-Path (Join-Path $CloudflaredHome "cert.pem"))) {
      Write-Warn "未找到 $CloudflaredHome\cert.pem，将执行 cloudflared tunnel login"
      cloudflared tunnel login
    }
    else {
      Write-Info "已找到 cloudflared 登录凭据"
    }
    Prepare-TunnelCredentials $Tunnel
    if (-not (Test-Option $Options "SkipRoute")) {
      Write-Info "创建通配 DNS 路由：*.$Domain"
      try {
        cloudflared tunnel route dns $Tunnel "*.$Domain"
      }
      catch {
        Write-Warn "自动创建 DNS 路由失败。请在 Cloudflare DNS 中手动添加 *.$Domain -> tunnel。"
      }
    }
    @(
      "tunnel: $Tunnel"
      "credentials-file: $((Join-Path $EasyGateHome "cloudflared\$Tunnel.json").Replace("\", "/"))"
      ""
      "ingress:"
      "  - hostname: ""*.$Domain"""
      "    service: http://127.0.0.1:$Port"
      "  - service: http_status:404"
    ) | Set-Content -Path (Join-Path $EasyGateHome "cloudflared\config.native.yml") -Encoding UTF8
  }

  if (Test-Option $Options "Demo") {
    $Python = Find-Python
    if (-not $Python) {
      Fail "缺少 python3/python，无法启动原生 demo 服务"
    }
    Write-NativeDemoServer
    $DemoScript = Join-Path $EasyGateHome "lib\native-demo-server.py"
    Start-NativeProcess "native-demo-api" $Python @($DemoScript, "--port", $ApiPort)
    Start-NativeProcess "native-demo-test-api" $Python @($DemoScript, "--port", $TestApiPort)
  }

  Start-NativeProcess "native-traefik" "traefik" @("--configFile", (Join-Path $EasyGateHome "native\traefik.yml"))
  if (-not $LocalOnly) {
    Start-NativeProcess "native-cloudflared" "cloudflared" @("tunnel", "--config", (Join-Path $EasyGateHome "cloudflared\config.native.yml"), "run")
  }

  Write-Info "原生部署完成"
  Write-Host ""
  Write-Host "后续检查："
  Write-Host "  easygate.ps1 native logs"
  Write-Host "  easygate.ps1 native cleanup"
  Write-Host "  运行时目录：$EasyGateHome"
  Write-Host "  本地调试入口：http://127.0.0.1:$Port"
  Write-Host "  https://api.$Domain"
  Write-Host "  https://test-api.$Domain"
}

function Start-Services {
  Invoke-EasyGateCompose start
  Write-Info "服务已启动"
}

function Stop-Services {
  Invoke-EasyGateCompose stop
  Write-Info "服务已停止，配置和凭据已保留"
}

function Restart-Services {
  Invoke-EasyGateCompose restart
  Write-Info "服务已重启"
}

function Invoke-Uninstall {
  # Stop services if any are running
  if ((Test-Path $ComposeFile) -and (Test-Path $ComposeEnv) -and (Get-Command docker -ErrorAction SilentlyContinue)) {
    try { Invoke-EasyGateCompose down --remove-orphans } catch { }
  }
  # Delete all local data
  if (Test-Path $EasyGateHome) {
    Remove-Item -Recurse -Force $EasyGateHome
    Write-Info "已删除运行时目录 ${EasyGateHome}"
  }
  Write-Info "卸载完成。Cloudflare 侧资源如需删除，请使用 cloudflared CLI 或 Cloudflare Dashboard 手动处理。"
}

# 手动解析子命令，避免 PS7 参数绑定问题
if ($CommandArgs.Count -eq 0) {
  Show-Usage
  exit 0
}
$Command = $CommandArgs[0]
$Rest = if ($CommandArgs.Count -gt 1) { $CommandArgs[1..($CommandArgs.Count - 1)] } else { @() }

switch ($Command) {
  "deploy" { Deploy-Compose $Rest }
  "native" {
    if ($Rest.Count -eq 0) {
      Show-Usage
      exit 1
    }
    $NativeCommand = $Rest[0]
    $NativeRest = if ($Rest.Count -gt 1) { $Rest[1..($Rest.Count - 1)] } else { @() }
    switch ($NativeCommand) {
      "deploy" { Deploy-Native $NativeRest }
      "logs" { Get-ChildItem (Join-Path $EasyGateHome "logs") -Filter "native-*.log" -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "==> $($_.FullName)"; Get-Content $_.FullName -Tail 80 } }
      default { Fail "未知 native 命令：$NativeCommand" }
    }
  }
  "start" { Start-Services }
  "stop" { Stop-Services }
  "restart" { Restart-Services }
  "ps" { Invoke-EasyGateCompose ps }
  "logs" { Invoke-EasyGateCompose logs -f traefik cloudflared }
  "config" { Invoke-EasyGateCompose config }
  "demo" {
    $DemoSub = if ($Rest.Count -gt 0) { $Rest[0] } else { "start" }
    switch ($DemoSub) {
      "start" { Invoke-EasyGateCompose --profile demo up -d demo-api demo-test-api }
      "stop" {
        Invoke-EasyGateCompose --profile demo stop demo-api demo-test-api
        Invoke-EasyGateCompose --profile demo rm -f demo-api demo-test-api
      }
      "restart" {
        Invoke-EasyGateCompose --profile demo stop demo-api demo-test-api
        Invoke-EasyGateCompose --profile demo rm -f demo-api demo-test-api
        Invoke-EasyGateCompose --profile demo up -d demo-api demo-test-api
      }
      default { Fail "未知 demo 子命令：$DemoSub。可用：start|stop|restart" }
    }
  }
  "home" { Write-Host $EasyGateHome }
  "version" { Write-Host $Version }
  "uninstall" {
    Invoke-Uninstall
  }
  "-h" { Show-Usage }
  "--help" { Show-Usage }
  default { Fail "未知命令：$Command" }
}
