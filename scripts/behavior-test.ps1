$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("easygate-behavior-" + [System.Guid]::NewGuid().ToString("N"))

function Write-Info {
  param([string]$Message)
  Write-Host "[behavior] $Message" -ForegroundColor Blue
}

function Fail {
  param([string]$Message)
  Write-Host "[behavior] $Message" -ForegroundColor Red
  exit 1
}

function Assert-File {
  param([string]$Path)
  if (-not (Test-Path $Path -PathType Leaf)) {
    Fail "缺少文件：$Path"
  }
}

function Assert-Missing {
  param([string]$Path)
  if (Test-Path $Path) {
    Fail "不应存在：$Path"
  }
}

function Assert-Contains {
  param(
    [string]$Path,
    [string]$Text
  )
  $Content = Get-Content -Raw $Path
  if (-not $Content.Contains($Text)) {
    Fail "$Path 未包含：$Text"
  }
}

function New-Fixture {
  param([string]$Destination)
  New-Item -ItemType Directory -Force -Path $Destination | Out-Null
  Copy-Item -Recurse (Join-Path $RootDir "scripts") $Destination
  Copy-Item -Recurse (Join-Path $RootDir "traefik") $Destination
  Copy-Item -Recurse (Join-Path $RootDir "cloudflared") $Destination
  Copy-Item (Join-Path $RootDir "docker-compose.yml") $Destination
  Copy-Item (Join-Path $RootDir "docker-compose.local.yml") $Destination
  Copy-Item (Join-Path $RootDir ".env.example") $Destination
}

function New-MockBin {
  param(
    [string]$BinDir,
    [string]$LogFile
  )
  New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
  "" | Set-Content -Path $LogFile
  $DockerScript = Join-Path $BinDir "docker.ps1"
  $CloudflaredScript = Join-Path $BinDir "cloudflared.ps1"
  $TraefikScript = Join-Path $BinDir "traefik.ps1"
  if ($IsWindows) {
    $DockerScript = Join-Path $BinDir "docker.mock.ps1"
    $CloudflaredScript = Join-Path $BinDir "cloudflared.mock.ps1"
    $TraefikScript = Join-Path $BinDir "traefik.mock.ps1"
  }

  @'
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$CommandArgs)
Add-Content -Path $env:EASYGATE_MOCK_LOG -Value ("docker " + ($CommandArgs -join " "))
$CommandText = $CommandArgs -join " "
if ($CommandText.Contains(" ps --services --status running")) {
  if ($env:EASYGATE_MOCK_COMPOSE_RUNNING -eq "true") {
    Write-Output "traefik"
    Write-Output "cloudflared"
  }
}
exit 0
'@ | Set-Content -Path $DockerScript -Encoding UTF8

  @'
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$CommandArgs)
Add-Content -Path $env:EASYGATE_MOCK_LOG -Value ("cloudflared " + ($CommandArgs -join " "))
if ($CommandArgs.Count -ge 2 -and $CommandArgs[0] -eq "tunnel" -and $CommandArgs[1] -eq "create") {
  exit 1
}
exit 0
'@ | Set-Content -Path $CloudflaredScript -Encoding UTF8

  @'
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$CommandArgs)
Add-Content -Path $env:EASYGATE_MOCK_LOG -Value ("traefik " + ($CommandArgs -join " "))
exit 0
'@ | Set-Content -Path $TraefikScript -Encoding UTF8

  if ($IsWindows) {
    "@pwsh -NoProfile -ExecutionPolicy Bypass -File ""$DockerScript"" %*" |
      Set-Content -Path (Join-Path $BinDir "docker.cmd") -Encoding ASCII
    "@pwsh -NoProfile -ExecutionPolicy Bypass -File ""$CloudflaredScript"" %*" |
      Set-Content -Path (Join-Path $BinDir "cloudflared.cmd") -Encoding ASCII
    "@pwsh -NoProfile -ExecutionPolicy Bypass -File ""$TraefikScript"" %*" |
      Set-Content -Path (Join-Path $BinDir "traefik.cmd") -Encoding ASCII
  }
  else {
    @"
#!/usr/bin/env sh
pwsh -NoProfile -File "$DockerScript" "`$@"
"@ | Set-Content -Path (Join-Path $BinDir "docker") -Encoding UTF8
    @"
#!/usr/bin/env sh
pwsh -NoProfile -File "$CloudflaredScript" "`$@"
"@ | Set-Content -Path (Join-Path $BinDir "cloudflared") -Encoding UTF8
    @"
#!/usr/bin/env sh
pwsh -NoProfile -File "$TraefikScript" "`$@"
"@ | Set-Content -Path (Join-Path $BinDir "traefik") -Encoding UTF8
    chmod +x "$(Join-Path $BinDir "docker")" "$(Join-Path $BinDir "cloudflared")" "$(Join-Path $BinDir "traefik")"
  }
}

