# 把 PC 上的 Lolo 服务端暴露给同一局域网的安卓设备（安卓单机 / 联机的服务端侧）
# 用法：右键「使用 PowerShell 运行」，或 powershell -ExecutionPolicy Bypass -File lan-server.ps1 -Action on

param(
    [ValidateSet('on','off','status')][string]$Action = 'on'
)

$ErrorActionPreference = 'Continue'
$Root      = 'C:\kfkj\OverFieldLauncher-portable'
if (-not (Test-Path $Root)) {
    $Root = Split-Path $PSScriptRoot -Parent
}
$Profile   = Join-Path $Root 'profiles\solo'
$Config    = Join-Path $Profile 'config.json'
$ConfigBak = Join-Path $PSScriptRoot 'config.solo.backup.json'
$Lolo      = Join-Path $Profile 'server\Lolo.exe'
$Python    = Join-Path $Root 'runtime-python\python.exe'

function Ok($t)   { Write-Host "[OK]   $t" -ForegroundColor Green }
function Warn($t) { Write-Host "[注意] $t" -ForegroundColor Yellow }
function Step($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Get-LanIp {
    $cands = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' -and $_.PrefixOrigin -ne 'WellKnown' }
    if ($cands) { return ($cands | Sort-Object -Property InterfaceMetric | Select-Object -First 1).IPAddress }
    return '127.0.0.1'
}

if ($Action -eq 'status') {
    Step '当前状态'
    $c = Get-Content -LiteralPath $Config -Raw -Encoding UTF8 | ConvertFrom-Json
    Write-Output ("HttpNet:  " + $c.HttpNet.InnerIp + ":" + $c.HttpNet.InnerPort)
    Write-Output ("GateWay: " + $c.GateWay.OuterIp + ":" + $c.GateWay.OuterPort)
    Write-Output ("LogServer: " + $c.LogServer.OuterIp + ":" + $c.LogServer.OuterPort)
    Write-Output ("本机局域网 IP: " + (Get-LanIp))
    $rule = Get-NetFirewallRule -Name 'OverField-LAN-*' -ErrorAction SilentlyContinue
    Write-Output ("防火墙规则: " + $(if ($rule) { '已存在' } else { '未创建' }))
    Read-Host '按回车关闭'
    exit
}

if (-not (Test-Admin)) {
    Warn '需要管理员权限（改配置、开防火墙），正在申请提权…（UAC 点「是」）'
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"",'-Action',$Action)
    exit
}

$lanIp = Get-LanIp

if ($Action -eq 'off') {
    Step '还原为仅本机可用'
    if (Test-Path $ConfigBak) {
        Copy-Item -LiteralPath $ConfigBak -Destination $Config -Force
        Ok "配置已还原"
    } else {
        Warn '没有找到备份，跳过'
    }
    Get-NetFirewallRule -Name 'OverField-LAN-*' -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
    Ok '防火墙规则已删除'
    Read-Host '按回车关闭'
    exit
}

Step '准备配置'
if (-not (Test-Path $ConfigBak)) {
    Copy-Item -LiteralPath $Config -Destination $ConfigBak -Force
    Ok "原配置已备份 -> $ConfigBak"
}

$json = Get-Content -LiteralPath $Config -Raw -Encoding UTF8 | ConvertFrom-Json
$json.HttpNet.InnerIp   = '0.0.0.0'
$json.HttpNet.InnerPort = '18881'
$json.GateWay.OuterIp   = $lanIp
$json.GateWay.OuterPort = 18100
$json.LogServer.OuterIp = $lanIp
$json.LogServer.OuterPort = 18200
$json | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Config -Encoding UTF8
Ok "监听 0.0.0.0:18881，网关返回 $lanIp:18100"

Step '放行防火墙'
foreach ($p in @(18881, 18100, 18200)) {
    $name = "OverField-LAN-$p"
    Get-NetFirewallRule -Name $name -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
    New-NetFirewallRule -Name $name -DisplayName "OverField LAN $p" -Direction Inbound -Action Allow `
        -Protocol TCP -LocalPort $p -Profile Private,Domain -ErrorAction SilentlyContinue | Out-Null
}
Ok 'TCP 18881 / 18100 / 18200 已放行（仅专用/域网络）'

Step '启动服务端'
Get-Process -Name 'Lolo' -ErrorAction SilentlyContinue | ForEach-Object {
    Stop-Process -Id $_.Id -Force
    Warn "已停止旧的 Lolo.exe (PID $($_.Id))"
}
Start-Sleep -Seconds 1
$logDir = Join-Path $Profile 'logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
Start-Process -FilePath $Lolo -ArgumentList '-c', "`"$Config`"" -WorkingDirectory $Profile `
    -RedirectStandardOutput (Join-Path $logDir "lan-$stamp.log") `
    -RedirectStandardError (Join-Path $logDir "lan-$stamp.err.log") -WindowStyle Hidden
Start-Sleep -Seconds 6
$up = Get-NetTCPConnection -LocalPort 18881 -State Listen -ErrorAction SilentlyContinue
if ($up) { Ok '服务端已在 18881 监听' } else { Warn '18881 还没监听，请看 profiles\solo\logs\lan-*.log' }

Write-Host ''
Write-Host '============================================' -ForegroundColor Cyan
Write-Host '  安卓设备要用的信息' -ForegroundColor Cyan
Write-Host '============================================' -ForegroundColor Cyan
Write-Host ("  服务端 IP   :  " + $lanIp) -ForegroundColor Yellow
Write-Host  "  服务端端口  :  18881（dispatch/HTTP）" -ForegroundColor Yellow
Write-Host  "  网关端口    :  18100（gate）" -ForegroundColor Yellow
Write-Host ''
Write-Host '  安卓设备上把 dsp-prod-of.inutan.com 解析到上面这个 IP' -ForegroundColor Gray
Write-Host '  （改 hosts / 用 VPN 类 hosts 工具 / 用 LSPosed 模块 hook）' -ForegroundColor Gray
Write-Host ''
Read-Host '按回车关闭'
