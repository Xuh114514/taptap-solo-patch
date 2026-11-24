# 安装 TapTap / 渠道版「本地单机启动」补丁
# 用法：右键本文件 -> 使用 PowerShell 运行；或 powershell -ExecutionPolicy Bypass -File install.ps1

param([string]$LauncherRoot = '')

$ErrorActionPreference = 'Continue'
$HookDir   = $PSScriptRoot
$StubExe   = Join-Path $HookDir 'tools\PCSDKUIStub.exe'
$HostsFile = Join-Path $env:WINDIR 'System32\drivers\etc\hosts'
$HostsBak  = Join-Path $HookDir 'hosts.backup'
$RegPath   = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
$ProxyOverrideBak = Join-Path $HookDir 'proxy-override.backup'
$DispatchHost = 'dsp-prod-of.inutan.com'

function Say($text)  { Write-Host "  $text" -ForegroundColor Gray }
function Ok($text)   { Write-Host "[OK]   $text" -ForegroundColor Green }
function Warn($text) { Write-Host "[注意] $text" -ForegroundColor Yellow }
function Step($text) { Write-Host "`n=== $text ===" -ForegroundColor Cyan }

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-Launcher([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return $false }
    return (Test-Path (Join-Path $path 'OverFieldLauncher.exe'))
}

# ---------- 1. 找启动器目录 ----------
Step '第 1 步：定位启动器'

$candidates = @()
if ($LauncherRoot) { $candidates += $LauncherRoot }
$candidates += $HookDir
$candidates += (Split-Path $HookDir -Parent)

$found = $null
foreach ($c in $candidates) {
    if (Test-Launcher $c) { $found = (Resolve-Path $c).Path; break }
}

if (-not $found) {
    Warn '没有自动找到 OverFieldLauncher.exe。'
    Say '把「启动器所在的文件夹」拖到这个窗口里，然后回车（例如 D:\Games\OverFieldLauncher）：'
    $input = Read-Host '  目录'
    $input = $input.Trim('"').Trim("'").Trim()
    if (Test-Launcher $input) { $found = (Resolve-Path $input).Path }
}

if (-not $found) {
    Warn '还是没找到。请确认目录里能看到 OverFieldLauncher.exe。'
    Read-Host '按回车退出'
    exit 1
}

Ok "启动器目录：$found"
$LauncherRoot = $found
$ClientDir = Join-Path $LauncherRoot 'profiles\solo\client'
$SdkDir    = Join-Path $ClientDir 'launcher_Data\Plugins\Win\PCSDK_release'
$StubDst   = Join-Path $SdkDir 'PCSDKUI.exe'
$StubBak   = Join-Path $SdkDir 'PCSDKUI.orig.exe'

# ---------- 2. 检查客户端副本 ----------
Step '第 2 步：检查客户端副本'

if (-not (Test-Path $SdkDir)) {
    Warn '还没生成客户端副本。'
    Say '请先这样做一次（失败没关系）：'
    Say '  1) 打开 OverFieldLauncher.exe'
    Say '  2) 选「单机模式」，填一个 UID'
    Say '  3) 点「更改目录」选中游戏客户端目录'
    Say '  4) 点「启动单机游戏」，等它跑完，然后关掉游戏'
    Say '做完后再运行本脚本。'
    Read-Host '按回车退出'
    exit 1
}
Ok "客户端副本：$SdkDir"

if (-not (Test-Path $StubExe)) {
    Warn "缺少 tools\PCSDKUIStub.exe，请确认解压完整。"
    Read-Host '按回车退出'
    exit 1
}

# ---------- 3. 替换 PCSDKUI.exe ----------
Step '第 3 步：装替身 PCSDKUI'

if (-not (Test-Path $StubBak)) {
    if (Test-Path $StubDst) {
        Copy-Item -LiteralPath $StubDst -Destination $StubBak -Force
        Ok '原版已备份为 PCSDKUI.orig.exe'
    }
}
$srcLen = (Get-Item $StubExe).Length
$dstLen = if (Test-Path $StubDst) { (Get-Item $StubDst).Length } else { -1 }
if ($srcLen -ne $dstLen) {
    Copy-Item -LiteralPath $StubExe -Destination $StubDst -Force
    Ok '已替换为替身程序'
} else {
    Ok '替身程序已是当前版本'
}

# ---------- 4. hosts + 端口转发（需要管理员） ----------
Step '第 4 步：hosts 与端口转发'

