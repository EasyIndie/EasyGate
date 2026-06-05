$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $RootDir

function Write-Info {
  param([string]$Message)
  Write-Host "[test] $Message" -ForegroundColor Blue
}

function Fail {
  param([string]$Message)
  Write-Host "[test] $Message" -ForegroundColor Red
  exit 1
}

function Require-File {
  param([string]$Path)
  if (-not (Test-Path $Path -PathType Leaf)) {
    Fail "缺少文件：$Path"
  }
}

Write-Info "检查关键文件"
@(
  ".env.example",
  ".github/dependabot.yml",
  ".github/workflows/ci.yml",
  ".github/workflows/release.yml",
  "docker-compose.yml",
  "docker-compose.local.yml",
  "traefik/traefik.yml",
  "traefik/dynamic/localhost-services.yml",
  "cloudflared/config.yml.example",
  "scripts/test.sh",
  "scripts/test.ps1",
  "scripts/cleanup.sh",
  "scripts/cleanup.ps1",
  "scripts/cleanup-native.sh",
  "scripts/cleanup-native.ps1",
  "scripts/deploy.sh",
  "scripts/deploy.ps1",
  "scripts/deploy-native.sh",
  "scripts/deploy-native.ps1",
  "scripts/uninstall.sh",
  "scripts/uninstall.ps1",
  "scripts/local-acceptance.sh",
  "scripts/local-acceptance.ps1",
  "scripts/local-acceptance-native.sh",
  "scripts/local-acceptance-native.ps1",
  "scripts/behavior-test.sh",
  "scripts/behavior-test.ps1",
  "scripts/native-demo-server.py",
  "scripts/compose.sh",
  "scripts/lib.sh",
  "scripts/easygate",
  "scripts/easygate.ps1",
  "scripts/install.sh",
  "scripts/install.ps1"
) | ForEach-Object { Require-File $_ }

Write-Info "检查旧项目名残留"
$OldNameMatches = Get-ChildItem -Recurse -File |
  Where-Object { $_.FullName -notmatch "\\.git\\" } |
  Select-String -Pattern "[E]asyTLS|[e]asytls|[E]ASYTLS" -ErrorAction SilentlyContinue

if ($OldNameMatches) {
  $OldNameMatches | Format-Table Path, LineNumber, Line -AutoSize
  Fail "发现旧项目名残留"
}

Write-Info "检查 PowerShell 脚本语法"
@(
  "scripts/test.ps1",
  "scripts/cleanup.ps1",
  "scripts/cleanup-native.ps1",
  "scripts/deploy.ps1",
  "scripts/deploy-native.ps1",
  "scripts/easygate.ps1",
  "scripts/install.ps1",
  "scripts/uninstall.ps1",
  "scripts/local-acceptance.ps1",
  "scripts/local-acceptance-native.ps1",
  "scripts/behavior-test.ps1"
) | ForEach-Object {
  $ParseErrors = $null
  $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content -Raw $_), [ref]$ParseErrors)
  if ($ParseErrors) {
    $ParseErrors | Format-List
    Fail "$_ 存在语法错误"
  }
}

Write-Info "检查 .env.example 默认值"
$ExampleEnv = @{}
Get-Content .env.example | ForEach-Object {
  $Line = $_.Trim()
  if ($Line -eq "" -or $Line.StartsWith("#")) {
    return
  }
  $Parts = $Line.Split("=", 2)
  if ($Parts.Length -eq 2) {
    $ExampleEnv[$Parts[0]] = $Parts[1]
  }
}

if (-not $ExampleEnv.ContainsKey("BASE_DOMAIN") -or $ExampleEnv["BASE_DOMAIN"] -ne "example.com") {
  Fail ".env.example 缺少 BASE_DOMAIN 默认值"
}
if (-not $ExampleEnv.ContainsKey("TRAEFIK_HTTP_PORT") -or $ExampleEnv["TRAEFIK_HTTP_PORT"] -ne "18080") {
  Fail ".env.example 缺少 TRAEFIK_HTTP_PORT 默认值"
}
if (-not $ExampleEnv.ContainsKey("TRAEFIK_DASHBOARD_HOST") -or $ExampleEnv["TRAEFIK_DASHBOARD_HOST"] -ne "traefik.example.com") {
  Fail ".env.example 缺少 dashboard host 默认值"
}

