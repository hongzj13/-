# Refresh-Once.ps1 -- 无界面刷新一次数据（用于调试 / 计划任务）
param([string]$Root = (Split-Path -Parent (Split-Path -Parent $PSCommandPath)), [switch]$Force, [int]$MaxResolve = -1)

$Global:AnimeWidgetRoot = (Resolve-Path -LiteralPath $Root).Path
. (Join-Path $Global:AnimeWidgetRoot 'src\lib\Util.ps1')
. (Join-Path $Global:AnimeWidgetRoot 'src\lib\Http.ps1')
. (Join-Path $Global:AnimeWidgetRoot 'src\lib\Yuc.ps1')
. (Join-Path $Global:AnimeWidgetRoot 'src\lib\Bangumi.ps1')
. (Join-Path $Global:AnimeWidgetRoot 'src\lib\Data.ps1')

$config = Get-WidgetConfig
if ($MaxResolve -ge 0) { $config.data.maxResolvePerRefresh = $MaxResolve }
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$state = Build-WidgetData -Config $config -Force:$Force -Progress { param($m) Write-Host ('  · ' + $m) }
$sw.Stop()

Write-Host ''
Write-Host ('刷新完成：{0} 部新番，在追 {1} 部，耗时 {2:N1}s' -f @($state.shows).Count, $state.followedCount, ($sw.ElapsedMilliseconds / 1000))
foreach ($w in @($state.warnings)) { Write-Host ('  ! ' + $w) }
$today = Get-WeekdayIndex (Get-Date)
$list = Get-ShowsByDay -Shows $state.shows -LocalWeekday $today
Write-Host ('今天（{0}）共 {1} 部：' -f (Get-WeekdayName $today), $list.Count)
foreach ($s in $list) { Write-Host ('  {0}  {1}{2}' -f $s.timeLocal, $(if ($s.followed) { '★ ' } else { '' }), $s.title) }
