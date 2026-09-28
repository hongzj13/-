# AnimeWidget.ps1 -- 新番桌面小组件 入口
#   数据来源：yuc.wiki（長門番堂）新番表 + Bangumi (bgm.tv) API
#   用法：powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File src\AnimeWidget.ps1 -Root <项目根>
#   可选参数：
#     -Screenshot <png>   把界面渲染成图片（自检 / 无交互）
#     -NoAutoRefresh      启动时不自动刷新
#     -NoWindow           不显示窗口（配合 -Screenshot）
param(
    [string]$Root = (Split-Path -Parent $PSCommandPath),
    [string]$Screenshot = '',
    [string]$ScreenshotView = '',
    [switch]$NoAutoRefresh,
    [switch]$DebugConsole
)

$ErrorActionPreference = 'Stop'
$Global:AnimeWidgetRoot = (Resolve-Path -LiteralPath $Root).Path
$Global:AnimeWidgetVerbose = [bool]$DebugConsole

. (Join-Path $Global:AnimeWidgetRoot 'src\lib\Util.ps1')
. (Join-Path $Global:AnimeWidgetRoot 'src\lib\Http.ps1')
. (Join-Path $Global:AnimeWidgetRoot 'src\lib\Yuc.ps1')
. (Join-Path $Global:AnimeWidgetRoot 'src\lib\Bangumi.ps1')
. (Join-Path $Global:AnimeWidgetRoot 'src\lib\Data.ps1')
. (Join-Path $Global:AnimeWidgetRoot 'src\lib\Ui.ps1')
. (Join-Path $Global:AnimeWidgetRoot 'src\lib\UiDialogs.ps1')
. (Join-Path $Global:AnimeWidgetRoot 'src\lib\UiRuntime.ps1')

Write-Log '================ 小组件启动 ================' 'INFO'

try {
    $config = Get-WidgetConfig
} catch {
    Write-Log "配置读取失败，使用默认配置：$($_.Exception.Message)" 'WARN'
    $defaults = Get-DefaultConfig
    $config = [pscustomobject]@{
        version = 1
        ui      = [pscustomobject]$defaults.ui
        data    = [pscustomobject]$defaults.data
        network = [pscustomobject]$defaults.network
        bangumi = [pscustomobject]$defaults.bangumi
    }
}

$state = Get-WidgetState

# ---------------- 自检渲染（不需要交互）----------------
if ($Screenshot) {
    $win = New-WidgetWindow -Config $config -State $state
    if ($ScreenshotView) {
        switch -Regex ($ScreenshotView) {
            '^(?i)follow' { $win.Ui.Tab = 'follow' }
            '^(?i)stream' { $win.Ui.Tab = 'stream' }
            '^[0-6]$' { $win.Ui.Tab = 'day'; $win.Ui.Day = [int]$ScreenshotView }
        }
    }
    $form = $win.Form
    $form.CreateControl()
    Update-UiRegions -Ui $win.Ui
    Update-WidgetScrollBounds -Ui $win.Ui
    $bmp = New-Object System.Drawing.Bitmap($form.Width, $form.Height)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        # 圆角外区域铺一层桌面色，便于观察边界
        $g.Clear([System.Drawing.ColorTranslator]::FromHtml('#3A3A44'))
        Draw-Widget -G $g -Ui $win.Ui
        $bmp.Save($Screenshot, [System.Drawing.Imaging.ImageFormat]::Png)
        Write-Host ("已渲染界面截图：{0}" -f $Screenshot)
    } finally {
        $g.Dispose()
        $bmp.Dispose()
    }
    $form.Dispose()
    return
}

# ---------------- 单实例 ----------------
$mutex = New-Object System.Threading.Mutex($false, 'Local\AnimeAiringWidget_DSH')
$hasLock = $false
try { $hasLock = $mutex.WaitOne(0) } catch { $hasLock = $true }
if (-not $hasLock) {
    Write-Log '已有实例在运行，本次启动退出' 'INFO'
    return
}

# ---------------- 启动界面 ----------------
try {
    $startOutput = Start-Widget -Config $config -State $state
    if ($startOutput) {
        Write-Log ('Start-Widget 杂散输出：' + (($startOutput | ForEach-Object { $_.GetType().Name + ':' + $_.ToString() }) -join ' | ')) 'DEBUG'
    }
    if ($NoAutoRefresh) { Write-Log '（-NoAutoRefresh）' 'INFO' }
} catch {
    Write-Log "界面异常退出：$($_.Exception.Message)`n$($_.ScriptStackTrace)" 'ERROR'
    if ($DebugConsole) {
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host $_.ScriptStackTrace
        Read-Host '按回车退出'
    }
} finally {
    try { if ($hasLock) { $mutex.ReleaseMutex() } } catch { }
    Write-Log '================ 小组件退出 ================' 'INFO'
}
