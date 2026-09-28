# Test-Follows.ps1 -- 验证 Bangumi「在看」读取与追番匹配
#   -Username <名字>   用公开收藏（不需要 Token）
#   不加参数则用 data\auth.json 里的 Token
param(
    [string]$Root = (Split-Path -Parent (Split-Path -Parent $PSCommandPath)),
    [string]$Username = '',
    [int]$Type = 3
)
$Global:AnimeWidgetRoot = (Resolve-Path -LiteralPath $Root).Path
. (Join-Path $Global:AnimeWidgetRoot 'src\lib\Util.ps1')
. (Join-Path $Global:AnimeWidgetRoot 'src\lib\Http.ps1')
. (Join-Path $Global:AnimeWidgetRoot 'src\lib\Yuc.ps1')
. (Join-Path $Global:AnimeWidgetRoot 'src\lib\Bangumi.ps1')
. (Join-Path $Global:AnimeWidgetRoot 'src\lib\Data.ps1')

$config = Get-WidgetConfig
$token = ''
if (-not $Username) {
    $auth = Get-BangumiAuth
    $auth = Update-BangumiAuthToken -Config $config
    $token = [string]$auth.accessToken
    if ($token) { $Username = [string]$auth.username }
}
if (-not $Username -and -not $token) {
    Write-Host '既没有 Token 也没有用户名：请先在设置里登录，或用 -Username 指定。'
    exit 1
}

Write-Host ('读取在看：{0}{1}（type={2}）' -f $(if ($token) { 'Token 用户 ' } else { '公开用户 ' }), $Username, $Type)
$col = Get-BangumiCollections -Username $Username -Token $token -Type $Type -Config $config -Force -MaxAgeMinutes 1
if (-not $col.ok) { Write-Host ('失败：' + $col.error); exit 1 }
Write-Host ('成功：共 {0} 条在看（total={1}）' -f $col.items.Count, $col.total)
$col.items | Select-Object -First 12 | ForEach-Object {
    $subj = Get-Prop $_ 'subject'
    Write-Host ('  - {0} / {1}' -f (Get-Prop $subj 'name_cn' ''), (Get-Prop $subj 'name' ''))
}

$state = Get-WidgetState
if (-not $state) { Write-Host '（没有 state.json，跳过匹配测试；先跑 tools\Refresh-Once.ps1）'; exit 0 }
$shows = @($state.shows)
$warn = New-Object System.Collections.ArrayList
$r = Get-FollowedInfo -Config $config -Shows $shows -Force -Warnings $warn
Write-Host ''
Write-Host ('匹配结果：在追 {0} 部（用户名 {1}）' -f $r.count, $r.username)
$shows | Where-Object { $_.followed } | Sort-Object { $_.localWeekday }, { $_.timeLocal } | ForEach-Object {
    Write-Host ('  ★ {0} {1}  {2}' -f (Get-WeekdayName $_.localWeekday), $_.timeLocal, $_.title)
}