function Invoke-WithMockPath {
  param(
    [string]$BinDir,
    [scriptblock]$Body
  )
  $OldPath = $env:PATH
  $Separator = [System.IO.Path]::PathSeparator
  $env:PATH = "$BinDir$Separator$OldPath"
  try {
    & $Body
  }
  finally {
    $env:PATH = $OldPath
  }
}

function Invoke-ExpectedNativeFailure {
  param(
    [scriptblock]$Body,
    [string]$Message
  )

  $HadNativePreference = Test-Path Variable:PSNativeCommandUseErrorActionPreference
  if ($HadNativePreference) {
    $OldNativePreference = $PSNativeCommandUseErrorActionPreference
    $PSNativeCommandUseErrorActionPreference = $false
  }

  try {
    & $Body | Out-Null
    if ($LASTEXITCODE -eq 0) {
      Fail $Message
    }
  }
  catch {
    if ($LASTEXITCODE -eq 0) {
      throw
    }
  }
  finally {
    if ($HadNativePreference) {
      $PSNativeCommandUseErrorActionPreference = $OldNativePreference
    }
  }
}

function Test-DeployBehavior {
  $Fixture = Join-Path $TempRoot "deploy-fixture"
  $HomeDir = Join-Path $TempRoot "home"
  $RuntimeDir = Join-Path $TempRoot "runtime-deploy"
  $BinDir = Join-Path $TempRoot "bin"
  $LogFile = Join-Path $TempRoot "commands.log"

  Write-Info "验证 PowerShell 部署脚本可复用已有 tunnel"
  New-Fixture $Fixture
  New-MockBin $BinDir $LogFile
  Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $Fixture "cloudflared/config.yml"), (Join-Path $Fixture "cloudflared/easygate-home.json")

  New-Item -ItemType Directory -Force -Path (Join-Path $HomeDir ".cloudflared") | Out-Null
  Set-Content -Path (Join-Path $HomeDir ".cloudflared/cert.pem") -Value "cert"
  Set-Content -Path (Join-Path $HomeDir ".cloudflared/0000.json") -Value '{"source":"new"}'

  $OldCloudflaredHome = $env:EASYGATE_CLOUDFLARED_HOME
  $OldEasyGateHome = $env:EASYGATE_HOME
  $OldMockLog = $env:EASYGATE_MOCK_LOG
  $env:EASYGATE_CLOUDFLARED_HOME = Join-Path $HomeDir ".cloudflared"
  $env:EASYGATE_HOME = $RuntimeDir
  $env:EASYGATE_MOCK_LOG = $LogFile
  try {
    Invoke-WithMockPath $BinDir {
      Push-Location $Fixture
      try {
        & ".\scripts\deploy.ps1" -Domain "example.test" -SkipRoute -Demo -NoInstallCloudflared
        & ".\scripts\deploy.ps1" -Domain "example.test" -SkipRoute -Demo -NoInstallCloudflared
      }
      finally {
        Pop-Location
      }
    }
  }
  finally {
    $env:EASYGATE_CLOUDFLARED_HOME = $OldCloudflaredHome
    $env:EASYGATE_HOME = $OldEasyGateHome
    $env:EASYGATE_MOCK_LOG = $OldMockLog
  }

  Assert-Contains (Join-Path $RuntimeDir "compose/.env") "BASE_DOMAIN=example.test"
  Assert-Contains (Join-Path $RuntimeDir "cloudflared/config.yml") 'hostname: "*.example.test"'
  Assert-Contains (Join-Path $RuntimeDir "cloudflared/easygate-home.json") '"source":"new"'
  Assert-Missing (Join-Path $Fixture ".env")
  Assert-Missing (Join-Path $Fixture "cloudflared/config.yml")
  $CreateCalls = ([regex]::Matches((Get-Content -Raw $LogFile), "cloudflared tunnel create easygate-home")).Count
  if ($CreateCalls -ne 1) {
    Fail "重复部署时 tunnel create 调用次数应为 1，实际为 $CreateCalls"
  }
  Assert-Contains $LogFile "docker compose -p easygate"
  Assert-Contains $LogFile " up -d"
  $ComposeCalls = ([regex]::Matches((Get-Content -Raw $LogFile), "docker compose")).Count
  if ($ComposeCalls -lt 6) {
    Fail "重复启用 -Demo 后 docker compose 调用次数不足：$ComposeCalls"
  }

  $LogText = Get-Content -Raw $LogFile
  if ($LogText.Contains("cloudflared tunnel route dns")) {
    Fail "-SkipRoute 仍调用了 tunnel route dns"
  }
}

