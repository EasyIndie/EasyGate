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

  @'
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
Add-Content -Path $env:EASYGATE_MOCK_LOG -Value ("docker " + ($Args -join " "))
if ($Args.Count -ge 5 -and $Args[0] -eq "compose" -and $Args[1] -eq "ps" -and $Args[2] -eq "--services" -and $Args[3] -eq "--status" -and $Args[4] -eq "running") {
  if ($env:EASYGATE_MOCK_COMPOSE_RUNNING -eq "true") {
    Write-Output "traefik"
    Write-Output "cloudflared"
  }
}
exit 0
'@ | Set-Content -Path (Join-Path $BinDir "docker.ps1") -Encoding UTF8

  @'
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
Add-Content -Path $env:EASYGATE_MOCK_LOG -Value ("cloudflared " + ($Args -join " "))
if ($Args.Count -ge 2 -and $Args[0] -eq "tunnel" -and $Args[1] -eq "create") {
  exit 1
}
exit 0
'@ | Set-Content -Path (Join-Path $BinDir "cloudflared.ps1") -Encoding UTF8

  @'
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
Add-Content -Path $env:EASYGATE_MOCK_LOG -Value ("traefik " + ($Args -join " "))
exit 0
'@ | Set-Content -Path (Join-Path $BinDir "traefik.ps1") -Encoding UTF8

  if ($IsWindows) {
    "@pwsh -NoProfile -ExecutionPolicy Bypass -File ""$BinDir\docker.ps1"" %*" |
      Set-Content -Path (Join-Path $BinDir "docker.cmd") -Encoding ASCII
    "@pwsh -NoProfile -ExecutionPolicy Bypass -File ""$BinDir\cloudflared.ps1"" %*" |
      Set-Content -Path (Join-Path $BinDir "cloudflared.cmd") -Encoding ASCII
    "@pwsh -NoProfile -ExecutionPolicy Bypass -File ""$BinDir\traefik.ps1"" %*" |
      Set-Content -Path (Join-Path $BinDir "traefik.cmd") -Encoding ASCII
  }
  else {
    @"
#!/usr/bin/env sh
pwsh -NoProfile -File "$BinDir/docker.ps1" "`$@"
"@ | Set-Content -Path (Join-Path $BinDir "docker") -Encoding UTF8
    @"
#!/usr/bin/env sh
pwsh -NoProfile -File "$BinDir/cloudflared.ps1" "`$@"
"@ | Set-Content -Path (Join-Path $BinDir "cloudflared") -Encoding UTF8
    @"
#!/usr/bin/env sh
pwsh -NoProfile -File "$BinDir/traefik.ps1" "`$@"
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

function Test-DeployBehavior {
  $Fixture = Join-Path $TempRoot "deploy-fixture"
  $HomeDir = Join-Path $TempRoot "home"
  $BinDir = Join-Path $TempRoot "bin"
  $LogFile = Join-Path $TempRoot "commands.log"

  Write-Info "验证 PowerShell 部署脚本可复用已有 tunnel"
  New-Fixture $Fixture
  New-MockBin $BinDir $LogFile

  New-Item -ItemType Directory -Force -Path (Join-Path $HomeDir ".cloudflared") | Out-Null
  Set-Content -Path (Join-Path $HomeDir ".cloudflared/cert.pem") -Value "cert"
  Set-Content -Path (Join-Path $HomeDir ".cloudflared/0000.json") -Value '{"source":"new"}'
  Set-Content -Path (Join-Path $Fixture "cloudflared/easygate-home.json") -Value '{"source":"old"}'

  $OldCloudflaredHome = $env:EASYGATE_CLOUDFLARED_HOME
  $env:EASYGATE_CLOUDFLARED_HOME = Join-Path $HomeDir ".cloudflared"
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
  }

  Assert-Contains (Join-Path $Fixture ".env") "BASE_DOMAIN=example.test"
  Assert-Contains (Join-Path $Fixture "cloudflared/config.yml") 'hostname: "*.example.test"'
  Assert-Contains (Join-Path $Fixture "cloudflared/easygate-home.json") '"source":"new"'
  Assert-Contains $LogFile "cloudflared tunnel create easygate-home"
  Assert-Contains $LogFile "docker compose up -d"
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
  $BinDir = Join-Path $TempRoot "compose-blocks-native-bin"
  $LogFile = Join-Path $TempRoot "compose-blocks-native.log"

  Write-Info "验证原生模式运行时 PowerShell Docker Compose 部署会被阻止"
  New-Fixture $Fixture
  New-MockBin $BinDir $LogFile

  New-Item -ItemType Directory -Force -Path (Join-Path $HomeDir ".cloudflared"), (Join-Path $Fixture ".easygate/run") | Out-Null
  Set-Content -Path (Join-Path $HomeDir ".cloudflared/cert.pem") -Value "cert"
  Set-Content -Path (Join-Path $Fixture ".easygate/run/native-traefik.pid") -Value $PID

  $OldCloudflaredHome = $env:EASYGATE_CLOUDFLARED_HOME
  $env:EASYGATE_CLOUDFLARED_HOME = Join-Path $HomeDir ".cloudflared"
  try {
    Invoke-WithMockPath $BinDir {
      Push-Location $Fixture
      try {
        & pwsh -NoProfile -File ".\scripts\deploy.ps1" -Domain "example.test" -SkipRoute -NoInstallCloudflared | Out-Null
        if ($LASTEXITCODE -eq 0) {
          Fail "原生模式运行时 deploy.ps1 不应继续部署"
        }
      }
      finally {
        Pop-Location
      }
    }
  }
  finally {
    $env:EASYGATE_CLOUDFLARED_HOME = $OldCloudflaredHome
  }

  $LogText = Get-Content -Raw $LogFile
  if ($LogText.Contains("docker compose up -d")) {
    Fail "原生模式运行时 deploy.ps1 不应调用 docker compose up"
  }
}

