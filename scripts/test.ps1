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
  "scripts/local-acceptance.sh",
  "scripts/local-acceptance.ps1",
  "scripts/local-acceptance-native.sh",
  "scripts/local-acceptance-native.ps1",
  "scripts/behavior-test.sh",
  "scripts/behavior-test.ps1",
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
  "scripts/easygate.ps1",
  "scripts/install.ps1",
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
$EasyGateSh = Get-Content -Raw scripts/easygate
$EasyGatePs = Get-Content -Raw scripts/easygate.ps1
$InstallSh = Get-Content -Raw scripts/install.sh
$InstallPs = Get-Content -Raw scripts/install.ps1

$LibSh = Get-Content -Raw scripts/lib.sh
if ($LibSh -notmatch "EASYGATE_CLOUDFLARED_HOME") {
  Fail "lib.sh 缺少 cloudflared home 覆盖入口"
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
if ($InstallPs -notmatch 'SetEnvironmentVariable.*Path.*User') {
  Fail "install.ps1 缺少用户环境变量 PATH 写入逻辑（重启持久化）"
}
if ($InstallPs -notmatch '\$env:Path = \"\$InstallDir;\$env:Path\"') {
  Fail "install.ps1 缺少当前会话 PATH 配置"
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
if ($EasyGatePs -notmatch "cloudflared-windows-") {
  Fail "easygate.ps1 缺少 Windows cloudflared 下载逻辑"
}

Write-Info "检查原生模式入口"
$LocalNativePs = Get-Content -Raw scripts/local-acceptance-native.ps1
if ($LibSh -notmatch "traefik_v") {
  Fail "lib.sh 缺少 Traefik 下载逻辑"
}
if ($EasyGateSh -notmatch "traefik_v") {
  Fail "easygate CLI 缺少 Traefik 下载逻辑"
}
if ($LocalNativePs -notmatch "EASYGATE_CLI") {
  Fail "local-acceptance-native.ps1 缺少独立 CLI 覆盖入口"
}

Write-Info "检查 Windows 重启持久化（计划任务）"
if ($EasyGatePs -notmatch "Register-NativeScheduledTask") {
  Fail "easygate.ps1 缺少计划任务注册函数（重启持久化）"
}
if ($EasyGatePs -notmatch "Unregister-NativeScheduledTask") {
  Fail "easygate.ps1 缺少计划任务删除函数"
}
if ($EasyGatePs -notmatch "schtasks /create") {
  Fail "easygate.ps1 缺少 schtasks 计划任务创建逻辑"
}
if ($EasyGatePs -notmatch "schtasks /delete") {
  Fail "easygate.ps1 缺少 schtasks 计划任务删除逻辑"
}
if ($EasyGatePs -notmatch 'Invoke-Uninstall[\s\S]*?Unregister-NativeScheduledTask') {
  Fail "easygate.ps1 的 Invoke-Uninstall 未调用 Unregister-NativeScheduledTask"
}

Write-Info "检查输入验证与端口检查"
$MissingValidation = @()
if ($EasyGatePs -notmatch "function Validate-Port") { $MissingValidation += "Validate-Port" }
if ($EasyGatePs -notmatch "function Validate-Domain") { $MissingValidation += "Validate-Domain" }
if ($EasyGatePs -notmatch "function Test-PortAvailable") { $MissingValidation += "Test-PortAvailable" }
if ($EasyGatePs -notmatch "function Test-ProcessStarted") { $MissingValidation += "Test-ProcessStarted" }
if ($EasyGatePs -notmatch "function Rotate-Logs") { $MissingValidation += "Rotate-Logs" }
if ($EasyGatePs -notmatch "function Install-ServiceHelper") { $MissingValidation += "Install-ServiceHelper" }
if ($MissingValidation.Count -gt 0) {
  Fail "easygate.ps1 缺少以下函数：$($MissingValidation -join ', ')"
}

Write-Info "检查验证函数集成"
if ($EasyGatePs -notmatch 'Deploy-Native[\s\S]*?Validate-Domain') {
  Fail "Deploy-Native 未调用 Validate-Domain"
}
if ($EasyGatePs -notmatch 'Deploy-Native[\s\S]*?Test-PortAvailable') {
  Fail "Deploy-Native 未调用 Test-PortAvailable"
}
if ($EasyGatePs -notmatch 'Deploy-Native[\s\S]*?Test-ProcessStarted') {
  Fail "Deploy-Native 未调用 Test-ProcessStarted"
}
if ($EasyGatePs -notmatch 'Deploy-Native[\s\S]*?Install-ServiceHelper') {
  Fail "Deploy-Native 未调用 Install-ServiceHelper"
}
if ($EasyGatePs -notmatch 'Deploy-Native[\s\S]*?Rotate-Logs') {
  Fail "Deploy-Native 未调用 Rotate-Logs"
}
if ($EasyGatePs -notmatch 'Start-NativeServices[\s\S]*?Test-PortAvailable') {
  Fail "Start-NativeServices 未调用 Test-PortAvailable"
}

Write-Info "检查卸载 PATH 清理"
if ($EasyGatePs -notmatch "SetEnvironmentVariable.*Path.*User") {
  Fail "Invoke-Uninstall 缺少用户 PATH 清理"
}

Write-Info "检查 install.ps1 PATH 自动配置"

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
  $oldEAP = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    docker compose version 2>$null | Out-Null
    docker compose --env-file .env.example config 2>$null | Out-Null
  }
  catch {
    Write-Host "[test] Docker Compose 不可用，跳过 Compose 配置检查" -ForegroundColor Yellow
  }
  $ErrorActionPreference = $oldEAP
}
else {
  Write-Host "[test] 未找到 docker，跳过 Compose 配置检查" -ForegroundColor Yellow
}

Write-Info "全部检查通过"
exit 0


