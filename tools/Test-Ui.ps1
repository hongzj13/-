# Test-Ui.ps1 -- 离屏渲染各视图与对话框，便于人工/自动核对界面
param([string]$Root = (Split-Path -Parent (Split-Path -Parent $PSCommandPath)))

$Global:AnimeWidgetRoot = (Resolve-Path -LiteralPath $Root).Path
$build = Join-Path $Global:AnimeWidgetRoot 'build'
if (-not (Test-Path $build)) { New-Item -ItemType Directory -Force -Path $build | Out-Null }

. (Join-Path $Global:AnimeWidgetRoot 'src\lib\Util.ps1')
. (Join-Path $Global:AnimeWidgetRoot 'src\lib\Http.ps1')
. (Join-Path $Global:AnimeWidgetRoot 'src\lib\Yuc.ps1')
. (Join-Path $Global:AnimeWidgetRoot 'src\lib\Bangumi.ps1')
. (Join-Path $Global:AnimeWidgetRoot 'src\lib\Data.ps1')
. (Join-Path $Global:AnimeWidgetRoot 'src\lib\Ui.ps1')
. (Join-Path $Global:AnimeWidgetRoot 'src\lib\UiDialogs.ps1')
. (Join-Path $Global:AnimeWidgetRoot 'src\lib\UiRuntime.ps1')

$config = Get-WidgetConfig
$state = Get-WidgetState
if (-not $state) { throw '没有 state.json，请先运行 tools\Test-Pipeline.ps1（离线）或 tools\Refresh-Once.ps1（联网）' }

function Render-View {
    param([string]$Name, [string]$Tab, [int]$Day = -1)
    $win = New-WidgetWindow -Config $config -State $state
    $win.Ui.Tab = $Tab
    if ($Day -ge 0) { $win.Ui.Day = $Day }
    $win.Form.CreateControl()
    Update-UiRegions -Ui $win.Ui
    Update-WidgetScrollBounds -Ui $win.Ui
    $bmp = New-Object System.Drawing.Bitmap($win.Form.Width, $win.Form.Height)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $g.Clear([System.Drawing.ColorTranslator]::FromHtml('#3A3A44'))
        Draw-Widget -G $g -Ui $win.Ui
        $bmp.Save((Join-Path $build ($Name + '.png')), [System.Drawing.Imaging.ImageFormat]::Png)
    } finally { $g.Dispose(); $bmp.Dispose() }
    $win.Form.Dispose()
    Write-Host ("  -> build\{0}.png ({1} 行)" -f $Name, @($win.Ui.VisibleShows).Count)
}

$today = Get-WeekdayIndex (Get-Date)
Write-Host '渲染主界面各视图：'
Render-View -Name 'view-today' -Tab 'day' -Day $today
Render-View -Name 'view-sat' -Tab 'day' -Day 5
Render-View -Name 'view-follow' -Tab 'follow'
Render-View -Name 'view-stream' -Tab 'stream'

Write-Host '渲染对话框：'
$sample = @($state.shows | Where-Object { -not $_.isStreaming } | Select-Object -First 1)[0]
if ($sample) {
    Show-DetailsDialog -Show $sample -Config $config -RenderTo (Join-Path $build 'dlg-details.png')
    Write-Host '  -> build\dlg-details.png'
}
Show-SettingsDialog -Config $config -RenderTo (Join-Path $build 'dlg-settings.png')
Write-Host '  -> build\dlg-settings.png'
Show-LoginDialog -Config $config -RenderTo (Join-Path $build 'dlg-login.png')
Write-Host '  -> build\dlg-login.png'