function Test-CleanupBehavior {
  $Fixture = Join-Path $TempRoot "cleanup-fixture"
  $BinDir = Join-Path $TempRoot "cleanup-bin"
  $LogFile = Join-Path $TempRoot "cleanup-commands.log"

  Write-Info "验证 PowerShell 清理脚本删除范围"
  New-Fixture $Fixture
  New-MockBin $BinDir $LogFile

  New-Item -ItemType Directory -Force -Path (Join-Path $Fixture ".easygate") | Out-Null
  Set-Content -Path (Join-Path $Fixture ".env") -Value "env"
  Set-Content -Path (Join-Path $Fixture ".easygate/tool") -Value "tool"
  Set-Content -Path (Join-Path $Fixture "cloudflared/config.yml") -Value "config"
  Set-Content -Path (Join-Path $Fixture "cloudflared/easygate-home.json") -Value "secret"

  Invoke-WithMockPath $BinDir {
    Push-Location $Fixture
    try {
      & ".\scripts\cleanup.ps1"
    }
    finally {
      Pop-Location
    }
  }
  Assert-File (Join-Path $Fixture ".env")
  Assert-File (Join-Path $Fixture "cloudflared/config.yml")
  Assert-File (Join-Path $Fixture "cloudflared/easygate-home.json")

  Invoke-WithMockPath $BinDir {
    Push-Location $Fixture
    try {
      $env:EASYGATE_CONFIRM_PURGE = "no"
      & ".\scripts\cleanup.ps1" -Purge
    }
    finally {
      Remove-Item Env:EASYGATE_CONFIRM_PURGE -ErrorAction SilentlyContinue
      Pop-Location
    }
  }
  Assert-File (Join-Path $Fixture ".env")
  Assert-File (Join-Path $Fixture "cloudflared/easygate-home.json")

  Invoke-WithMockPath $BinDir {
    Push-Location $Fixture
    try {
      $env:EASYGATE_CONFIRM_PURGE = "yes"
      & ".\scripts\cleanup.ps1" -Purge
    }
    finally {
      Remove-Item Env:EASYGATE_CONFIRM_PURGE -ErrorAction SilentlyContinue
      Pop-Location
    }
  }
}

