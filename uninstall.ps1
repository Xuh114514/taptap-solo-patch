# 完整还原：恢复 hosts、删除端口转发、还原 PCSDKUI.exe、清理代理旁路
# 用法：右键本文件 -> 使用 PowerShell 运行；或 powershell -ExecutionPolicy Bypass -File uninstall.ps1

param([string]$LauncherRoot = '')

$ErrorActionPreference = 'Continue'
$HookDir   = $PSScriptRoot
$HostsFile = Join-Path $env:WINDIR 'System32\drivers\etc\hosts'
$HostsBak  = Join-Path $HookDir 'hosts.backup'
$RegPath   = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'

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

Step '定位启动器'

$candidates = @()
if ($LauncherRoot) { $candidates += $LauncherRoot }
$candidates += $HookDir
$candidates += (Split-Path $HookDir -Parent)

$found = $null
foreach ($c in $candidates) {
    if (Test-Launcher $c) { $found = (Resolve-Path $c).Path; break }
}
if (-not $found) {
    Warn '没有自动找到启动器目录，请把启动器文件夹拖进来后回车：'
    $input = Read-Host '  目录'
    $input = $input.Trim('"').Trim("'").Trim()
    if (Test-Launcher $input) { $found = (Resolve-Path $input).Path }
}
if (-not $found) {
    Warn '未找到启动器，仍会尝试清理 hosts 与端口转发。'
} else {
    Ok "启动器目录：$found"
    $LauncherRoot = $found
}

Step '还原系统设置（需要管理员）'

if (-not (Test-Admin)) {
    Warn '正在申请提权…（UAC 点「是」）'
    $args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
    if ($LauncherRoot) { $args += @('-LauncherRoot', "`"$LauncherRoot`"") }
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait -ArgumentList $args
    exit
}

# hosts
if (Test-Path $HostsBak) {
    Copy-Item -LiteralPath $HostsBak -Destination $HostsFile -Force
    Ok 'hosts 已从备份还原'
} else {
    $lines = Get-Content -LiteralPath $HostsFile -ErrorAction SilentlyContinue |
             Where-Object { $_ -notmatch 'dsp-prod-of\.inutan\.com' -and $_ -notmatch 'taptap-solo-patch' }
    [IO.File]::WriteAllLines($HostsFile, [string[]]$lines, (New-Object Text.UTF8Encoding($false)))
    Ok 'hosts 里的补丁行已删除'
}
& ipconfig /flushdns | Out-Null

# portproxy
& netsh interface portproxy delete v4tov4 listenaddress=127.0.0.1 listenport=18881 2>$null | Out-Null
Ok '端口转发 18881 已删除'

# PCSDKUI
if ($LauncherRoot) {
    $sdkDir = Join-Path $LauncherRoot 'profiles\solo\client\launcher_Data\Plugins\Win\PCSDK_release'
    $orig   = Join-Path $sdkDir 'PCSDKUI.orig.exe'
    $target = Join-Path $sdkDir 'PCSDKUI.exe'
    if (Test-Path $orig) {
        Copy-Item -LiteralPath $orig -Destination $target -Force
        Ok 'PCSDKUI.exe 已还原为原版'
    } else {
        Warn '没有找到 PCSDKUI.orig.exe，跳过（可删除 profiles\solo\client 让启动器重建）'
    }
}

# 代理旁路
$proxyBak = Join-Path $HookDir 'proxy-override.backup'
if (Test-Path $proxyBak) {
    $origin = [IO.File]::ReadAllText($proxyBak, [Text.Encoding]::UTF8)
    Set-ItemProperty -Path $RegPath -Name ProxyOverride -Value $origin -Type String
    Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class TspWinInet2 { [DllImport("wininet.dll")] public static extern bool InternetSetOption(IntPtr h,int o,IntPtr b,int n); }' -ErrorAction SilentlyContinue
    [TspWinInet2]::InternetSetOption([IntPtr]::Zero,39,[IntPtr]::Zero,0) | Out-Null
    [TspWinInet2]::InternetSetOption([IntPtr]::Zero,37,[IntPtr]::Zero,0) | Out-Null
    Ok '代理设置已从备份还原'
} else {
    $cur = (Get-ItemProperty -Path $RegPath -ErrorAction SilentlyContinue).ProxyOverride
    if ($cur) {
        $parts = $cur -split ';' | Where-Object { $_ -ne '' -and $_ -notin @('*.inutan.com','14.103.*') }
        Set-ItemProperty -Path $RegPath -Name ProxyOverride -Value ($parts -join ';') -Type String
        Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class TspWinInet2 { [DllImport("wininet.dll")] public static extern bool InternetSetOption(IntPtr h,int o,IntPtr b,int n); }' -ErrorAction SilentlyContinue
        [TspWinInet2]::InternetSetOption([IntPtr]::Zero,39,[IntPtr]::Zero,0) | Out-Null
        [TspWinInet2]::InternetSetOption([IntPtr]::Zero,37,[IntPtr]::Zero,0) | Out-Null
        Ok '代理旁路条目已清理'
    }
}

Step '完成'
Write-Host '  现在客户端与安装补丁前一致，可以正常走官方登录。' -ForegroundColor Gray
Read-Host '按回车关闭'
