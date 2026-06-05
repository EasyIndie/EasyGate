param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$CommandArgs,
  [string]$Domain,
  [string]$Tunnel,
  [string]$Dashboard,
  [string]$Port,
  [string]$ApiPort,
  [string]$TestApiPort,
  [switch]$SkipRoute,
  [switch]$Demo,
  [switch]$LocalOnly,
  [switch]$NoInstallCloudflared,
  [switch]$NoInstallTraefik,
  [switch]$Purge
)

$ErrorActionPreference = "Stop"

$Repo = if ([string]::IsNullOrWhiteSpace($env:EASYGATE_REPO)) { "EasyIndie/EasyGate" } else { $env:EASYGATE_REPO }
$Ref = if ([string]::IsNullOrWhiteSpace($env:EASYGATE_REF)) { "main" } else { $env:EASYGATE_REF }
$SourceUrl = if ([string]::IsNullOrWhiteSpace($env:EASYGATE_CLI_URL)) {
  "https://raw.githubusercontent.com/$Repo/$Ref/scripts/easygate.ps1"
}
else {
  $env:EASYGATE_CLI_URL
}

function Get-EasyGateHome {
  if (-not [string]::IsNullOrWhiteSpace($env:EASYGATE_HOME)) {
    return $env:EASYGATE_HOME
  }
  return Join-Path $env:LOCALAPPDATA "EasyGate"
}

$EasyGateHome = Get-EasyGateHome
$InstallDir = Join-Path $EasyGateHome "bin"
$Target = Join-Path $InstallDir "easygate.ps1"

$ForwardedOptions = @()
if ($PSBoundParameters.ContainsKey("Domain")) { $ForwardedOptions += @("-Domain", $Domain) }
if ($PSBoundParameters.ContainsKey("Tunnel")) { $ForwardedOptions += @("-Tunnel", $Tunnel) }
if ($PSBoundParameters.ContainsKey("Dashboard")) { $ForwardedOptions += @("-Dashboard", $Dashboard) }
if ($PSBoundParameters.ContainsKey("Port")) { $ForwardedOptions += @("-Port", $Port) }
if ($PSBoundParameters.ContainsKey("ApiPort")) { $ForwardedOptions += @("-ApiPort", $ApiPort) }
if ($PSBoundParameters.ContainsKey("TestApiPort")) { $ForwardedOptions += @("-TestApiPort", $TestApiPort) }
if ($SkipRoute) { $ForwardedOptions += "-SkipRoute" }
if ($Demo) { $ForwardedOptions += "-Demo" }
if ($LocalOnly) { $ForwardedOptions += "-LocalOnly" }
if ($NoInstallCloudflared) { $ForwardedOptions += "-NoInstallCloudflared" }
if ($NoInstallTraefik) { $ForwardedOptions += "-NoInstallTraefik" }
if ($Purge) { $ForwardedOptions += "-Purge" }
$CommandArgs = @($CommandArgs) + $ForwardedOptions

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

if (-not [string]::IsNullOrWhiteSpace($env:EASYGATE_LOCAL_CLI)) {
  Copy-Item $env:EASYGATE_LOCAL_CLI $Target -Force
}
else {
  Invoke-WebRequest -UseBasicParsing -Uri $SourceUrl -OutFile $Target
}

Write-Host "[install] easygate.ps1 已安装到：$Target"
Write-Host "[install] 运行时目录：$EasyGateHome"
Write-Host "[install] 可选：将 $InstallDir 加入 PATH"

if ($CommandArgs.Count -gt 0) {
  & $Target @CommandArgs
  if ($null -eq $LASTEXITCODE) {
    exit 0
  }
  exit $LASTEXITCODE
}

Write-Host "[install] 部署示例：powershell -ExecutionPolicy Bypass -File `"$Target`" deploy -Domain example.com"