function Test-ComposeDeployBlocksNative {
  $Fixture = Join-Path $TempRoot "compose-blocks-native-fixture"
  $HomeDir = Join-Path $TempRoot "compose-blocks-native-home"
  $RuntimeDir = Join-Path $TempRoot "compose-blocks-native-runtime"
  $BinDir = Join-Path $TempRoot "compose-blocks-native-bin"
  $LogFile = Join-Path $TempRoot "compose-blocks-native.log"

  Write-Info "验证原生模式运行时 PowerShell Docker Compose 部署会被阻止"
  New-Fixture $Fixture
  New-MockBin $BinDir $LogFile

  New-Item -ItemType Directory -Force -Path (Join-Path $HomeDir ".cloudflared"), (Join-Path $RuntimeDir "run") | Out-Null
  Set-Content -Path (Join-Path $HomeDir ".cloudflared/cert.pem") -Value "cert"
  Set-Content -Path (Join-Path $RuntimeDir "run/native-traefik.pid") -Value $PID

  $OldCloudflaredHome = $env:EASYGATE_CLOUDFLARED_HOME
  $OldEasyGateHome = $env:EASYGATE_HOME
  $OldMockLog = $env:EASYGATE_MOCK_LOG
  $env:EASYGATE_CLOUDFLARED_HOME = Join-Path $HomeDir ".cloudflared"
  $env:EASYGATE_HOME = $RuntimeDir
  $env:EASYGATE_MOCK_LOG = $LogFile
  try {
    Invoke-WithMockPath $BinDir {
      Push-Location $Fixture
      try {
        Invoke-ExpectedNativeFailure {
          & pwsh -NoProfile -File ".\scripts\deploy.ps1" -Domain "example.test" -SkipRoute -NoInstallCloudflared
        } "原生模式运行时 deploy.ps1 不应继续部署"
      }
      finally {
        Pop-Location
      }
    }
  }
  finally {
    $env:EASYGATE_CLOUDFLARED_HOME = $OldCloudflaredHome
    $env:EASYGATE_HOME = $OldEasyGateHome
    $env:EASYGATE_MOCK_LOG = $OldMockLog
  }

  $LogText = Get-Content -Raw $LogFile
  if ($LogText.Contains("docker compose up -d")) {
    Fail "原生模式运行时 deploy.ps1 不应调用 docker compose up"
  }
}

