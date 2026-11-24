# 一键切换：单机 <-> 官服
# 双击运行进入菜单；也可以带参数直接切换：
#   powershell -ExecutionPolicy Bypass -File switch.ps1 -Mode official
#   powershell -ExecutionPolicy Bypass -File switch.ps1 -Mode solo

param(
    [ValidateSet('solo','official','')][string]$Mode = '',
    [string]$LauncherRoot = ''
)

$ErrorActionPreference = 'Continue'
$HookDir      = $PSScriptRoot
$StubExe      = Join-Path $HookDir 'tools\PCSDKUIStub.exe'
$PathFile     = Join-Path $HookDir 'launcher.path'
$HostsFile    = Join-Path $env:WINDIR 'System32\drivers\etc\hosts'
$HostsBak     = Join-Path $HookDir 'hosts.backup'
$RegPath      = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
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

# 允许直接拖 OverFieldLauncher.exe，或拖启动器文件夹
function Normalize-LauncherPath([string]$p) {
    if ([string]::IsNullOrWhiteSpace($p)) { return '' }
    $p = $p.Trim().Trim('"').Trim("'").Trim()
    if ($p -match '\.exe$') { $p = Split-Path $p -Parent }
    if (Test-Path $p) { return (Resolve-Path $p).Path }
    return ''
}

function Find-Launcher {
    $cands = @()
    if ($LauncherRoot) { $cands += $LauncherRoot }
    if (Test-Path $PathFile) {
        $saved = Get-Content -LiteralPath $PathFile -Raw -ErrorAction SilentlyContinue
        if ($saved) { $cands += $saved }
    }
    $cands += $HookDir
    $cands += (Split-Path $HookDir -Parent)
    foreach ($c in $cands) {
        $n = Normalize-LauncherPath $c
        if ($n -and (Test-Launcher $n)) { return $n }
    }
    return $null
}

function Save-LauncherPath([string]$p) {
    try { [IO.File]::WriteAllText($PathFile, $p, (New-Object Text.UTF8Encoding($false))) } catch { }
}

function Get-CurrentMode {
    $text = Get-Content -LiteralPath $HostsFile -ErrorAction SilentlyContinue
    if ($text -match [regex]::Escape($DispatchHost)) { return 'solo' }
    return 'official'
}

# ---------- 菜单 ----------
if (-not $Mode) {
    $current = Get-CurrentMode
    $known = Find-Launcher
    Write-Host ''
    Write-Host '============================================' -ForegroundColor Cyan
    Write-Host '   开放空间 · 单机 / 官服 一键切换' -ForegroundColor Cyan
    Write-Host '============================================' -ForegroundColor Cyan
    if ($current -eq 'solo') {
        Write-Host '   当前状态：单机模式（走本机服务端）' -ForegroundColor Yellow
    } else {
        Write-Host '   当前状态：官服模式（走官方服务器）' -ForegroundColor Yellow
    }
    if ($known) {
        Write-Host "   启动器目录：$known" -ForegroundColor DarkGray
    } else {
        Write-Host '   启动器目录：未记录（选 1 时会问你一次，之后记住）' -ForegroundColor DarkGray
    }
    Write-Host ''
    Write-Host '   1  切到【单机模式】'
    Write-Host '   2  切回【官服模式】'
    Write-Host '   0  退出'
    Write-Host ''
    $sel = Read-Host '请输入 1 / 2 / 0'
    switch ($sel.Trim()) {
        '1' { $Mode = 'solo' }
        '2' { $Mode = 'official' }
        default { Write-Host '已退出。' -ForegroundColor Gray; Start-Sleep -Milliseconds 500; exit }
    }
}

# 只有切单机才必须知道启动器目录
$found = $null
if ($Mode -eq 'solo') {
    $found = Find-Launcher
    while (-not $found) {
        Warn '请把「OverFieldLauncher.exe 所在的文件夹」拖进来后回车'
        Write-Host '     （这个文件夹里应该有 OverFieldLauncher.exe，不是游戏客户端目录 176228）' -ForegroundColor DarkGray
        Write-Host '     （直接拖 OverFieldLauncher.exe 这个文件也可以）' -ForegroundColor DarkGray
        $in = Read-Host '  路径'
        $found = Normalize-LauncherPath $in
        if (-not $found) { Warn '这个路径里没有 OverFieldLauncher.exe，再试一次。' }
    }
    Save-LauncherPath $found
    Ok "启动器目录：$found（已记录，下次不用再填）"
}

if (-not (Test-Admin)) {
    Warn '需要管理员权限，正在申请提权…（UAC 点「是」）'
    $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"",'-Mode',$Mode)
    if ($found) { $argList += @('-LauncherRoot', "`"$found`"") }
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait -ArgumentList $argList
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
    Write-Host '  已切回官服。' -ForegroundColor Green
    Write-Host '  现在直接点 TapTap / 官方启动器启动即可。' -ForegroundColor Gray
    if (Get-Process -Name 'Lolo' -ErrorAction SilentlyContinue) {
        Write-Host '  提示：本地 Lolo.exe 还在跑，可在启动器点「停止」或在任务管理器结束它。' -ForegroundColor Yellow
    }
    Write-Host ''
    Read-Host '按回车关闭'
    exit
}

# ---------- 回单机 ----------
if (-not $found) { $found = Find-Launcher }
if (-not $found) { Warn '没有启动器目录，无法继续。'; Read-Host '按回车退出'; exit 1 }
Save-LauncherPath $found

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
    } else {
        Warn "缺少 $StubExe，替身没装"
    }
} else {
    Warn '还没生成客户端副本：先打开启动器点一次「启动单机游戏」再回来。'
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
Write-Host '  已切到单机。' -ForegroundColor Green
Write-Host '  现在打开启动器 → 单机模式 → 启动单机游戏（渠道登录弹窗直接关）。' -ForegroundColor Gray
Write-Host ''
Read-Host '按回车关闭'
