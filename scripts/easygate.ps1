# 不使用 param() 以避免 PS7 参数绑定问题。
# $args 捕获所有原始参数，由函数内部手动解析。
$CommandArgs = @($args)

# 被 dot-source 时跳过 dispatch，仅加载函数定义
if ($MyInvocation.InvocationName -eq '.') { return }

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
  easygate.ps1 deploy -Domain <domain> [-Native] [选项]
  easygate.ps1 start|stop|restart      服务管理（自动检测模式）
  easygate.ps1 ps|logs|config          状态与日志（自动检测模式）
  easygate.ps1 demo start|stop|restart Demo 服务（自动检测模式）
  easygate.ps1 service add|remove|list  自定义服务管理（自动检测模式）
  easygate.ps1 uninstall               卸载
  easygate.ps1 home|version            信息查询

service 子命令：
  easygate.ps1 service add -Name <name> -Host <hostname> -Url <url>
  easygate.ps1 service remove <name>
  easygate.ps1 service list

常用选项：
  -Domain <domain>       主域名，例如 example.com
  -Native                使用原生模式部署（无需 Docker）
  -Tunnel <name>         tunnel 名称，默认 easygate-home
  -Dashboard <hostname>  Traefik dashboard 域名，默认 traefik.<domain>
  -Port <port>           本地调试端口，默认 18080
  -SkipRoute             不自动创建 *.domain 的 DNS 路由
  -Demo                  部署后启动 demo 服务
  -NoInstallCloudflared
  -NoInstallTraefik      仅 -Native 模式支持
  -LocalOnly             仅 -Native 模式支持
  -ApiPort <port>        仅 -Native 模式，demo api 端口，默认 19080
  -TestApiPort <port>    仅 -Native 模式，demo test-api 端口，默认 19081
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
  param([string[]]$OptionArgs)
  $Options = @{}
  for ($Index = 0; $Index -lt $OptionArgs.Count; $Index++) {
    $Arg = $OptionArgs[$Index]
    switch -Regex ($Arg) {
      '^--?domain$|^-Domain$' { $Index++; $Options["Domain"] = $OptionArgs[$Index]; continue }
      '^--?tunnel$|^-Tunnel$' { $Index++; $Options["Tunnel"] = $OptionArgs[$Index]; continue }
      '^--?dashboard$|^-Dashboard$' { $Index++; $Options["Dashboard"] = $OptionArgs[$Index]; continue }
      '^--?port$|^-Port$' { $Index++; $Options["Port"] = $OptionArgs[$Index]; continue }
      '^--?api-port$|^-ApiPort$' { $Index++; $Options["ApiPort"] = $OptionArgs[$Index]; continue }
      '^--?test-api-port$|^-TestApiPort$' { $Index++; $Options["TestApiPort"] = $OptionArgs[$Index]; continue }
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

# ── 输入验证 ──────────────────────────────────────────────────────────

function Validate-Port {
  param([string]$Port, [string]$Label = "port")
  if (-not ($Port -match '^\d+$')) {
    Fail "${Label} 必须是数字：$Port"
  }
  $p = [int]$Port
  if ($p -lt 1 -or $p -gt 65535) {
    Fail "${Label} 超出范围 (1-65535)：$Port"
  }
}

function Validate-Domain {
  param([string]$Domain)
  if ($Domain -eq "example.com") {
    Fail "请使用真实域名，不要使用 example.com"
  }
  if ($Domain -notmatch '\.') {
    Fail "域名格式不正确：${Domain}（缺少顶级域）"
  }
  if ($Domain -match '\s') {
    Fail "域名不能包含空格：${Domain}"
  }
}

function Test-PortAvailable {
  param([string]$Port, [string]$Label = "port")
  $Connections = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()
  foreach ($Conn in $Connections) {
    if ($Conn.Port -eq [int]$Port) {
      Fail "${Label} $Port 已被占用，请先停止该进程再部署"
    }
  }
}

# ── 进程验证 ──────────────────────────────────────────────────────────

function Test-ProcessStarted {
  param([string]$Name)
  if ($env:EASYGATE_CI -eq "true") { return }
  Start-Sleep -Seconds 1
  $PidFile = Join-Path $EasyGateHome "run\$Name.pid"
  $LogFile = Join-Path $EasyGateHome "logs\$Name.log"
  if (-not (Test-Path $PidFile)) { return }
  $PidText = (Get-Content -Raw $PidFile).Trim()
  if ([string]::IsNullOrWhiteSpace($PidText)) { return }
  $Process = Get-Process -Id ([int]$PidText) -ErrorAction SilentlyContinue
  if (-not $Process) {
    Write-Host "[easygate] ${Name} 启动失败！日志（$LogFile）：" -ForegroundColor Red
    if (Test-Path $LogFile) { Get-Content $LogFile -Tail 20 | ForEach-Object { Write-Host "  $_" -ForegroundColor Red } }
    else { Write-Host "[easygate] 日志文件不存在" -ForegroundColor Red }
    Fail "${Name} 启动失败"
  }
}

# ── 日志轮转 ──────────────────────────────────────────────────────────

function Rotate-Logs {
  $MaxSize = if ($env:EASYGATE_LOG_MAX_SIZE) { [int]$env:EASYGATE_LOG_MAX_SIZE } else { 10485760 }
  $Keep = if ($env:EASYGATE_LOG_KEEP) { [int]$env:EASYGATE_LOG_KEEP } else { 5 }
  $LogDir = Join-Path $EasyGateHome "logs"
  if (-not (Test-Path $LogDir)) { return }
  Get-ChildItem "$LogDir\*.log" -File | ForEach-Object {
    if ($_.Length -gt $MaxSize) {
      $Base = $_.FullName
      Remove-Item "${Base}.${Keep}" -Force -ErrorAction SilentlyContinue
      for ($i = $Keep - 1; $i -ge 1; $i--) {
        $OldFile = "${Base}.${i}"
        if (Test-Path $OldFile) {
          Move-Item $OldFile "${Base}.$($i + 1)" -Force
        }
      }
      Move-Item $Base "${Base}.1" -Force
      New-Item $Base -ItemType File -Force | Out-Null
      Write-Info "已轮转日志：$($_.Name)"
    }
  }
}

function Install-ServiceHelper {
  $LibDir = Join-Path $EasyGateHome "lib"
  New-Item -ItemType Directory -Force -Path $LibDir | Out-Null
  $Target = Join-Path $LibDir "service-helper.py"
  if (Test-Path $Target) { return }
  $Embedded = @'
IyEvdXNyL2Jpbi9lbnYgcHl0aG9uMwoiIiJFYXN5R2F0ZSBzZXJ2aWNlIGhlbHBlciDigJQgYWRk
L3JlbW92ZS9saXN0IHNlcnZpY2VzIGluIFRyYWVmaWsgZHluYW1pYyBZQU1MLiIiIgoKaW1wb3J0
IHN5cywgcmUKCmRlZiBnZXRfaW5kZW50KGxpbmUpOgogICAgIiIiUmV0dXJuIGluZGVudGF0aW9u
IGxldmVsIChudW1iZXIgb2YgbGVhZGluZyBzcGFjZXMpLiIiIgogICAgcmV0dXJuIGxlbihsaW5l
KSAtIGxlbihsaW5lLmxzdHJpcCgiICIpKQoKZGVmIGdldF9zZWN0aW9uX2JvdW5kYXJpZXMobGlu
ZXMpOgogICAgIiIiRmluZCBzdGFydCBhbmQgZW5kIG9mIHJvdXRlcnMgYW5kIHNlcnZpY2VzIHNl
Y3Rpb25zLiIiIgogICAgcm91dGVyc19zdGFydCA9IHNlcnZpY2VzX3N0YXJ0ID0gLTEKICAgIGZv
ciBpLCBsaW5lIGluIGVudW1lcmF0ZShsaW5lcyk6CiAgICAgICAgcyA9IGxpbmUucnN0cmlwKCkK
ICAgICAgICBpZiBzIGluICgiICByb3V0ZXJzOiIsICIgIHJvdXRlcnM6IHt9Iik6CiAgICAgICAg
ICAgIHJvdXRlcnNfc3RhcnQgPSBpCiAgICAgICAgZWxpZiBzIGluICgiICBzZXJ2aWNlczoiLCAi
ICBzZXJ2aWNlczoge30iKToKICAgICAgICAgICAgc2VydmljZXNfc3RhcnQgPSBpCiAgICByZXR1
cm4gcm91dGVyc19zdGFydCwgc2VydmljZXNfc3RhcnQKCmRlZiBmaW5kX2VudHJpZXMobGluZXMs
IHNlY3Rpb25fc3RhcnQpOgogICAgIiIiRmluZCBlbnRyaWVzIGluIGEgWUFNTCBzZWN0aW9uIChu
YW1lcyBvZiA0LXNwYWNlIGluZGVudGVkIGJsb2NrcykuIiIiCiAgICBlbnRyaWVzID0ge30KICAg
IGlmIHNlY3Rpb25fc3RhcnQgPCAwOgogICAgICAgIHJldHVybiBlbnRyaWVzCiAgICBpID0gc2Vj
dGlvbl9zdGFydCArIDEKICAgIHdoaWxlIGkgPCBsZW4obGluZXMpOgogICAgICAgIGxpbmUgPSBs
aW5lc1tpXQogICAgICAgIGlmIG5vdCBsaW5lLnN0cmlwKCk6CiAgICAgICAgICAgIGkgKz0gMQog
ICAgICAgICAgICBjb250aW51ZQogICAgICAgIGluZGVudCA9IGdldF9pbmRlbnQobGluZSkKICAg
ICAgICBpZiBpbmRlbnQgPT0gNCAgYW5kIGxpbmUucnN0cmlwKCkuZW5kc3dpdGgoIjoiKToKICAg
ICAgICAgICAgbmFtZSA9IGxpbmUuc3RyaXAoKVstOl0KICAgICAgICAgICAgaiA9IGkgKyAxCiAg
ICAgICAgICAgIHdoaWxlIGogPCBsZW4obGluZXMpIGFuZCAoZ2V0X2luZGVudChsaW5lc1tqXSkg
PiA0IG9yIG5vdCBsaW5lc1tqXS5zdHJpcCgpKToKICAgICAgICAgICAgICAgIGogKz0gMQogICAg
ICAgICAgICBlbnRyaWVzW25hbWVdID0gKGksIGopCiAgICAgICAgICAgIGkgPSBqCiAgICAgICAg
ZWxpZiBpbmRlbnQgPD0gMjogIAogICAgICAgICAgICBicmVhawogICAgICAgIGVsc2U6CiAgICAg
ICAgICAgIGkgKz0gMQogICAgcmV0dXJuIGVudHJpZXMKCmRlZiBsaXN0X3NlcnZpY2VzKHBhdGgp
OgogICAgdHJ5OgogICAgICAgIHdpdGggb3BlbihwYXRoKSBhcyBmOgogICAgICAgICAgICBsaW5l
cyA9IGYucmVhZGxpbmVzKCkKICAgIGV4Y2VwdCBGaWxlTm90Rm91bmRFcnJvcjoKICAgICAgICBw
cmludCgi5pqC5peg5bey6YWN572u55qE5pyN5YqhIikKICAgICAgICByZXR1cm4KCiAgICByb3V0
ZXJzX3N0YXJ0LCBzZXJ2aWNlc19zdGFydCA9IGdldF9zZWN0aW9uX2JvdW5kYXJpZXMobGluZXMp
CiAgICByb3V0ZXJzID0gZmluZF9lbnRyaWVzKGxpbmVzLCByb3V0ZXJzX3N0YXJ0KQogICAgc2Vy
dmljZXMgPSBmaW5kX2VudHJpZXMobGluZXMsIHNlcnZpY2VzX3N0YXJ0KQoKICAgIGFsbF9zdmNz
ID0ge30KICAgIGZvciBuYW1lLCAoc3RhcnQsIGVuZCkgaW4gcm91dGVycy5pdGVtcygpOgogICAg
ICAgIGluZm8gPSB7Imhvc3QiOiAiPyIsICJ1cmwiOiAiPyJ9CiAgICAgICAgZm9yIGkgaW4gcmFu
Z2Uoc3RhcnQsIGVuZCk6CiAgICAgICAgICAgIHMgPSBsaW5lc1tpXS5zdHJpcCgpCiAgICAgICAg
ICAgIG0gPSByZS5zZWFyY2gociJIb3N0KGBbXildKylgXCkiLCBzKQogICAgICAgICAgICBpZiBt
OgogICAgICAgICAgICAgICAgaW5mb1siaG9zdCJdID0gbS5ncm91cCgxKQogICAgICAgICAgICBp
ZiBzLnN0YXJ0c3dpdGgoInNlcnZpY2U6ICIpIGFuZCBzICE9ICJzZXJ2aWNlOiBhcGlAaW50ZXJu
YWwiOgogICAgICAgICAgICAgICAgcGFzcwogICAgICAgIGFsbF9zdmNzW25hbWVdID0gaW5mbwoK
ICAgIGZvciBuYW1lLCAoc3RhcnQsIGVuZCkgaW4gc2VydmljZXMuaXRlbXMoKToKICAgICAgICBp
bmZvID0gYWxsX3N2Y3MuZ2V0KG5hbWUsIHsiaG9zdCI6ICI/IiwgInVybCI6ICI/In0pCiAg
ICAgICAgYWxsX3N2Y3NbbmFtZV0gPSBpbmZvCiAgICAgICAgZm9yIGkgaW4gcmFuZ2Uoc3RhcnQs
IGVuZCk6CiAgICAgICAgICAgIHMgPSBsaW5lc1tpXS5zdHJpcCgpCiAgICAgICAgICAgIGlmIHMu
c3RhcnRzd2l0aCgiLSB1cmw6Iik6CiAgICAgICAgICAgICAgICBpbmZvWyJ1cmwiXSA9IHMuc3Bs
aXQoIi0gdXJsOiIsIDEpWzFdLnN0cmlwKCkKCiAgICBpZiBhbGxfc3ZjczoKICAgICAgICBwcmlu
dChmInt9ezw2IH17OjIwfSB7OjM1fSB7On0iLmZvcm1hdCgiTmFtZSIsICJIb3N0IiwgIlVSTCIp
KQogICAgICAgIHByaW50KCItIiAqIDgwKQogICAgICAgIGZvciBuYW1lIGluIHNvcnRlZChhbGxf
c3Zjcyk6CiAgICAgICAgICAgIGluZm8gPSBhbGxfc3Zjc1tuYW1lXQogICAgICAgICAgICBwcmlu
dChmInt9ezw2IH17OjIwfSB7OjM1fSB7On0iLmZvcm1hdChuYW1lLCBpbmZvLmdldCgnaG9zdCcs
ICc/JyksIGluZm8uZ2V0KCd1cmwnLCAnPycpKSkKICAgIGVsc2U6CiAgICAgICAgcHJpbnQoIuac
gumXoOW3sumFjee9rueahOacjeWKoSIpCgpkZWYgYWRkX3NlcnZpY2UocGF0aCwgbmFtZSwgaG9z
dCwgdXJsKToKICAgIHRyeToKICAgICAgICB3aXRoIG9wZW4ocGF0aCkgYXMgZjoKICAgICAgICAg
ICAgbGluZXMgPSBmLnJlYWRsaW5lcygpCiAgICBleGNlcHQgRmlsZU5vdEZvdW5kRXJyb3I6CiAg
ICAgICAgbGluZXMgPSBbImh0dHA6XG4iLCAiICByb3V0ZXJzOiB7fVxuIiwgIiAgc2VydmljZXM6
IHt9XG4iXQoKICAgIHJvdXRlcnNfc3RhcnQsIHNlcnZpY2VzX3N0YXJ0ID0gZ2V0X3NlY3Rpb25f
Ym91bmRhcmllcyhsaW5lcykKICAgIHJvdXRlcnMgPSBmaW5kX2VudHJpZXMobGluZXMsIHJvdXRl
cnNfc3RhcnQpCiAgICBpZiBuYW1lIGluIHJvdXRlcnM6CiAgICAgICAgcHJpbnQoZiJbZWFzeWdh
dGVdIOacjeWKoSB7bmFtZX0g5bel5a2Y5ZyoIiwgZmlsZT1zeXMuc3RkZXJyKQogICAgICAgIHN5
cy5leGl0KDEpCgogICAgZm9yIGksIGxpbmUgaW4gZW51bWVyYXRlKGxpbmVzKToKICAgICAgICBp
ZiBsaW5lLnJzdHJpcCgpID09ICIgIHJvdXRlcnM6IHt9IjoKICAgICAgICAgICAgbGluZXNbaV0g
PSAiICByb3V0ZXJzOlxuIgogICAgICAgIGVsaWYgbGluZS5yc3RyaXAoKSA9PSAiICBzZXJ2aWNl
czoge30iOgogICAgICAgICAgICBsaW5lc1tpXSA9ICIgIHNlcnZpY2VzOlxuIgoKICAgIHJvdXRl
cl9ibG9jayA9IFsKICAgICAgICBmIiAgICAge25hbWV9OlxuIiwKICAgICAgICBmIiAgICAgIHJ1
bGU6IEhvc3QoYHtob3N0fWApXG4iLAogICAgICAgIGYiICAgICAgZW50cnlQb2ludHM6XG4iLAog
ICAgICAgIGYiICAgICAgICAtIHdlYlxuIiwKICAgICAgICBmIiAgICAgIHNlcnZpY2U6IHtuYW1l
fVxuIiwKICAgIF0KICAgIHNlcnZpY2VfYmxvY2sgPSBbCiAgICAgICAgZiIgICAge25hbWV9Olxu
IiwKICAgICAgICBmIiAgICAgIGxvYWRCYWxhbmNlcjpcbiIsCiAgICAgICAgZiIgICAgICAgIHNl
cnZlcnM6XG4iLAogICAgICAgIGYiICAgICAgICAgIC0gdXJsOiB7dXJsfVxuIiwKICAgIF0KCiAg
ICByb3V0ZXJzX3N0YXJ0LCBzZXJ2aWNlc19zdGFydCA9IGdldF9zZWN0aW9uX2JvdW5kYXJpZXMo
bGluZXMpCgogICAgaWYgc2VydmljZXNfc3RhcnQgPj0gMDoKICAgICAgICBmb3IgaXRlbSBpbiBy
ZXZlcnNlZChyb3V0ZXJfYmxvY2spOgogICAgICAgICAgICBsaW5lcy5pbnNlcnQoc2VydmljZXNf
c3RhcnQsIGl0ZW0pCiAgICAgICAgcm91dGVyc19zdGFydCwgc2VydmljZXNfc3RhcnQgPSBnZXRf
c2VjdGlvbl9ib3VuZGFyaWVzKGxpbmVzKQogICAgICAgIGogPSBzZXJ2aWNlc19zdGFydCArIDEK
ICAgICAgICB3aGlsZSBqIDwgbGVuKGxpbmVzKSBhbmQgKGdldF9pbmRlbnQobGluZXNbal0pID49
IDQgb3Igbm90IGxpbmVzW2pdLnN0cmlwKCkpOgogICAgICAgICAgICBqICs9IDEKICAgICAgICBm
b3IgaXRlbSBpbiByZXZlcnNlZChzZXJ2aWNlX2Jsb2NrKToKICAgICAgICAgICAgbGluZXMuaW5z
ZXJ0KGosIGl0ZW0pCiAgICBlbHNlOgogICAgICAgIGxpbmVzLmFwcGVuZCgiXG4iKQogICAgICAg
IGxpbmVzLmV4dGVuZChyb3V0ZXJfYmxvY2spCiAgICAgICAgbGluZXMuYXBwZW5kKCIgIHNlcnZp
Y2VzOlxuIikKICAgICAgICBsaW5lcy5leHRlbmQoc2VydmljZV9ibG9jaykKCiAgICB3aXRoIG9w
ZW4ocGF0aCwgInciKSBhcyBmOgogICAgICAgIGYud3JpdGVsaW5lcyhsaW5lcykKICAgIHByaW50
KGYiW2Vhc3lnYXRlXSDlt7Lmt7vliqDmnI3liqHvvJp7bmFtZX0g4oaSIHtob3N0fSDihpIge3Vy
bH0iKQoKZGVmIHJlbW92ZV9zZXJ2aWNlKHBhdGgsIG5hbWUpOgogICAgd2l0aCBvcGVuKHBhdGgp
IGFzIGY6CiAgICAgICAgbGluZXMgPSBmLnJlYWRsaW5lcygpCgogICAgcm91dGVyc19zdGFydCwg
c2VydmljZXNfc3RhcnQgPSBnZXRfc2VjdGlvbl9ib3VuZGFyaWVzKGxpbmVzKQogICAgcm91dGVy
cyA9IGZpbmRfZW50cmllcyhsaW5lcywgcm91dGVyc19zdGFydCkKICAgIGlmIG5hbWUgbm90IGlu
IHJvdXRlcnM6CiAgICAgICAgcHJpbnQoZiJbZWFzeWdhdGVdIOacjeWKoSB7bmFtZX0g5LiN5a2Y
5ZyoIiwgZmlsZT1zeXMuc3RkZXJyKQogICAgICAgIHN5cy5leGl0KDEpCgogICAgIyBFbnRyeSBz
dGFydC9lbmQgbGluZXMgYXJlIGZyb20gcm91dGVycyBkaWN0CiAgICBzdGFydCwgZW5kID0gcm91
dGVyc1tuYW1lXQoKICAgICMgUmVtb3ZlIGZyb20gZW5kIHRvIHN0YXJ0IChpbmNsdXNpdmUsIGJh
Y2t3YXJkcykKICAgIGRlbCBsaW5lc1tzdGFydDplbmQrMV0KCiAgICByb3V0ZXJzX3N0YXJ0LCBz
ZXJ2aWNlc19zdGFydCA9IGdldF9zZWN0aW9uX2JvdW5kYXJpZXMobGluZXMpCiAgICBpZiByb3V0
ZXJzX3N0YXJ0IDwgMCBvciBzZXJ2aWNlc19zdGFydCA8IDA6CiAgICAgICAgIyBObyBtb3JlIHNl
cnZpY2VzLCBwdXQge30gYmFjawogICAgICAgIGxpbmVzLmFwcGVuZCgiICByb3V0ZXJzOiB7fVxu
IikKICAgICAgICBsaW5lcy5hcHBlbmQoIiAgc2VydmljZXM6IHt9XG4iKQogICAgZWxzZToKICAg
ICAgICBzZXJ2aWNlcyA9IGZpbmRfZW50cmllcyhsaW5lcywgc2VydmljZXNfc3RhcnQpCiAgICAg
ICAgaWYgZW1wdHkoc2VydmljZXMpOgogICAgICAgICAgICBsaW5lc1tzZXJ2aWNlc19zdGFydF0g
PSAiICBzZXJ2aWNlczoge31cbiIKCiAgICB3aXRoIG9wZW4ocGF0aCwgInciKSBhcyBmOgogICAg
ICAgIGYud3JpdGVsaW5lcyhsaW5lcykKICAgIHByaW50KGYiW2Vhc3lnYXRlXSDlt7LliKDpmaTm
nI3liqHvvJp7bmFtZX0iKQoKCmlmIF9fbmFtZV9fID09ICJfX21haW5fXyI6CiAgICBpZiBsZW4o
c3lzLmFyZ3YpIDwgMzoKICAgICAgICBwcmludCgi55So5rOVOiBzZXJ2aWNlLWhlbHBlci5weSB7
YWRkfHJlbW92ZXxsaXN0fSA8cGF0aD4gPG5hbWU+IFtob3N0XSBbdXJsXSIpCiAgICAgICAgc3lz
LmV4aXQoMSkKCiAgICBjbWQgPSBzeXMuYXJndlsxXQoKICAgIGlmIGNtZCA9PSAibGlzdCI6CiAg
ICAgICAgaWYgbGVuKHN5cy5hcmd2KSA8IDI6CiAgICAgICAgICAgIHByaW50KCLnvJPlr7nml6Dm
t7vliqDmnI3liqHnmoTov57mjqXvvIxzbGlzdOWPr+iDveW3suaXoOaXoOeJiOacrOS/neaKpCIp
CiAgICAgICAgICAgIHN5cy5leGl0KDEpCiAgICAgICAgbGlzdF9zZXJ2aWNlcyhzeXMuYXJndlsy
XSkKICAgIGVsaWYgY21kID09ICJhZGQiOgogICAgICAgIGlmIGxlbihzeXMuYXJndikgPCA1Ogog
ICAgICAgICAgICBwcmludCgi55So5rOVOiBzZXJ2aWNlLWhlbHBlci5weSBhZGQgPHBhdGg+IDxu
YW1lPiA8aG9zdD4gPHVybD4iKQogICAgICAgICAgICBzeXMuZXhpdCgxKQogICAgICAgIGFkZF9z
ZXJ2aWNlKHN5cy5hcmd2WzJdLCBzeXMuYXJndlszXSwgc3lzLmFyZ3ZbNF0sIHN5cy5hcmd2WzVd
KQogICAgZWxpZiBjbWQgPT0gInJlbW92ZSI6CiAgICAgICAgaWYgbGVuKHN5cy5hcmd2KSA8IDM6
CiAgICAgICAgICAgIHByaW50KCLnlKjms5U6IHNlcnZpY2UtaGVscGVyLnB5IHJlbW92ZSA8cGF0
aD4gPG5hbWU+IikKICAgICAgICAgICAgc3lzLmV4aXQoMSkKICAgICAgICByZW1vdmVfc2Vydmlj
ZShzeXMuYXJndlsyXSwgc3lzLmFyZ3ZbM10pCiAgICBlbHNlOgogICAgICAgIHByaW50KGLmnI3n
p7DnmoTlrZfnrKbvvJp7Y21kfe+8jOWPr+iDveWPr+aYr2FkZHxyZW1vdmV8bGlzdCIpCiAgICAg
ICAgc3lzLmV4aXQoMSkK'@
  try {
    $Bytes = [System.Convert]::FromBase64String($Embedded)
    $Utf8 = [System.Text.Encoding]::UTF8
    $Utf8.GetString($Bytes) | Set-Content -Path $Target -Encoding UTF8
    Write-Info "已安装 service-helper 到 $Target"
  }
  catch {
    # fallback: 从源码目录复制
    $Src = Join-Path $PSScriptRoot "service-helper.py"
    if (Test-Path $Src) { Copy-Item $Src $Target -Force }
  }
}

function Write-ModeFile {
  param([string]$Mode)
  Set-Content -Path (Join-Path $EasyGateHome ".mode") -Value "$Mode" -Encoding UTF8 -NoNewline
}

function Detect-Mode {
  $ModeFile = Join-Path $EasyGateHome ".mode"
  if (Test-Path $ModeFile) {
    return (Get-Content $ModeFile).Trim()
  }
  # Fallback: check PID files for native, compose files for Docker
  if (Test-Path (Join-Path $EasyGateHome "run\native-traefik.pid")) {
    return "native"
  }
  if ((Test-Path $ComposeFile) -and (Test-Path $ComposeEnv)) {
    return "compose"
  }
  return ""
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
    try { cloudflared tunnel info $Tunnel | Out-Null }
    catch {
      Write-Warn "tunnel ${Tunnel} 凭据已失效，将重新创建"
      try { cloudflared tunnel delete $Tunnel 2>$null } catch {}
      Remove-Item $CredentialTarget -Force -ErrorAction SilentlyContinue
    }
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
    Write-Warn "未找到 tunnel 凭据，尝试删除并重建 tunnel"
    try { cloudflared tunnel delete $Tunnel 2>$null } catch {}
    try { cloudflared tunnel create $Tunnel } catch { Fail "创建 tunnel 失败" }
    $CredentialSource = Find-LatestCredential $CloudflaredHome
    if (-not $CredentialSource) { Fail "创建 tunnel 后仍未找到凭据文件" }
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
      Fail "检测到原生模式进程正在运行：$_。请先执行 easygate.ps1 stop 停止原生进程。"
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
  param([string[]]$FuncArgs)
  $Options = Parse-Options $FuncArgs
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
  Validate-Domain $Domain
  $Tunnel = Get-OptionValue $Options "Tunnel" "easygate-home"
  $Dashboard = Get-OptionValue $Options "Dashboard" "traefik.$Domain"
  $Port = Get-OptionValue $Options "Port" "18080"
  Validate-Port $Port "Traefik 端口"

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
  Install-ServiceHelper
  Write-Info "部署完成"
  Write-ModeFile "compose"
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
      # Graceful stop first, wait up to 4 seconds
      Stop-Process -Id $Process.Id -ErrorAction SilentlyContinue
      $Process.WaitForExit(4000) | Out-Null
      # Force kill if still running (SIGKILL equivalent)
      $Stubborn = Get-Process -Id ([int]$PidText) -ErrorAction SilentlyContinue
      if ($Stubborn) {
        Stop-Process -Id $Stubborn.Id -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
      }
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

function Start-NativeDemo {
  $EnvFile = Join-Path $EasyGateHome "native\.env"
  if (-not (Test-Path $EnvFile)) {
    Fail "未找到原生模式环境文件：$EnvFile"
  }
  $EnvLines = Get-Content $EnvFile
  $ApiPort = "19080"
  $TestApiPort = "19081"
  foreach ($Line in $EnvLines) {
    if ($Line -match "^EASYGATE_NATIVE_API_PORT=(.+)") { $ApiPort = $matches[1] }
    if ($Line -match "^EASYGATE_NATIVE_TEST_API_PORT=(.+)") { $TestApiPort = $matches[1] }
  }
  $Python = Find-Python
  if (-not $Python) {
    Fail "原生 demo 需要 python3 或 python"
  }
  Write-NativeDemoServer
  $DemoScript = Join-Path $EasyGateHome "lib\native-demo-server.py"
  Start-NativeProcess "native-demo-api" $Python @($DemoScript, "--port", $ApiPort)
  Start-NativeProcess "native-demo-test-api" $Python @($DemoScript, "--port", $TestApiPort)
  Write-Info "原生 demo 服务已启动"
}

function Stop-NativeDemo {
  Stop-PidFile (Join-Path $EasyGateHome "run\native-demo-api.pid")
  Stop-PidFile (Join-Path $EasyGateHome "run\native-demo-test-api.pid")
  Write-Info "原生 demo 服务已停止"
}

# ── Windows 计划任务注册（重启持久化） ────────────────────────────────
# 等价于 Linux: register_systemd() / macOS: register_launchd()

function Register-NativeScheduledTask {
  $TaskName = "EasyGate"
  $ScriptPath = Join-Path $EasyGateHome "bin\easygate.ps1"

  if (-not (Test-Path $ScriptPath)) {
    Write-Warn "未找到 easygate.ps1：$ScriptPath，跳过计划任务注册"
    return
  }

  # 先尝试删除已有任务（忽略错误）
  schtasks /delete /tn "$TaskName" /f 2>$null

  $Command = "powershell -ExecutionPolicy Bypass -File `"$ScriptPath`" start"
  Write-Info "注册计划任务（用户登录时自动启动原生服务）：$TaskName"

  # /sc onlogon — 用户登录时触发（无需管理员）
  # /rl limited  — 以当前用户权限运行
  # /delay 0000:30 — 延迟 30 秒，等系统就绪
  # /f — 覆盖已有任务
  schtasks /create /tn "$TaskName" /tr "$Command" /sc onlogon /rl limited /delay 0000:30 /f 2>$null

  if ($LASTEXITCODE -eq 0) {
    Write-Info "计划任务已注册：$TaskName（用户登录后自动启动）"
  }
  else {
    Write-Warn "计划任务注册失败（可能需要管理员权限）"
    Write-Warn "可手动注册：schtasks /create /tn EasyGate /tr `"$Command`" /sc onlogon /rl limited /delay 0000:30 /f"
  }
}

function Unregister-NativeScheduledTask {
  $TaskName = "EasyGate"
  schtasks /delete /tn "$TaskName" /f 2>$null
  if ($LASTEXITCODE -eq 0) {
    Write-Info "计划任务已删除：$TaskName"
  }
}

function Deploy-Native {
  param([string[]]$FuncArgs)
  $Options = Parse-Options $FuncArgs
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
  Validate-Domain $Domain
  $Tunnel = Get-OptionValue $Options "Tunnel" "easygate-home"
  $Dashboard = Get-OptionValue $Options "Dashboard" "traefik.$Domain"
  $Port = Get-OptionValue $Options "Port" "18080"
  $ApiPort = Get-OptionValue $Options "ApiPort" "19080"
  $TestApiPort = Get-OptionValue $Options "TestApiPort" "19081"
  Validate-Port $Port "Traefik 端口"
  Validate-Port $ApiPort "Demo API 端口"
  Validate-Port $TestApiPort "Demo Test API 端口"
  Test-PortAvailable $Port "Traefik 端口"

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
      "ha-connections: 2"
      "loglevel: warn"
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

  Install-ServiceHelper

  Start-NativeProcess "native-traefik" "traefik" @("--configFile", (Join-Path $EasyGateHome "native\traefik.yml"))
  Test-ProcessStarted "native-traefik"
  if (-not $LocalOnly) {
    Start-NativeProcess "native-cloudflared" "cloudflared" @("tunnel", "--config", (Join-Path $EasyGateHome "cloudflared\config.native.yml"), "run")
    Test-ProcessStarted "native-cloudflared"
  }

  Rotate-Logs

  # 注册计划任务，系统重启后用户登录时自动启动
  Register-NativeScheduledTask

  Write-Info "原生部署完成"
  Write-ModeFile "native"
  Write-Host ""
  Write-Host "后续检查："
  Write-Host "  easygate.ps1 logs"
  Write-Host "  easygate.ps1 uninstall"
  Write-Host "  运行时目录：$EasyGateHome"
  Write-Host "  本地调试入口：http://127.0.0.1:$Port"
  Write-Host "  https://api.$Domain"
  Write-Host "  https://test-api.$Domain"
}

function Start-Services {
  $Mode = Detect-Mode
  switch ($Mode) {
    "compose" { Invoke-EasyGateCompose start; Write-Info "服务已启动" }
    "native" { Start-NativeServices }
    default { Fail "未找到已部署的服务，请先执行 easygate.ps1 deploy" }
  }
}

function Stop-Services {
  $Mode = Detect-Mode
  switch ($Mode) {
    "compose" { Invoke-EasyGateCompose stop; Write-Info "服务已停止，配置和凭据已保留" }
    "native" { Stop-NativeServices }
    default { Fail "未找到已部署的服务，请先执行 easygate.ps1 deploy" }
  }
}

function Restart-Services {
  $Mode = Detect-Mode
  switch ($Mode) {
    "compose" { Invoke-EasyGateCompose restart; Write-Info "服务已重启" }
    "native" { Stop-NativeServices; Start-NativeServices; Write-Info "服务已重启" }
    default { Fail "未找到已部署的服务，请先执行 easygate.ps1 deploy" }
  }
}

function Start-NativeServices {
  $EnvFile = Join-Path $EasyGateHome "native\.env"
  if (-not (Test-Path $EnvFile)) {
    Fail "未找到原生模式环境文件：$EnvFile"
  }
  # 读取环境文件
  $EnvLines = Get-Content $EnvFile
  $TraefikPort = "18080"
  foreach ($Line in $EnvLines) {
    if ($Line -match "^TRAEFIK_HTTP_PORT=(.+)") { $TraefikPort = $matches[1] }
    if ($Line -match "^EASYGATE_DEPLOY_MODE=(.+)") { $DeployMode = $matches[1] }
  }
  # 端口检查
  Test-PortAvailable $TraefikPort "Traefik 端口"
  if (-not (Get-Command traefik -ErrorAction SilentlyContinue)) {
    Fail "缺少命令：traefik"
  }
  Start-NativeProcess "native-traefik" "traefik" @("--configFile", (Join-Path $EasyGateHome "native\traefik.yml"))
  Test-ProcessStarted "native-traefik"
  if ($DeployMode -ne "local-only") {
    if (-not (Get-Command cloudflared -ErrorAction SilentlyContinue)) {
      Fail "缺少命令：cloudflared"
    }
    Start-NativeProcess "native-cloudflared" "cloudflared" @("tunnel", "--config", (Join-Path $EasyGateHome "cloudflared\config.native.yml"), "run")
    Test-ProcessStarted "native-cloudflared"
  }
}

function Stop-NativeServices {
  Stop-PidFile (Join-Path $EasyGateHome "run\native-cloudflared.pid")
  Stop-PidFile (Join-Path $EasyGateHome "run\native-traefik.pid")
  Stop-PidFile (Join-Path $EasyGateHome "run\native-demo-api.pid")
  Stop-PidFile (Join-Path $EasyGateHome "run\native-demo-test-api.pid")
}

# ── Service management (add/remove/list) ─────────────────────────────

function Get-ServiceYamlPath {
  $Mode = Detect-Mode
  switch ($Mode) {
    "compose" { return Join-Path $EasyGateHome "traefik\dynamic\localhost-services.yml" }
    "native" { return Join-Path $EasyGateHome "native\dynamic\services.yml" }
    default { return Join-Path $EasyGateHome "native\dynamic\services.yml" }
  }
}

function Get-ServiceHelper {
  $Helper = Join-Path $EasyGateHome "lib\service-helper.py"
  if (Test-Path $Helper) { return $Helper }
  $SourceHelper = Join-Path $PSScriptRoot "service-helper.py"
  if (Test-Path $SourceHelper) { return (Resolve-Path $SourceHelper).Path }
  return $null
}

function Invoke-ServiceHelper {
  param([string[]]$FuncArgs)
  $Helper = Get-ServiceHelper
  if (-not $Helper) { Fail "service-helper.py 不可用" }
  $Python = Get-Command "python3" -ErrorAction SilentlyContinue
  if (-not $Python) { $Python = Get-Command "python" -ErrorAction SilentlyContinue }
  if (-not $Python) { Fail "需要 python3 或 python" }
  & $Python.Source $Helper @Args
}

function Start-ServiceAdd {
  param([string[]]$FuncArgs)
  $Name = $Host = $Url = $null
  for ($i = 0; $i -lt $FuncArgs.Count; $i++) {
    switch -Regex ($FuncArgs[$i]) {
      '^--?name$|^-Name$' { $i++; $Name = $Args[$i] }
      '^--?host$|^-Host$' { $i++; $Host = $Args[$i] }
      '^--?url$|^-Url$' { $i++; $Url = $Args[$i] }
      default { Fail "未知参数：$($Args[$i])" }
    }
  }
  if (-not $Name) { Fail "缺少 -Name（服务名称）" }
  if (-not $Host) { Fail "缺少 -Host（访问域名，如 app.example.com）" }
  if (-not $Url) { Fail "缺少 -Url（上游地址，如 http://192.168.1.100:8080）" }

  $YamlFile = Get-ServiceYamlPath
  New-Item -ItemType Directory -Force -Path (Split-Path $YamlFile) | Out-Null
  Invoke-ServiceHelper add $YamlFile $Name $Host $Url
}

function Start-ServiceRemove {
  param([string[]]$FuncArgs)
  $Name = if ($FuncArgs.Count -gt 0) { $FuncArgs[0] } else { $null }
  if (-not $Name) { Fail "用法：easygate.ps1 service remove <name>" }

  $YamlFile = Get-ServiceYamlPath
  if (-not (Test-Path $YamlFile)) { Fail "服务配置文件不存在：$YamlFile" }
  Invoke-ServiceHelper remove $YamlFile $Name
}

function Start-ServiceList {
  $YamlFile = Get-ServiceYamlPath
  if (-not (Test-Path $YamlFile)) {
    Write-Info "暂无已配置的服务"
    return
  }
  Invoke-ServiceHelper list $YamlFile
}

function Invoke-Uninstall {
  # 删除计划任务（阻止重启后自动启动）
  Unregister-NativeScheduledTask
  # Stop native services (traefik + cloudflared)
  Stop-NativeServices
  # Stop demo services
  Stop-NativeDemo
  # Kill any leftover demo Python processes
  Get-Process -Name "python3","python" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match "native-demo-server" } |
    Stop-Process -Force -ErrorAction SilentlyContinue
  # Stop compose containers
  if ((Test-Path $ComposeFile) -and (Test-Path $ComposeEnv) -and (Get-Command docker -ErrorAction SilentlyContinue)) {
    try { Invoke-EasyGateCompose --profile demo down --remove-orphans } catch { }
  }
  # 从用户环境变量 PATH 中移除 EasyGate 目录
  $InstallDir = Join-Path $EasyGateHome "bin"
  $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
  if ($UserPath -like "*$InstallDir*") {
    $NewPath = ($UserPath -split ';' | Where-Object { $_ -ne $InstallDir }) -join ';'
    [Environment]::SetEnvironmentVariable("Path", $NewPath, "User")
    Write-Info "已从用户环境变量 PATH 中移除 $InstallDir"
  }
  # Delete all local data
  # On Windows, processes may still hold file handles briefly after Stop-Process.
  # Retry a few times to avoid "Access denied" on locked executables.
  if (Test-Path $EasyGateHome) {
    $Removed = $false
    for ($Retry = 0; $Retry -lt 5; $Retry++) {
      try {
        Remove-Item -Recurse -Force $EasyGateHome -ErrorAction Stop
        Write-Info "已删除运行时目录 ${EasyGateHome}"
        $Removed = $true
        break
      } catch {
        Start-Sleep -Milliseconds 500
      }
    }
    if (-not $Removed) {
      Write-Warn "无法完全删除运行时目录（文件可能被占用）：${EasyGateHome}"
    }
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
  "deploy" {
    $NativeMode = $false
    $DeployArgs = @()
    for ($Index = 0; $Index -lt $Rest.Count; $Index++) {
      if ($Rest[$Index] -eq "-Native" -or $Rest[$Index] -eq "--native") { $NativeMode = $true }
      else { $DeployArgs += $Rest[$Index] }
    }
    if ($NativeMode) { Deploy-Native $DeployArgs }
    else { Deploy-Compose $DeployArgs }
  }
  "start" { Start-Services }
  "stop" { Stop-Services }
  "restart" { Restart-Services }
  "ps" {
    $Mode = Detect-Mode
    switch ($Mode) {
      "compose" { Invoke-EasyGateCompose ps }
      "native" {
        Write-Info "原生模式进程状态："
        @("native-traefik", "native-cloudflared", "native-demo-api", "native-demo-test-api") | ForEach-Object {
          $PidFile = Join-Path $EasyGateHome "run\$_.pid"
          $Name = $_ -replace "^native-", ""
          if (Test-NativeProcessActive $PidFile) {
            Write-Host "  $($Name.PadRight(15)) running  (pid $(Get-Content $PidFile))"
          } else {
            Write-Host "  $($Name.PadRight(15)) stopped"
          }
        }
        # 显示计划任务状态
        $TaskInfo = schtasks /query /tn "EasyGate" /fo LIST /v 2>$null
        if ($LASTEXITCODE -eq 0) {
          $TaskStatus = if ($TaskInfo -match "状态:\s+(\S+)") { $matches[1] } else { "?" }
          Write-Host "  $("计划任务".PadRight(15)) $TaskStatus  (用户登录时自动启动)"
        }
      }
      default { Fail "未找到已部署的服务，请先执行 easygate.ps1 deploy" }
    }
  }
  "logs" {
    # 查看前先检查是否需要轮转
    Rotate-Logs
    $Mode = Detect-Mode
    switch ($Mode) {
      "compose" { Invoke-EasyGateCompose logs -f traefik cloudflared }
      "native" {
        Get-ChildItem (Join-Path $EasyGateHome "logs") -Filter "native-*.log" -ErrorAction SilentlyContinue | ForEach-Object {
          Write-Host "==> $($_.FullName)"
          Get-Content $_.FullName -Tail 80
        }
      }
      default { Fail "未找到已部署的服务，请先执行 easygate.ps1 deploy" }
    }
  }
  "config" {
    $Mode = Detect-Mode
    switch ($Mode) {
      "compose" { Invoke-EasyGateCompose config }
      "native" {
        Write-Host "=== Traefik 配置 ==="
        if (Test-Path (Join-Path $EasyGateHome "native\traefik.yml")) {
          Get-Content (Join-Path $EasyGateHome "native\traefik.yml")
        } else { Write-Info "未找到 Traefik 配置" }
        $CfConfig = Join-Path $EasyGateHome "cloudflared\config.native.yml"
        if (Test-Path $CfConfig) {
          Write-Host ""
          Write-Host "=== Cloudflared 配置 ==="
          Get-Content $CfConfig
        }
      }
      default { Fail "未找到已部署的服务，请先执行 easygate.ps1 deploy" }
    }
  }
  "demo" {
    $Mode = Detect-Mode
    $DemoSub = if ($Rest.Count -gt 0) { $Rest[0] } else { "start" }
    switch ($Mode) {
      "compose" {
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
          default { Fail "未知 demo 子命令：${DemoSub}。可用：start|stop|restart" }
        }
      }
      "native" {
        switch ($DemoSub) {
          "start" { Start-NativeDemo }
          "restart" { Stop-NativeDemo; Start-NativeDemo }
          "stop" { Stop-NativeDemo }
          default { Fail "未知 demo 子命令：${DemoSub}。可用：start|stop|restart" }
        }
      }
      default { Fail "未找到已部署的服务，请先执行 easygate.ps1 deploy" }
    }
  }
  "service" {
    $ServiceSub = if ($Rest.Count -gt 0) { $Rest[0] } else { "" }
    $ServiceRest = if ($Rest.Count -gt 1) { $Rest[1..($Rest.Count - 1)] } else { @() }
    switch ($ServiceSub) {
      "add" { Start-ServiceAdd $ServiceRest }
      "remove" { Start-ServiceRemove $ServiceRest }
      "list" { Start-ServiceList }
      default { Fail "未知 service 子命令：${ServiceSub}。可用：add|remove|list" }
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