function Test-CleanupBehavior {
  $Fixture = Join-Path $TempRoot "cleanup-fixture"
  $RuntimeDir = Join-Path $TempRoot "cleanup-runtime"
  $BinDir = Join-Path $TempRoot "cleanup-bin"
  $LogFile = Join-Path $TempRoot "cleanup-commands.log"

  Write-Info "验证 PowerShell 清理脚本删除范围"
  New-Fixture $Fixture
  New-MockBin $BinDir $LogFile

  New-Item -ItemType Directory -Force -Path (Join-Path $RuntimeDir "compose"), (Join-Path $RuntimeDir "cloudflared") | Out-Null
  Set-Content -Path (Join-Path $RuntimeDir "compose/docker-compose.yml") -Value "compose"
  Set-Content -Path (Join-Path $RuntimeDir "compose/.env") -Value "env"
  Set-Content -Path (Join-Path $RuntimeDir "cloudflared/config.yml") -Value "config"
  Set-Content -Path (Join-Path $RuntimeDir "cloudflared/easygate-home.json") -Value "secret"

  Invoke-WithMockPath $BinDir {
    Push-Location $Fixture
    try {
      $env:EASYGATE_HOME = $RuntimeDir
      & ".\scripts\cleanup.ps1"
    }
    finally {
      Remove-Item Env:EASYGATE_HOME -ErrorAction SilentlyContinue
      Pop-Location
    }
  }
  Assert-File (Join-Path $RuntimeDir "compose/.env")
  Assert-File (Join-Path $RuntimeDir "cloudflared/config.yml")
  Assert-File (Join-Path $RuntimeDir "cloudflared/easygate-home.json")

  Invoke-WithMockPath $BinDir {
    Push-Location $Fixture
    try {
      $env:EASYGATE_HOME = $RuntimeDir
      $env:EASYGATE_CONFIRM_PURGE = "no"
      & ".\scripts\cleanup.ps1" -Purge
    }
    finally {
      Remove-Item Env:EASYGATE_HOME -ErrorAction SilentlyContinue
      Remove-Item Env:EASYGATE_CONFIRM_PURGE -ErrorAction SilentlyContinue
      Pop-Location
    }
  }
  Assert-File (Join-Path $RuntimeDir "compose/.env")
  Assert-File (Join-Path $RuntimeDir "cloudflared/easygate-home.json")

  Invoke-WithMockPath $BinDir {
    Push-Location $Fixture
    try {
      $env:EASYGATE_HOME = $RuntimeDir
      $env:EASYGATE_CONFIRM_PURGE = "yes"
      & ".\scripts\cleanup.ps1" -Purge
    }
    finally {
      Remove-Item Env:EASYGATE_HOME -ErrorAction SilentlyContinue
      Remove-Item Env:EASYGATE_CONFIRM_PURGE -ErrorAction SilentlyContinue
      Pop-Location
    }
  }
  Assert-Missing $RuntimeDir
}