$admin = Test-Admin
if (-not $admin) {
    Warn '这一步需要管理员权限，正在申请提权…（UAC 点「是」）'
    $args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"",'-LauncherRoot',"`"$LauncherRoot`"")
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait -ArgumentList $args
    exit
}

$hostsText = Get-Content -LiteralPath $HostsFile -ErrorAction SilentlyContinue
$hasHosts = [bool]($hostsText -match [regex]::Escape($DispatchHost))
if (-not $hasHosts) {
    if (-not (Test-Path $HostsBak)) { Copy-Item -LiteralPath $HostsFile -Destination $HostsBak -Force }
    Add-Content -LiteralPath $HostsFile -Value "`r`n# taptap-solo-patch (remove this line to restore)"
    Add-Content -LiteralPath $HostsFile -Value "127.0.0.1 $DispatchHost"
    Ok "hosts 已加入 127.0.0.1 $DispatchHost"
} else {
    Ok 'hosts 已经有对应记录'
}

& netsh interface portproxy delete v4tov4 listenaddress=127.0.0.1 listenport=18881 2>$null | Out-Null
& netsh interface portproxy add v4tov4 listenaddress=127.0.0.1 listenport=18881 connectaddress=127.0.0.1 connectport=18080
if ($LASTEXITCODE -eq 0) { Ok '端口转发 127.0.0.1:18881 -> 127.0.0.1:18080' }
else { Warn '端口转发设置失败，请确认是以管理员身份运行' }

& ipconfig /flushdns | Out-Null

# ---------- 5. 代理旁路（只有真的装了系统代理才需要） ----------
Step '第 5 步：代理旁路'

$proxyState = Get-ItemProperty -Path $RegPath -ErrorAction SilentlyContinue
$proxyOn = ($proxyState.ProxyEnable -eq 1) -and ($proxyState.ProxyServer -or $proxyState.AutoConfigURL)

if (-not $proxyOn) {
    Ok '没有检测到系统代理（ProxyEnable 不是 1），这一步自动跳过'
    Say '直连网络不会劫持 dispatch 请求，不需要这项设置。'
} else {
    $current = $proxyState.ProxyOverride
    if ($current) {
        if (-not (Test-Path $ProxyOverrideBak)) {
            [IO.File]::WriteAllText($ProxyOverrideBak, $current, (New-Object Text.UTF8Encoding($false)))
        }
        $parts = $current -split ';' | Where-Object { $_ -ne '' -and $_ -ne '<local>' }
        foreach ($item in @('*.inutan.com','14.103.*')) {
            if ($parts -notcontains $item) { $parts += $item }
        }
        $newValue = ($parts -join ';') + ';<local>'
        if ($newValue -ne $current) {
            Set-ItemProperty -Path $RegPath -Name ProxyOverride -Value $newValue -Type String
            Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class TspWinInet { [DllImport("wininet.dll")] public static extern bool InternetSetOption(IntPtr h,int o,IntPtr b,int n); }' -ErrorAction SilentlyContinue
            [TspWinInet]::InternetSetOption([IntPtr]::Zero,39,[IntPtr]::Zero,0) | Out-Null
            [TspWinInet]::InternetSetOption([IntPtr]::Zero,37,[IntPtr]::Zero,0) | Out-Null
            Ok "检测到系统代理（$($proxyState.ProxyServer)），已把 dispatch 域名加入「不使用代理」列表"
            if ($proxyState.ProxyServer -match '^[^:]+:(\d+)$') {
                $pp = [int]$Matches[1]
                if (-not (Get-NetTCPConnection -LocalPort $pp -State Listen -ErrorAction SilentlyContinue)) {
                    Warn "不过 $($proxyState.ProxyServer) 现在没有在监听（代理软件没开？）。dispatch 已经走旁路，不受影响；但你最好把代理软件关掉或打开，否则其它网页会打不开。"
                }
            }
        } else {
            Ok '代理旁路已存在'
        }
    } else {
        Warn '有代理但没有 ProxyOverride 列表，跳过（一般不影响）'
    }
}

# ---------- 完成 ----------
Step '完成'
Say '接下来：'
Say '  1) 打开 OverFieldLauncher.exe'
Say '  2) 选「单机模式」，填 UID'
Say '  3) 点「启动单机游戏」'
Say '  4) 出现渠道登录弹窗时直接关掉'
Say ''
Say "验证：看 $LauncherRoot\profiles\solo\logs\ 最新 server-*.log"
Say '      出现「VerifyLoginToken ... verify success」和「PlayerLogin ... 登录成功」就是成功'
Say ''
Warn '要回官服，运行 uninstall.ps1'
Read-Host '按回车关闭'