Write-Info "检查 Traefik 网络命名"
$ComposeText = Get-Content -Raw docker-compose.yml
$TraefikText = Get-Content -Raw traefik/traefik.yml
$ExampleText = Get-Content -Raw examples/docker-service.compose.yml

if ($ComposeText -notmatch "easygate-proxy") {
  Fail "docker-compose.yml 缺少 easygate-proxy"
}
if ($TraefikText -notmatch "network:\s+easygate-proxy") {
  Fail "traefik.yml 未指向 easygate-proxy"
}
if ($ExampleText -notmatch "traefik\.docker\.network=easygate-proxy") {
  Fail "示例服务未使用 easygate-proxy"
}

Write-Info "检查 cloudflared 自动安装入口"
$DeploySh = Get-Content -Raw scripts/deploy.sh
$DeployPs = Get-Content -Raw scripts/deploy.ps1
$EasyGateSh = Get-Content -Raw scripts/easygate
$EasyGatePs = Get-Content -Raw scripts/easygate.ps1
$InstallSh = Get-Content -Raw scripts/install.sh
$InstallPs = Get-Content -Raw scripts/install.ps1

if ($DeploySh -notmatch "--no-install-cloudflared") {
  Fail "deploy.sh 缺少 cloudflared 自动安装开关"
}
$LibSh = Get-Content -Raw scripts/lib.sh
if ($LibSh -notmatch "EASYGATE_CLOUDFLARED_HOME") {
  Fail "lib.sh 缺少 cloudflared home 覆盖入口"
}
if ($DeploySh -notmatch "EASYGATE_HOME") {
  Fail "deploy.sh 缺少 EASYGATE_HOME 运行时目录"
}
if ($DeployPs -notmatch "EASYGATE_CLOUDFLARED_HOME") {
  Fail "deploy.ps1 缺少 cloudflared home 覆盖入口"
}
if ($DeployPs -notmatch "EASYGATE_HOME") {
  Fail "deploy.ps1 缺少 EASYGATE_HOME 运行时目录"
}
if ($EasyGateSh -notmatch "EASYGATE_HOME") {
  Fail "easygate CLI 缺少 EASYGATE_HOME 运行时目录"
}
if ($EasyGatePs -notmatch "EASYGATE_HOME") {
  Fail "easygate.ps1 缺少 EASYGATE_HOME 运行时目录"
}
if ($InstallSh -notmatch "EASYGATE_LOCAL_CLI") {
  Fail "install.sh 缺少本地 CLI 安装测试入口"
}
if ($InstallPs -notmatch "EASYGATE_LOCAL_CLI") {
  Fail "install.ps1 缺少本地 CLI 安装测试入口"
}
if ($LibSh -notmatch "cloudflared-linux-") {
  Fail "lib.sh 缺少 Linux cloudflared 下载逻辑"
}
if ($LibSh -notmatch "cloudflared-darwin-") {
  Fail "lib.sh 缺少 macOS cloudflared 下载逻辑"
}
# Standalone CLI must have its own copies of download logic:
if ($EasyGateSh -notmatch "cloudflared-linux-") {
  Fail "easygate CLI 缺少 Linux cloudflared 下载逻辑"
}
if ($EasyGateSh -notmatch "cloudflared-darwin-") {
  Fail "easygate CLI 缺少 macOS cloudflared 下载逻辑"
}
if ($DeployPs -notmatch "cloudflared-windows-") {
  Fail "deploy.ps1 缺少 Windows cloudflared 下载逻辑"
}
if ($EasyGatePs -notmatch "cloudflared-windows-") {
  Fail "easygate.ps1 缺少 Windows cloudflared 下载逻辑"
}