function Test-NativeDeployBehavior {
  $Fixture = Join-Path $TempRoot "native-deploy-fixture"
  $HomeDir = Join-Path $TempRoot "native-home"
  $RuntimeDir = Join-Path $TempRoot "runtime-native"
  $BinDir = Join-Path $TempRoot "native-bin"
  $LogFile = Join-Path $TempRoot "native-commands.log"

  Write-Info "验证 PowerShell 原生部署脚本生成 file provider 配置"
  New-Fixture $Fixture
  New-MockBin $BinDir $LogFile
  Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $Fixture "cloudflared/config.yml"), (Join-Path $Fixture "cloudflared/easygate-home.json")

  New-Item -ItemType Directory -Force -Path (Join-Path $HomeDir ".cloudflared") | Out-Null
  Set-Content -Path (Join-Path $HomeDir ".cloudflared/cert.pem") -Value "cert"
  Set-Content -Path (Join-Path $HomeDir ".cloudflared/0000.json") -Value '{"source":"native"}'

  $OldCloudflaredHome = $env:EASYGATE_CLOUDFLARED_HOME
  $OldEasyGateHome = $env:EASYGATE_HOME
  $OldMockLog = $env:EASYGATE_MOCK_LOG
  $env:EASYGATE_CLOUDFLARED_HOME = Join-Path $HomeDir ".cloudflared"
  $env:EASYGATE_HOME = $RuntimeDir
  $env:EASYGATE_MOCK_LOG = $LogFile
  try {
    Invoke-WithMockPath $BinDir {
      Push-Location $Fixture
      try {
        & ".\scripts\deploy-native.ps1" -Domain "example.test" -SkipRoute -NoInstallCloudflared -NoInstallTraefik
        & ".\scripts\deploy-native.ps1" -Domain "example.test" -SkipRoute -NoInstallCloudflared -NoInstallTraefik
      }
      finally {
        Pop-Location
      }
    }
  }
  finally {
    $env:EASYGATE_CLOUDFLARED_HOME = $OldCloudflaredHome
    $env:EASYGATE_HOME = $OldEasyGateHome
    $env:EASYGATE_MOCK_LOG = $OldMockLog
  }

  Assert-Contains (Join-Path $RuntimeDir "native/.env") "EASYGATE_DEPLOY_MODE=native"
  Assert-Contains (Join-Path $RuntimeDir "native/traefik.yml") "providers:"
  Assert-Contains (Join-Path $RuntimeDir "native/dynamic/services.yml") "service: api@internal"
  Assert-Contains (Join-Path $RuntimeDir "cloudflared/config.native.yml") "service: http://127.0.0.1:18080"
  $CreateCalls = ([regex]::Matches((Get-Content -Raw $LogFile), "cloudflared tunnel create easygate-home")).Count
  if ($CreateCalls -ne 1) {
    Fail "重复原生部署时 tunnel create 调用次数应为 1，实际为 $CreateCalls"
  }

  $TraefikText = Get-Content -Raw (Join-Path $RuntimeDir "native/traefik.yml")
  if ($TraefikText.Contains("docker:")) {
    Fail "原生 Traefik 配置不应启用 docker provider"
  }

  $LogText = Get-Content -Raw $LogFile
  if ($LogText.Contains("cloudflared tunnel route dns")) {
    Fail "原生部署 -SkipRoute 仍调用了 tunnel route dns"
  }
}

function Test-NativeCleanupBehavior {
  $Fixture = Join-Path $TempRoot "native-cleanup-fixture"
  $RuntimeDir = Join-Path $TempRoot "native-cleanup-runtime"

  Write-Info "验证 PowerShell 原生清理脚本删除范围"
  New-Fixture $Fixture

  New-Item -ItemType Directory -Force -Path (Join-Path $RuntimeDir "native"), (Join-Path $RuntimeDir "run"), (Join-Path $RuntimeDir "logs"), (Join-Path $RuntimeDir "cloudflared") | Out-Null
  Set-Content -Path (Join-Path $RuntimeDir "native/traefik.yml") -Value "traefik"
  Set-Content -Path (Join-Path $RuntimeDir "run/native-traefik.pid") -Value ""
  Set-Content -Path (Join-Path $RuntimeDir "logs/native-traefik.log") -Value "log"
  Set-Content -Path (Join-Path $RuntimeDir "cloudflared/config.native.yml") -Value "cloudflared"

  Push-Location $Fixture
  try {
    $env:EASYGATE_HOME = $RuntimeDir
    & ".\scripts\cleanup-native.ps1"
  }
  finally {
    Remove-Item Env:EASYGATE_HOME -ErrorAction SilentlyContinue
    Pop-Location
  }
  Assert-File (Join-Path $RuntimeDir "native/traefik.yml")
  Assert-File (Join-Path $RuntimeDir "cloudflared/config.native.yml")
  Assert-Missing (Join-Path $RuntimeDir "run/native-traefik.pid")

  Push-Location $Fixture
  try {
    $env:EASYGATE_HOME = $RuntimeDir
    & ".\scripts\cleanup-native.ps1" -Purge
  }
  finally {
    Remove-Item Env:EASYGATE_HOME -ErrorAction SilentlyContinue
    Pop-Location
  }
  Assert-Missing (Join-Path $RuntimeDir "native")
  Assert-Missing (Join-Path $RuntimeDir "run")
  Assert-Missing (Join-Path $RuntimeDir "logs")
  Assert-Missing (Join-Path $RuntimeDir "cloudflared/config.native.yml")
}

