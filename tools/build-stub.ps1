# 用系统自带的 csc.exe 编译替身 PCSDKUI.exe（不需要 Visual Studio）
# 用法：powershell -ExecutionPolicy Bypass -File tools\build-stub.ps1

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$cscCandidates = @(
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
)
$csc = $cscCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $csc) { throw '没找到 csc.exe，请确认系统是 Windows 10/11 且 .NET Framework 4.x 完整。' }

$src = Join-Path $here 'PCSDKUIStub.cs'
$out = Join-Path $here 'PCSDKUIStub.exe'

& $csc /nologo /target:exe /platform:x64 /optimize+ "/out:$out" $src
if ($LASTEXITCODE -ne 0) { throw '编译失败。' }
Write-Host "已生成：$out" -ForegroundColor Green
Write-Host ('大小：' + (Get-Item $out).Length + ' 字节') -ForegroundColor Gray
