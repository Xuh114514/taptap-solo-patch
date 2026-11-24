# 一键切换：单机 <-> 官服
# 用法：
#   powershell -ExecutionPolicy Bypass -File switch.ps1 -Mode official   # 回官服
#   powershell -ExecutionPolicy Bypass -File switch.ps1 -Mode solo       # 回单机

param(
    [ValidateSet('solo','official')][string]$Mode = 'solo',
    [string]$LauncherRoot = ''
)

$ErrorActionPreference = 'Continue'
$HookDir   = $PSScriptRoot
$StubExe   = Join-Path $HookDir 'tools\PCSDKUIStub.exe'
$HostsFile = Join-Path $env:WINDIR 'System32\drivers\etc\hosts'
$HostsBak  = Join-Path $HookDir 'hosts.backup'
$RegPath   = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
$DispatchHost = 'dsp-prod-of.inutan.com'

function Ok($t)   { Write-Host "[OK]   $t" -ForegroundColor Green }
function Warn($t) { Write-Host "[注意] $t" -ForegroundColor Yellow }

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Test-Launcher([string]$p) {
    if ([string]::IsNullOrWhiteSpace($p)) { return $false }
    return (Test-Path (Join-Path $p 'OverFieldLauncher.exe'))
}

# 定位启动器（只有切到单机时才需要）
$found = $null
foreach ($c in @($LauncherRoot, $HookDir, (Split-Path $HookDir -Parent))) {
    if (Test-Launcher $c) { $found = (Resolve-Path $c).Path; break }
}
if ($Mode -eq 'solo' -and -not $found) {
    Warn '没找到启动器目录，请把启动器文件夹拖进来后回车：'
    $in = (Read-Host '  目录').Trim('"').Trim("'").Trim()
    if (Test-Launcher $in) { $found = (Resolve-Path $in).Path }
}

if (-not (Test-Admin)) {
    Warn '需要管理员权限，正在申请提权…（UAC 点「是」）'
    $args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"",'-Mode',$Mode)
    if ($found) { $args += @('-LauncherRoot', "`"$found`"") }
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait -ArgumentList $args
    exit
}

if ($Mode -eq 'official') {
    # ---------- 回官服 ----------
    if (Test-Path $HostsBak) {
        Copy-Item -LiteralPath $HostsBak -Destination $HostsFile -Force
        Ok 'hosts 已从备份还原'
    } else {
        $lines = Get-Content -LiteralPath $HostsFile -ErrorAction SilentlyContinue |
                 Where-Object { $_ -notmatch 'dsp-prod-of\.inutan\.com' -and $_ -notmatch 'taptap-solo-patch' }
        [IO.File]::WriteAllLines($HostsFile, [string[]]$lines, (New-Object Text.UTF8Encoding($false)))
        Ok 'hosts 里的劫持行已删除'
    }
    & netsh interface portproxy delete v4tov4 listenaddress=127.0.0.1 listenport=18881 2>$null | Out-Null
    Ok '端口转发 18881 已删除'
    & ipconfig /flushdns | Out-Null

    $cur = (Get-ItemProperty -Path $RegPath -ErrorAction SilentlyContinue).ProxyOverride
    if ($cur) {
        $parts = $cur -split ';' | Where-Object { $_ -ne '' -and $_ -notin @('*.inutan.com','14.103.*') }
        Set-ItemProperty -Path $RegPath -Name ProxyOverride -Value ($parts -join ';') -Type String
        Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class SwWinInet { [DllImport("wininet.dll")] public static extern bool InternetSetOption(IntPtr h,int o,IntPtr b,int n); }' -ErrorAction SilentlyContinue
        [SwWinInet]::InternetSetOption([IntPtr]::Zero,39,[IntPtr]::Zero,0) | Out-Null
        [SwWinInet]::InternetSetOption([IntPtr]::Zero,37,[IntPtr]::Zero,0) | Out-Null
        Ok '代理旁路已清理'
    }
    Write-Host ''
    Write-Host '  现在直接用 TapTap / 官方启动器启动，就是官服。' -ForegroundColor Green
    Read-Host '按回车关闭'
    exit
}

# ---------- 回单机 ----------
if (-not $found) { Warn '没有启动器目录，无法继续。'; Read-Host '按回车退出'; exit 1 }

$sdkDir  = Join-Path $found 'profiles\solo\client\launcher_Data\Plugins\Win\PCSDK_release'
$stubDst = Join-Path $sdkDir 'PCSDKUI.exe'
$stubBak = Join-Path $sdkDir 'PCSDKUI.orig.exe'

if (Test-Path $sdkDir) {
    if (-not (Test-Path $stubBak) -and (Test-Path $stubDst)) {
        Copy-Item -LiteralPath $stubDst -Destination $stubBak -Force
    }
    if (Test-Path $StubExe) {
        Copy-Item -LiteralPath $StubExe -Destination $stubDst -Force
        Ok '替身 PCSDKUI 已就位'
    }
} else {
    Warn "还没生成客户端副本：先打开启动器点一次「启动单机游戏」再回来。"
}

$text = Get-Content -LiteralPath $HostsFile -ErrorAction SilentlyContinue
if (-not ($text -match [regex]::Escape($DispatchHost))) {
    if (-not (Test-Path $HostsBak)) { Copy-Item -LiteralPath $HostsFile -Destination $HostsBak -Force }
    Add-Content -LiteralPath $HostsFile -Value "`r`n# taptap-solo-patch"
    Add-Content -LiteralPath $HostsFile -Value "127.0.0.1 $DispatchHost"
    Ok 'hosts 已劫持 dispatch 域名'
} else {
    Ok 'hosts 已是劫持状态'
}

& netsh interface portproxy delete v4tov4 listenaddress=127.0.0.1 listenport=18881 2>$null | Out-Null
& netsh interface portproxy add v4tov4 listenaddress=127.0.0.1 listenport=18881 connectaddress=127.0.0.1 connectport=18080
Ok '端口转发 18881 -> 18080 已就绪'
& ipconfig /flushdns | Out-Null

$cur = (Get-ItemProperty -Path $RegPath -ErrorAction SilentlyContinue).ProxyOverride
if ($cur) {
    $parts = $cur -split ';' | Where-Object { $_ -ne '' -and $_ -ne '<local>' }
    foreach ($item in @('*.inutan.com','14.103.*')) { if ($parts -notcontains $item) { $parts += $item } }
    Set-ItemProperty -Path $RegPath -Name ProxyOverride -Value (($parts -join ';') + ';<local>') -Type String
    Ok '代理旁路已就绪'
}

Write-Host ''
Write-Host '  现在打开启动器 → 单机模式 → 启动单机游戏。' -ForegroundColor Green
Read-Host '按回车关闭'