function Test-NativeDeployBlocksCompose {
  $Fixture = Join-Path $TempRoot "native-blocks-compose-fixture"
  $HomeDir = Join-Path $TempRoot "native-blocks-compose-home"
  $RuntimeDir = Join-Path $TempRoot "native-blocks-compose-runtime"
  $BinDir = Join-Path $TempRoot "native-blocks-compose-bin"
  $LogFile = Join-Path $TempRoot "native-blocks-compose.log"

  Write-Info "验证 Docker Compose 模式运行时 PowerShell 原生部署会被阻止"
  New-Fixture $Fixture
  New-MockBin $BinDir $LogFile

  New-Item -ItemType Directory -Force -Path (Join-Path $HomeDir ".cloudflared"), (Join-Path $RuntimeDir "compose") | Out-Null
  Set-Content -Path (Join-Path $HomeDir ".cloudflared/cert.pem") -Value "cert"
  Set-Content -Path (Join-Path $RuntimeDir "compose/docker-compose.yml") -Value "compose"
  Set-Content -Path (Join-Path $RuntimeDir "compose/.env") -Value "env"

  $OldCloudflaredHome = $env:EASYGATE_CLOUDFLARED_HOME
  $OldEasyGateHome = $env:EASYGATE_HOME
  $OldMockComposeRunning = $env:EASYGATE_MOCK_COMPOSE_RUNNING
  $env:EASYGATE_CLOUDFLARED_HOME = Join-Path $HomeDir ".cloudflared"
  $env:EASYGATE_HOME = $RuntimeDir
  $env:EASYGATE_MOCK_COMPOSE_RUNNING = "true"
  try {
    Invoke-WithMockPath $BinDir {
      Push-Location $Fixture
      try {
        Invoke-ExpectedNativeFailure {
          & pwsh -NoProfile -File ".\scripts\deploy-native.ps1" -Domain "example.test" -SkipRoute -NoInstallCloudflared -NoInstallTraefik
        } "Docker Compose 模式运行时 deploy-native.ps1 不应继续部署"
      }
      finally {
        Pop-Location
      }
    }
  }
  finally {
    $env:EASYGATE_CLOUDFLARED_HOME = $OldCloudflaredHome
    $env:EASYGATE_HOME = $OldEasyGateHome
    $env:EASYGATE_MOCK_LOG = $OldMockLog
    $env:EASYGATE_MOCK_COMPOSE_RUNNING = $OldMockComposeRunning
  }

  Assert-Missing (Join-Path $RuntimeDir "native/traefik.yml")
}

