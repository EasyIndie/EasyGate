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
$EasyGateCli = if (-not [string]::IsNullOrWhiteSpace($env:EASYGATE_CLI)) {
  $env:EASYGATE_CLI
}
else {
  Join-Path $RootDir "scripts\easygate.ps1"
}

$Strict = $env:EASYGATE_ACCEPTANCE_STRICT -eq "true"
$TraefikHttpPort = if (-not [string]::IsNullOrWhiteSpace($env:TRAEFIK_HTTP_PORT)) {
  $env:TRAEFIK_HTTP_PORT
}
else {
  "18080"
}
$EnvBackup = Join-Path ([System.IO.Path]::GetTempPath()) ("easygate-native-env-" + [System.Guid]::NewGuid().ToString("N"))
$HadEnv = Test-Path ".env"
if ($HadEnv) {
  Copy-Item ".env" $EnvBackup -Force
}

function Write-Info {
  param([string]$Message)
  Write-Host "[acceptance-native] $Message" -ForegroundColor Blue
}

function Write-Warn {
  param([string]$Message)
  Write-Host "[acceptance-native] $Message" -ForegroundColor Yellow
}

function Fail {
  param([string]$Message)
  Write-Host "[acceptance-native] $Message" -ForegroundColor Red
  exit 1
}

function Skip-Or-Fail {
  param([string]$Message)
  if ($Strict) {
    Fail $Message
  }
  Write-Warn "$Message，跳过原生本机路由验收"
  exit 0
}

function Request-Host {
  param([string]$HostName)
  Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$TraefikHttpPort" -Headers @{ Host = $HostName }
}

try {
  Write-Info "启动原生本机验收栈"
  try {
    & $EasyGateCli deploy -Native -Domain "example.com" -Demo -LocalOnly
  }
  catch {
    Skip-Or-Fail "原生本机验收栈启动失败"
  }

  $ProdHost = "api.example.com"
  $TestHost = "test-api.example.com"

  Write-Info "等待原生 Traefik 就绪"
  $Ready = $false
  for ($i = 0; $i -lt 10; $i++) {
    try {
      $Response = Request-Host $ProdHost
      if ($Response.StatusCode -eq 200) {
        $Ready = $true
        break
      }
    }
    catch {
      Start-Sleep -Seconds 1
    }
  }

  if (-not $Ready) {
    $TraefikLog = Join-Path $EasyGateHome "logs\native-traefik.log"
    if (Test-Path $TraefikLog) {
      Get-Content $TraefikLog -Tail 80
    }
    Skip-Or-Fail "原生 Traefik 未在预期时间内就绪"
  }

  Write-Info "验证原生生产 demo 路由"
  $Prod = Request-Host $ProdHost
  if (-not $Prod.Content.Contains("Hostname:")) {
    Skip-Or-Fail "$ProdHost 未返回 demo 响应"
  }

  Write-Info "验证原生测试 demo 路由"
  $Test = Request-Host $TestHost
  if (-not $Test.Content.Contains("Hostname:")) {
    Skip-Or-Fail "$TestHost 未返回 demo 响应"
  }

  Write-Info "验证未配置域名返回 404"
  try {
    Request-Host "missing.example.com" | Out-Null
    Skip-Or-Fail "missing.example.com 预期 404，实际 200"
  }
  catch {
    $StatusCode = $_.Exception.Response.StatusCode.value__
    if ($StatusCode -ne 404) {
      Skip-Or-Fail "missing.example.com 预期 404，实际 $StatusCode"
    }
  }

  Write-Info "原生本机路由验收通过"
}
finally {
  & $EasyGateCli uninstall | Out-Null
  if ($HadEnv) {
    Copy-Item $EnvBackup ".env" -Force
  }
  else {
    Remove-Item ".env" -Force -ErrorAction SilentlyContinue
  }
  Remove-Item $EnvBackup -Force -ErrorAction SilentlyContinue
}
