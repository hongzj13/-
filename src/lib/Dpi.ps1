# Dpi.ps1 -- 高分屏（DPI）感知与清晰渲染
# 未声明 DPI 感知时，Windows 会把窗口按 96dpi 渲染后整块位图放大 -> 字体发虚。
# 本文件在进程启动早期声明「系统 DPI 感知」，并记录缩放系数（150% -> 1.5）。
# 目标运行时：Windows PowerShell 5.1

$script:DpiScale = 1.0
$script:DpiInitialized = $false

function Initialize-Dpi {
    if ($script:DpiInitialized) { return $script:DpiScale }
    $script:DpiInitialized = $true
    # 读取 DPI 前必须先加载 System.Drawing（入口里此刻尚未加载）
    Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
    try {
        $src = 'using System;' + "`n" +
               'using System.Runtime.InteropServices;' + "`n" +
               'public static class DpiNative {' + "`n" +
               '    [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);' + "`n" +
               '    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();' + "`n" +
               '}'
        Add-Type -TypeDefinition $src -ErrorAction SilentlyContinue
        $ok = $false
        try { $ok = [DpiNative]::SetProcessDpiAwarenessContext([IntPtr](-2)) } catch { }   # SYSTEM_DPI_AWARE
        if (-not $ok) { try { $ok = [DpiNative]::SetProcessDPIAware() } catch { } }
    } catch { }
    try {
        $g = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
        $script:DpiScale = [math]::Round($g.DpiX / 96.0, 3)
        $g.Dispose()
    } catch { $script:DpiScale = 1.0 }
    if ($script:DpiScale -lt 0.9 -or $script:DpiScale -gt 4.0) { $script:DpiScale = 1.0 }
    return $script:DpiScale
}

function Get-DpiScale {
    if ($script:DpiScale -and $script:DpiScale -gt 0) { return $script:DpiScale }
    return 1.0
}