function Test-StandaloneCliBehavior {
  $Fixture = Join-Path $TempRoot "standalone-cli-fixture"
  $HomeDir = Join-Path $TempRoot "standalone-cli-home"
  $RuntimeDir = Join-Path $TempRoot "standalone-cli-runtime"
  $BinDir = Join-Path $TempRoot "standalone-cli-bin"
  $LogFile = Join-Path $TempRoot "standalone-cli.log"

  Write-Info "验证 PowerShell 独立 CLI 不依赖源码模板生成运行时配置"
  New-Fixture $Fixture
  New-MockBin $BinDir $LogFile
  Remove-Item -Recurse -Force -ErrorAction SilentlyContinue (Join-Path $Fixture "traefik"), (Join-Path $Fixture "cloudflared")

  New-Item -ItemType Directory -Force -Path (Join-Path $HomeDir ".cloudflared") | Out-Null
  Set-Content -Path (Join-Path $HomeDir ".cloudflared/cert.pem") -Value "cert"
  Set-Content -Path (Join-Path $HomeDir ".cloudflared/0000.json") -Value '{"source":"standalone"}'

  $OldCloudflaredHome = $env:EASYGATE_CLOUDFLARED_HOME
  $OldEasyGateHome = $env:EASYGATE_HOME
  $OldMockLog = $env:EASYGATE_MOCK_LOG
  $env:EASYGATE_CLOUDFLARED_HOME = Join-Path $HomeDir ".cloudflared"
  $env:EASYGATE_HOME = $RuntimeDir
  $env:EASYGATE_MOCK_LOG = $LogFile
  try {
    Invoke-WithMockPath $BinDir {
      Push-Location $Fixture
      try {
        & ".\scripts\easygate.ps1" deploy -Domain "example.test" -SkipRoute -Demo -NoInstallCloudflared
      }
      finally {
        Pop-Location
      }
    }
  }
  finally {
    $env:EASYGATE_CLOUDFLARED_HOME = $OldCloudflaredHome
    $env:EASYGATE_HOME = $OldEasyGateHome
    $env:EASYGATE_MOCK_LOG = $OldMockLog
  }

  Assert-Contains (Join-Path $RuntimeDir "compose/.env") "BASE_DOMAIN=example.test"
  Assert-Contains (Join-Path $RuntimeDir "traefik/traefik.yml") "providers:"
  Assert-Contains (Join-Path $RuntimeDir "cloudflared/config.yml") 'hostname: "*.example.test"'
  Assert-Contains (Join-Path $RuntimeDir "cloudflared/easygate-home.json") '"source":"standalone"'
  Assert-Contains $LogFile "docker compose -p easygate"
  Assert-Contains $LogFile " up -d"
}

function Test-StandaloneInstallBehavior {
  $Fixture = Join-Path $TempRoot "standalone-install-fixture"
  $RuntimeDir = Join-Path $TempRoot "standalone-install-runtime"

  Write-Info "验证 PowerShell 安装器可安装后直接执行 CLI"
  New-Fixture $Fixture

  $OldEasyGateHome = $env:EASYGATE_HOME
  $OldLocalCli = $env:EASYGATE_LOCAL_CLI
  $env:EASYGATE_HOME = $RuntimeDir
  $env:EASYGATE_LOCAL_CLI = Join-Path $Fixture "scripts\easygate.ps1"
  try {
    Push-Location $Fixture
    try {
      & ".\scripts\install.ps1" version | Out-Null
    }
    finally {
      Pop-Location
    }
  }
  finally {
    $env:EASYGATE_HOME = $OldEasyGateHome
    $env:EASYGATE_LOCAL_CLI = $OldLocalCli
  }

  Assert-File (Join-Path $RuntimeDir "bin/easygate.ps1")
}

try {
  New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null
  Test-DeployBehavior
  Test-ComposeDeployBlocksNative
  Test-NativeDeployBehavior
  Test-NativeDeployBlocksCompose
  Test-StandaloneCliBehavior
  Test-StandaloneInstallBehavior
  Test-CleanupBehavior
  Test-NativeCleanupBehavior
  Write-Info "PowerShell 行为测试通过"
}
finally {
  if (Test-Path $TempRoot) {
    Remove-Item $TempRoot -Recurse -Force
  }
}
