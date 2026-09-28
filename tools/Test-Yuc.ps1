# Test-Yuc.ps1 -- 用 tools/samples 下的真实页面快照验证 yuc.wiki 解析（离线，不需要联网）
param([string]$Sample = 'yuc_202610.html')

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$Global:AnimeWidgetRoot = $root

. (Join-Path $root 'src\lib\Util.ps1')
. (Join-Path $root 'src\lib\Yuc.ps1')

$path = Join-Path $root ('tools\samples\' + $Sample)
$html = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
$key = ($Sample -replace 'yuc_', '') -replace '\.html$', ''

$parsed = ConvertFrom-YucSeasonPage -Html $html -SeasonKey $key
Write-Host ("== {0} ==  标题: {1}  季档: {2}  收录: {3} 部" -f $key, $parsed.title, $parsed.seasonLabel, $parsed.newCount)
Write-Host ("日表条目: {0}   详情条目: {1}" -f $parsed.schedule.Count, $parsed.details.Count)

$joined = Join-YucSeasonData -Parsed $parsed
Write-Host ("合并后: {0}" -f $joined.Count)
Write-Host ''
Write-Host '--- 前 6 条 ---'
$joined | Select-Object -First 6 | ForEach-Object {
    $d = if ($_.firstAir) { $_.firstAir.ToString('yyyy-MM-dd') } else { '?' }
    $pf = ($_.platforms | ForEach-Object { "$($_.name)[$($_.region)]" }) -join ','
    Write-Host ("{0} {1,-6} {2,-12} {3} | {4} | 标签: {5} | 类型: {6}" -f (Get-WeekdayName $_.weekday), $_.timeJst, $d, $_.title, $pf, ($_.tags -join '/'), $_.type)
    if ($_.titleJp) { Write-Host ("      日文名: {0}  官网: {1}" -f $_.titleJp, $_.site) }
}

Write-Host ''
Write-Host '--- 网络放送 ---'
$joined | Where-Object { $_.isStreaming } | ForEach-Object {
    Write-Host ("{0} | {1} | {2}" -f $_.title, $_.streamNote, $_.epNote)
}

Write-Host ''
Write-Host '--- 各日计数 ---'
0..6 | ForEach-Object { $i = $_; $c = ($joined | Where-Object { $_.weekday -eq $i }).Count; Write-Host ("{0}: {1}" -f (Get-WeekdayName $i), $c) }

Write-Host ''
Write-Host '--- 未解析出时间/日期的条目 ---'
$joined | Where-Object { -not $_.timeJst -or -not $_.firstAir } | Select-Object -First 12 | ForEach-Object {
    Write-Host ("  [{0}] time='{1}' day='{2}' stream={3}" -f $_.title, $_.timeJst, $_.dayText, $_.isStreaming)
}
Write-Host ''
Write-Host '--- 详情样例（第一条有 staff 的）---'
$d0 = $parsed.details | Where-Object { $_.staff } | Select-Object -First 1
Write-Host ("中文名: {0}`n日文名: {1}`n类型: {2}`n标签: {3}`n官网: {4}`n档位: {5}" -f $d0.titleCn, $d0.titleJp, $d0.type, ($d0.tags -join '/'), $d0.site, $d0.broadcast)
Write-Host ("staff 第一行: {0}" -f (($d0.staff -split "`n")[0]))
Write-Host ("cast 第一行: {0}" -f (($d0.cast -split "`n")[0]))
