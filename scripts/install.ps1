$CommandArgs = @($args)

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

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

if (-not [string]::IsNullOrWhiteSpace($env:EASYGATE_LOCAL_CLI)) {
  $SourcePath = $env:EASYGATE_LOCAL_CLI
  Write-Host "[install] 从本地复制 CLI：$SourcePath"
  if (-not (Test-Path $SourcePath -PathType Leaf)) {
    Write-Error "[install] 找不到本地 CLI：$SourcePath"
    Write-Host "[install] 当前工作目录：$(Get-Location)"
    Write-Host "[install] github.workspace：$env:GITHUB_WORKSPACE"
    exit 1
  }
  try {
    Copy-Item $SourcePath $Target -Force -ErrorAction Stop
  }
  catch {
    Write-Error "[install] 复制 CLI 失败：$_"
    exit 1
  }
}
else {
  Write-Host "[install] 从远程下载 CLI：$SourceUrl"
  try {
    Invoke-WebRequest -UseBasicParsing -Uri $SourceUrl -OutFile $Target -ErrorAction Stop
  }
  catch {
    Write-Error "[install] 下载 CLI 失败：$_"
    exit 1
  }
}

# ── PATH 自动配置 ──────────────────────────────────────────────────────

# 当前会话立即生效
$env:Path = "$InstallDir;$env:Path"
Write-Host "[install] 已将 $InstallDir 添加到当前会话 PATH"

# 写入用户环境变量（永久生效），仅在安装到默认路径时执行
$DefaultHome = Join-Path $env:LOCALAPPDATA "EasyGate"
if ($EasyGateHome -eq $DefaultHome) {
  $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
  if ($UserPath -notlike "*$InstallDir*") {
    $NewPath = "$InstallDir;$UserPath"
    [Environment]::SetEnvironmentVariable("Path", $NewPath, "User")
    Write-Host "[install] 已写入用户环境变量 PATH，新终端窗口自动生效"
  }
  else {
    Write-Host "[install] $InstallDir 已在用户环境变量 PATH 中"
  }
}

Write-Host ""
Write-Host "[install] ✅ 安装完成"
Write-Host "   CLI 路径：$Target"
Write-Host "   运行时目录：$EasyGateHome"
Write-Host ""

if ($CommandArgs.Count -gt 0 -and $CommandArgs[0] -ne '') {
  & $Target @CommandArgs
  if ($null -eq $LASTEXITCODE) {
    exit 0
  }
  exit $LASTEXITCODE
}

Write-Host "   直接部署："
Write-Host "   easygate.ps1 deploy -Domain example.com"
Write-Host "   easygate.ps1 deploy -Native -Domain example.com（原生模式，无需 Docker）"