Write-Info "检查原生模式入口"
$DeployNativeSh = Get-Content -Raw scripts/deploy-native.sh
$DeployNativePs = Get-Content -Raw scripts/deploy-native.ps1
$LocalNativePs = Get-Content -Raw scripts/local-acceptance-native.ps1
if ($DeployNativeSh -notmatch "--local-only") {
  Fail "deploy-native.sh 缺少 local-only 验收入口"
}
if ($LibSh -notmatch "traefik_v") {
  Fail "lib.sh 缺少 Traefik 下载逻辑"
}
if ($EasyGateSh -notmatch "traefik_v") {
  Fail "easygate CLI 缺少 Traefik 下载逻辑"
}
if ($DeployNativeSh -notmatch "config.native.yml") {
  Fail "deploy-native.sh 缺少原生 cloudflared 配置"
}
if ($DeployNativeSh -notmatch "providers:") {
  Fail "deploy-native.sh 缺少原生 Traefik 配置生成"
}
if ($DeployNativePs -notmatch "config.native.yml") {
  Fail "deploy-native.ps1 缺少原生 cloudflared 配置"
}
if ($LocalNativePs -notmatch "EASYGATE_CLI") {
  Fail "local-acceptance-native.ps1 缺少独立 CLI 覆盖入口"
}
if ($DeploySh -notmatch "assert_no_native_deployment") {
  Fail "deploy.sh 缺少原生模式互斥检查"
}
if ($DeployNativeSh -notmatch "assert_no_compose_deployment") {
  Fail "deploy-native.sh 缺少 Compose 模式互斥检查"
}
if ($DeployPs -notmatch "Test-NativeDeploymentActive") {
  Fail "deploy.ps1 缺少原生模式互斥检查"
}
if ($DeployNativePs -notmatch "Test-ComposeDeploymentActive") {
  Fail "deploy-native.ps1 缺少 Compose 模式互斥检查"
}

Write-Info "检查 GitHub Actions Node 24 兼容配置"
$WorkflowText = Get-Content -Raw ".github/workflows/ci.yml"
$ReleaseText = Get-Content -Raw ".github/workflows/release.yml"
if ($WorkflowText -notmatch "FORCE_JAVASCRIPT_ACTIONS_TO_NODE24") {
  Fail "CI 缺少 Node 24 opt-in"
}
if ($WorkflowText -notmatch "actions/checkout@v6") {
  Fail "CI 未使用支持 Node 24 的 checkout 版本"
}
if ($ReleaseText -notmatch "SHA256SUMS") {
  Fail "Release workflow 缺少校验和产物"
}

Write-Info "检查文档链接文件是否存在"
$DocFiles = @("README.md") + (Get-ChildItem docs -Filter "*.md" | ForEach-Object { $_.FullName })
foreach ($File in $DocFiles) {
  $Text = Get-Content -Raw $File
  $Matches = [regex]::Matches($Text, "\[[^\]]+\]\(([^)]+)\)")
  foreach ($Match in $Matches) {
    $Link = $Match.Groups[1].Value
    if ($Link -match "^(https?://|mailto:|#)" -or [string]::IsNullOrWhiteSpace($Link)) {
      continue
    }

    $PathOnly = ($Link -split "#", 2)[0]
    if (-not $PathOnly.EndsWith(".md")) {
      continue
    }

    if ($PathOnly.StartsWith("docs/")) {
      $Target = $PathOnly
    }
    else {
      $SourceDir = Split-Path -Parent $File
      if ([string]::IsNullOrWhiteSpace($SourceDir)) {
        $SourceDir = "."
      }
      $Target = Join-Path $SourceDir $PathOnly
    }

    if (-not (Test-Path $Target -PathType Leaf)) {
      Fail "文档链接指向不存在的文件：$File -> $Link"
    }
  }
}

Write-Info "运行 PowerShell 行为测试"
& ".\scripts\behavior-test.ps1"
if ($LASTEXITCODE -ne 0) {
  Fail "PowerShell 行为测试失败（exit code: $LASTEXITCODE）"
}

Write-Info "检查 Docker Compose 配置"
if (Get-Command docker -ErrorAction SilentlyContinue) {
  try {
    docker compose version | Out-Null
    docker compose --env-file .env.example config | Out-Null
  }
  catch {
    Write-Host "[test] Docker Compose 不可用，跳过 Compose 配置检查" -ForegroundColor Yellow
  }
}
else {
  Write-Host "[test] 未找到 docker，跳过 Compose 配置检查" -ForegroundColor Yellow
}

Write-Info "全部检查通过"
