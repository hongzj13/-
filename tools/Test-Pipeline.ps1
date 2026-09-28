# Test-Pipeline.ps1 -- 离线验证数据管线：用 tools/samples 的真实快照填充缓存，然后跑一遍 Build-WidgetData
param([switch]$UseFakeFollows)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$Global:AnimeWidgetRoot = $root
$Global:AnimeWidgetVerbose = $false

. (Join-Path $root 'src\lib\Util.ps1')
. (Join-Path $root 'src\lib\Http.ps1')
. (Join-Path $root 'src\lib\Yuc.ps1')
. (Join-Path $root 'src\lib\Bangumi.ps1')
. (Join-Path $root 'src\lib\Data.ps1')

$cacheDir = Get-CacheDir
if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null }

function Seed-Cache {
    param([string]$CacheKey, [string]$Text, [string]$Method = 'GET', [string]$Body = '')
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $hash = [System.BitConverter]::ToString($md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Method + '|' + $CacheKey + '|' + $Body))).Replace('-', '').ToLower()
    [System.IO.File]::WriteAllText((Join-Path $cacheDir ($hash + '.body')), $Text, (New-Object System.Text.UTF8Encoding($false)))
    $meta = [pscustomobject]@{ url = 'seed://' + $CacheKey; fetchedAt = (Get-Date).ToString('o'); via = 'seed'; status = 200 }
    Write-JsonFile (Join-Path $cacheDir ($hash + '.meta.json')) $meta | Out-Null
}

$samples = Join-Path $root 'tools\samples'
Write-Host '== 播种缓存 =='
Seed-Cache 'yuc:202610' ([System.IO.File]::ReadAllText((Join-Path $samples 'yuc_202610.html'), [System.Text.Encoding]::UTF8))
Seed-Cache 'yuc:202607' ([System.IO.File]::ReadAllText((Join-Path $samples 'yuc_202607.html'), [System.Text.Encoding]::UTF8))
Seed-Cache 'bgm:calendar' ([System.IO.File]::ReadAllText((Join-Path $samples 'bgm_calendar.json'), [System.Text.Encoding]::UTF8))
Seed-Cache 'bgm:subject:569116' ([System.IO.File]::ReadAllText((Join-Path $samples 'bgm_subject_569116.json'), [System.Text.Encoding]::UTF8))

# 用日历里的 3 部当季番构造一份「在看」收藏，验证追番匹配
$cal = Get-Content (Join-Path $samples 'bgm_calendar.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$picked = @($cal[0].items | Select-Object -First 3)
$colItems = @()
foreach ($p in $picked) {
    $colItems += [pscustomobject]@{
        subject_id = $p.id; type = 3; ep_status = 1
        subject    = [pscustomobject]@{ id = $p.id; name = $p.name; name_cn = $p.name_cn; images = $p.images; date = $p.air_date; score = $p.rating.score }
    }
}
$colPayload = [pscustomobject]@{ total = $colItems.Count; limit = 100; offset = 0; data = $colItems } | ConvertTo-Json -Depth 8
Seed-Cache 'bgm:collections:3:sai:0' $colPayload
Write-Host ("  yuc:202610 / yuc:202607 / bgm:calendar / bgm:subject:569116 / bgm:collections:3:sai:0 ({0} 条在看)" -f $colItems.Count)

Write-Host ''
Write-Host '== 跑数据管线（离线，全部走缓存）=='
$cfg = Get-WidgetConfig
$cfg.network.proxyMode = 'direct'          # 无网络时快速失败，不影响缓存命中
$cfg.network.allowInsecureTls = $true
$cfg.data.maxResolvePerRefresh = 0         # 离线不解析新 ID
$cfg.bangumi.usePublicCollections = $true
$cfg.bangumi.username = 'sai'

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$state = Build-WidgetData -Config $cfg -Progress { param($m) Write-Host ("  · " + $m) }
$sw.Stop()
Write-Host ("耗时 {0:N0} ms" -f $sw.ElapsedMilliseconds)

Write-Host ''
Write-Host ("状态：共 {0} 部，在追 {1} 部，日历可用={2}，来源条目={3}" -f $state.shows.Count, $state.followedCount, $state.calendarOk, $state.sourceCount)
Write-Host ("季表：{0}" -f (($state.seasons | ForEach-Object { "$($_.key)/$($_.label)/$($_.count)部" }) -join '  '))
if ($state.warnings.Count -gt 0) { Write-Host '警告：'; $state.warnings | ForEach-Object { Write-Host ("  ! " + $_) } }

$todayWd = Get-WeekdayIndex (Get-Date)
Write-Host ''
Write-Host ("== 今天（{0}）本地时间的播出表 ==" -f (Get-WeekdayName $todayWd))
$today = Get-ShowsByDay -Shows $state.shows -LocalWeekday $todayWd
if ($today.Count -eq 0) { Write-Host '  （今天没有条目）' }
foreach ($s in $today) {
    $pf = @()
    if ($s.station) { $pf += $s.station }
    foreach ($p in @($s.platforms)) { $pf += $p.name }
    $star = if ($s.followed) { '★' } else { ' ' }
    Write-Host (" {0} {1}  {2,-34} JST {3,-6} [{4}] {5}" -f $star, $s.timeLocal, $s.title, $s.timeJst, ($pf -join '/'), ($s.tags -join '·'))
}

Write-Host ''
Write-Host '== 各星期条目数（北京时间归组）=='
0..6 | ForEach-Object { Write-Host ("  {0}: {1}" -f (Get-WeekdayName $_), (Get-ShowsByDay -Shows $state.shows -LocalWeekday $_).Count) }

Write-Host ''
Write-Host '== 跨日换算抽查（JST 24:00 之后）=='
$state.shows | Where-Object { $_.timeJst -match '^2[4-9]:' } | Select-Object -First 8 | ForEach-Object {
    Write-Host ("  {0,-38} JST {1} ({2}) -> 北京 {3} ({4})" -f $_.title, $_.timeJst, (Get-WeekdayName $_.weekday), $_.timeLocal, (Get-WeekdayName $_.localWeekday))
}

Write-Host ''
Write-Host '== 在追命中 =='
$state.shows | Where-Object { $_.followed } | ForEach-Object { Write-Host ("  ★ {0} ({1} {2})" -f $_.title, (Get-WeekdayName $_.localWeekday), $_.timeLocal) }

Write-Host ''
Write-Host '== 网络放送 =='
Get-StreamingShows -Shows $state.shows | ForEach-Object { Write-Host ("  {0} | {1} | {2}" -f $_.title, $_.streamNote, $_.epNote) }

$next = Get-NextShow -Shows $state.shows
if ($next) { Write-Host ("`n下一部：{0} {1}（{2} 分钟后）" -f $next.show.title, $next.show.timeLocal, $next.minutes) }