function Test-NativeDeployBehavior {
  $Fixture = Join-Path $TempRoot "native-deploy-fixture"
  $HomeDir = Join-Path $TempRoot "native-home"
  $BinDir = Join-Path $TempRoot "native-bin"
  $LogFile = Join-Path $TempRoot "native-commands.log"

  Write-Info "验证 PowerShell 原生部署脚本生成 file provider 配置"
  New-Fixture $Fixture
  New-MockBin $BinDir $LogFile

  New-Item -ItemType Directory -Force -Path (Join-Path $HomeDir ".cloudflared") | Out-Null
  Set-Content -Path (Join-Path $HomeDir ".cloudflared/cert.pem") -Value "cert"
  Set-Content -Path (Join-Path $HomeDir ".cloudflared/0000.json") -Value '{"source":"native"}'

  $OldCloudflaredHome = $env:EASYGATE_CLOUDFLARED_HOME
  $env:EASYGATE_CLOUDFLARED_HOME = Join-Path $HomeDir ".cloudflared"
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
  }

  Assert-Contains (Join-Path $Fixture ".env") "EASYGATE_DEPLOY_MODE=native"
  Assert-Contains (Join-Path $Fixture ".easygate/native/traefik.yml") "providers:"
  Assert-Contains (Join-Path $Fixture ".easygate/native/dynamic/services.yml") "service: api@internal"
  Assert-Contains (Join-Path $Fixture "cloudflared/config.native.yml") "service: http://127.0.0.1:18080"
  Assert-Contains $LogFile "cloudflared tunnel create easygate-home"

  $TraefikText = Get-Content -Raw (Join-Path $Fixture ".easygate/native/traefik.yml")
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

  Write-Info "验证 PowerShell 原生清理脚本删除范围"
  New-Fixture $Fixture

  New-Item -ItemType Directory -Force -Path (Join-Path $Fixture ".easygate/native"), (Join-Path $Fixture ".easygate/run"), (Join-Path $Fixture ".easygate/logs"), (Join-Path $Fixture "cloudflared") | Out-Null
  Set-Content -Path (Join-Path $Fixture ".easygate/native/traefik.yml") -Value "traefik"
  Set-Content -Path (Join-Path $Fixture ".easygate/run/native-traefik.pid") -Value ""
  Set-Content -Path (Join-Path $Fixture ".easygate/logs/native-traefik.log") -Value "log"
  Set-Content -Path (Join-Path $Fixture "cloudflared/config.native.yml") -Value "cloudflared"

  Push-Location $Fixture
  try {
    & ".\scripts\cleanup-native.ps1"
  }
  finally {
    Pop-Location
  }
  Assert-File (Join-Path $Fixture ".easygate/native/traefik.yml")
  Assert-File (Join-Path $Fixture "cloudflared/config.native.yml")
  Assert-Missing (Join-Path $Fixture ".easygate/run/native-traefik.pid")

  Push-Location $Fixture
  try {
    & ".\scripts\cleanup-native.ps1" -Purge
  }
  finally {
    Pop-Location
  }
  Assert-Missing (Join-Path $Fixture ".easygate/native")
  Assert-Missing (Join-Path $Fixture ".easygate/run")
  Assert-Missing (Join-Path $Fixture ".easygate/logs")
  Assert-Missing (Join-Path $Fixture "cloudflared/config.native.yml")
}

function Test-NativeDeployBlocksCompose {
  $Fixture = Join-Path $TempRoot "native-blocks-compose-fixture"
  $HomeDir = Join-Path $TempRoot "native-blocks-compose-home"
  $BinDir = Join-Path $TempRoot "native-blocks-compose-bin"
  $LogFile = Join-Path $TempRoot "native-blocks-compose.log"

  Write-Info "验证 Docker Compose 模式运行时 PowerShell 原生部署会被阻止"
  New-Fixture $Fixture
  New-MockBin $BinDir $LogFile

  New-Item -ItemType Directory -Force -Path (Join-Path $HomeDir ".cloudflared") | Out-Null
  Set-Content -Path (Join-Path $HomeDir ".cloudflared/cert.pem") -Value "cert"

  $OldCloudflaredHome = $env:EASYGATE_CLOUDFLARED_HOME
  $OldMockComposeRunning = $env:EASYGATE_MOCK_COMPOSE_RUNNING
  $env:EASYGATE_CLOUDFLARED_HOME = Join-Path $HomeDir ".cloudflared"
  $env:EASYGATE_MOCK_COMPOSE_RUNNING = "true"
  try {
    Invoke-WithMockPath $BinDir {
      Push-Location $Fixture
      try {
        & pwsh -NoProfile -File ".\scripts\deploy-native.ps1" -Domain "example.test" -SkipRoute -NoInstallCloudflared -NoInstallTraefik | Out-Null
        if ($LASTEXITCODE -eq 0) {
          Fail "Docker Compose 模式运行时 deploy-native.ps1 不应继续部署"
        }
      }
      finally {
        Pop-Location
      }
    }
  }
  finally {
    $env:EASYGATE_CLOUDFLARED_HOME = $OldCloudflaredHome
    $env:EASYGATE_MOCK_COMPOSE_RUNNING = $OldMockComposeRunning
  }

  Assert-Missing (Join-Path $Fixture ".easygate/native/traefik.yml")
}

try {
  New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null
  Test-DeployBehavior
  Test-ComposeDeployBlocksNative
  Test-NativeDeployBehavior
  Test-NativeDeployBlocksCompose
  Test-CleanupBehavior
  Test-NativeCleanupBehavior
  Write-Info "PowerShell 行为测试通过"
}
finally {
  if (Test-Path $TempRoot) {
    Remove-Item $TempRoot -Recurse -Force
  }
}
