# Data.ps1 -- 配置 / 数据合并 / 每日刷新 / 本地状态
# 目标运行时：Windows PowerShell 5.1

function Get-DefaultConfig {
    return @{
        version = 1
        ui      = @{
            topMost = $true; opacity = 1.0; width = 404; height = 348
            fontFamily = 'Microsoft YaHei UI'; accent = '#9D7BFF'; theme = 'deep-purple'; bgCustom = '#14121E'
            showTrayIcon = $true; rememberPosition = $true; rememberSize = $true; rowsPerView = 3
        }
        data    = @{
            yucBaseUrl = 'https://yuc.wiki'; useYuc = $true; useBangumi = $true
            lookaheadDays = 21; dropEndedAfterDays = 14; onlyNewAnime = $true
            showStreaming = $true; showJstTime = $true; resolveBangumiIds = $true
            maxResolvePerRefresh = 30; refreshHours = 6; dailyRefreshAt = '04:10'; showNextUp = $true
        }
        network = @{
            proxyMode = 'auto'; proxyUrl = 'http://127.0.0.1:7897'; allowInsecureTls = $true
            timeoutSec = 25; userAgent = 'anime-widget/1.0 (personal desktop widget)'
        }
        bangumi = @{
            username = ''; usePublicCollections = $false; oauthAppId = ''; oauthAppSecret = ''
            oauthRedirectPort = 3721; showOnlyFollowed = $false; highlightFollowed = $true
        }
    }
}

function Merge-ConfigSection {
    param($Defaults, $Override)
    $result = @{}
    foreach ($k in $Defaults.Keys) { $result[$k] = $Defaults[$k] }
    if ($Override) {
        $props = @()
        if ($Override -is [System.Collections.IDictionary]) { $props = @($Override.Keys) }
        else { $props = @($Override.PSObject.Properties.Name) }
        foreach ($k in $props) {
            $v = Get-Prop $Override $k $null
            if ($null -ne $v) { $result[$k] = $v }
        }
    }
    return [pscustomobject]$result
}

function Get-WidgetConfig {
    $path = Join-Path (Get-Root) 'config.json'
    $defaults = Get-DefaultConfig
    $file = Read-JsonFile $path
    $ui = Merge-ConfigSection $defaults.ui (Get-Prop $file 'ui')
    $data = Merge-ConfigSection $defaults.data (Get-Prop $file 'data')
    $net = Merge-ConfigSection $defaults.network (Get-Prop $file 'network')
    $bgm = Merge-ConfigSection $defaults.bangumi (Get-Prop $file 'bangumi')
    return [pscustomobject]@{ version = 1; ui = $ui; data = $data; network = $net; bangumi = $bgm; path = $path; raw = $file }
}

function Save-WidgetConfig {
    param($Config)
    $path = Join-Path (Get-Root) 'config.json'
    $obj = [pscustomobject]@{ version = 1; ui = $Config.ui; data = $Config.data; network = $Config.network; bangumi = $Config.bangumi }
    return (Write-JsonFile $path $obj)
}

function Get-StatePath { Join-Path (Get-DataDir) 'state.json' }

function Get-WidgetState {
    $s = Read-JsonFile (Get-StatePath)
    if (-not $s) { return $null }
    return $s
}

function Save-WidgetState {
    param($State)
    return (Write-JsonFile (Get-StatePath) $State)
}

# ---------- 时间换算 ----------
# yuc.wiki 的时间为日本时间（JST, UTC+9），"25:00~" 表示次日 01:00。
# 北京时间 = JST - 1 小时；换算后可能跨日，故同时给出本地星期与本地时刻。
function ConvertFrom-JstTime {
    param([string]$TimeJst, [int]$Weekday = -1)
    $h = 0; $mi = 0
    if ($TimeJst -match '^(\d{1,2}):(\d{2})') { $h = [int]$Matches[1]; $mi = [int]$Matches[2] }
    else { return [pscustomobject]@{ hour = -1; minute = 0; timeLocal = ''; dayOffset = 0; localWeekday = $Weekday } }
    $total = ($h * 60 + $mi) - 60          # JST -> 北京
    $dayOffset = [int][math]::Floor($total / 1440.0)
    $local = $total - ($dayOffset * 1440)
    $lw = $Weekday
    if ($Weekday -ge 0) {
        $lw = ((($Weekday + $dayOffset) % 7) + 7) % 7
    }
    return [pscustomobject]@{
        hour         = [int][math]::Floor($local / 60)
        minute       = [int]($local % 60)
        timeLocal    = ('{0:D2}:{1:D2}' -f [int][math]::Floor($local / 60), [int]($local % 60))
        dayOffset    = $dayOffset
        localWeekday = $lw
    }
}

# ---------- 名称匹配 ----------
# 名称匹配：预先把候选名称展开成键，避免在循环里反复做正则归一化
function Get-ShowNameKeys {
    param([string]$Title, [string]$TitleJp)
    $keys = New-Object System.Collections.ArrayList
    foreach ($n in @($Title, $TitleJp)) {
        if ([string]::IsNullOrWhiteSpace($n)) { continue }
        foreach ($k in (Get-NameKeys $n)) { if ($k -and -not $keys.Contains($k)) { [void]$keys.Add($k) } }
    }
    return $keys.ToArray()
}

function Get-KeyOverlapScore {
    param([string[]]$KeysA, [string[]]$KeysB)
    $best = 0
    foreach ($a in @($KeysA)) {
        if ([string]::IsNullOrEmpty($a)) { continue }
        foreach ($b in @($KeysB)) {
            if ([string]::IsNullOrEmpty($b)) { continue }
            if ($a -eq $b) { return 100 }
            if ($a.Length -ge 5 -and $b.Length -ge 5 -and ($a.Contains($b) -or $b.Contains($a))) {
                $ratio = [math]::Min($a.Length, $b.Length) / [math]::Max($a.Length, $b.Length)
                $score = [int](60 + 30 * $ratio)
                if ($score -gt $best) { $best = $score }
            }
        }
    }
    return $best
}

function Find-BestMatch {
    param([string]$YucTitle, [string]$YucTitleJp, $CalIndex)
    if (-not $CalIndex) { return [pscustomobject]@{ item = $null; score = 0 } }
    $keys = @(Get-ShowNameKeys -Title $YucTitle -TitleJp $YucTitleJp)
    foreach ($k in $keys) {
        if ($CalIndex.index.ContainsKey($k)) { return [pscustomobject]@{ item = $CalIndex.index[$k]; score = 100 } }
    }
    $best = $null; $bestScore = 0
    foreach ($e in @($CalIndex.entries)) {
        $s = Get-KeyOverlapScore -KeysA $keys -KeysB $e.keys
        if ($s -gt $bestScore) { $bestScore = $s; $best = $e.item }
        if ($bestScore -eq 100) { break }
    }
    if ($bestScore -ge 70) { return [pscustomobject]@{ item = $best; score = $bestScore } }
    return [pscustomobject]@{ item = $null; score = 0 }
}
# ---------- 构建当日数据 ----------
function Build-WidgetData {
    param(
        $Config,
        [switch]$Force,
        [scriptblock]$Progress
    )
    $report = {
        param($msg)
        if ($Progress) { & $Progress $msg }
        Write-Log $msg 'INFO'
    }

    $warnings = New-Object System.Collections.ArrayList
    $today = Get-Date
    $todayDate = (Get-Date -Year $today.Year -Month $today.Month -Day $today.Day -Hour 0 -Minute 0 -Second 0)

    # ---- 1. yuc.wiki 新番表（当季 + 即将开播季）----
    $entries = New-Object System.Collections.ArrayList
    $seasonInfo = @()
    if ((Get-Prop $Config.data 'useYuc' $true)) {
        $keys = @(Get-YucSeasonsToLoad -Config $Config -Today $today)
        [void](& $report ("读取 yuc.wiki 新番表：{0}" -f ($keys -join ', ')))
        foreach ($key in $keys) {
            $page = Get-YucSeasonPage -SeasonKey $key -Config $Config -Force:$Force -MaxAgeMinutes 360
            if (-not $page.ok) {
                [void]$warnings.Add("yuc.wiki $key 抓取失败：$($page.error)")
                continue
            }
            $parsed = ConvertFrom-YucSeasonPage -Html $page.html -SeasonKey $key
            $joined = Join-YucSeasonData -Parsed $parsed
            foreach ($e in $joined) { [void]$entries.Add($e) }
            $seasonInfo += [pscustomobject]@{ key = $key; label = $parsed.seasonLabel; title = $parsed.title; count = $parsed.newCount; url = $page.url }
        }
    }

    # ---- 2. Bangumi 日历（判断“是否仍在放送” + 取评分/条目 ID）----
    $calIndex = @{}
    $calOk = $false
    $calMap = @{}     # normName -> item
    if ((Get-Prop $Config.data 'useBangumi' $true)) {
        [void](& $report '读取 Bangumi 每日放送日历……')
        $cal = Get-BangumiCalendar -Config $Config -Force:$Force -MaxAgeMinutes 360
        if ($cal.ok) {
            $calOk = $true
            $built = Get-BangumiCalendarIndex -Days $cal.days
            $calMap = $built
        } else {
            [void]$warnings.Add("Bangumi 日历抓取失败：$($cal.error)")
        }
    }

    # ---- 3. 合并 ----
    [void](& $report '合并新番数据……')
    $shows = New-Object System.Collections.ArrayList
    $seen = @{}
    foreach ($e in $entries) {
        $timeInfo = ConvertFrom-JstTime -TimeJst $e.timeJst -Weekday $e.weekday
        $match = $null
        if ($calOk) { $match = Find-BestMatch -YucTitle $e.title -YucTitleJp $e.titleJp -CalIndex $calMap }

        $bgmId = 0; $score = 0; $bgmName = ''; $cover = $e.cover
        $isAiring = $false
        if ($match.item) {
            $bgmId = [int]$match.item.id
            if ($match.item.rating -and $match.item.rating.score) { $score = [double]$match.item.rating.score }
            $bgmName = [string]$match.item.name_cn
            if (-not $cover -and $match.item.images) { $cover = [string]$match.item.images.large }
            $isAiring = $true
        }

        $dedupeKey = ConvertTo-NormName $e.title
        if (-not $dedupeKey) { $dedupeKey = $e.title }
        if ($seen.ContainsKey($dedupeKey)) { continue }
        $seen[$dedupeKey] = $true

        $firstAir = $e.firstAir
        $firstAirLocal = $null
        if ($firstAir) { $firstAirLocal = $firstAir.AddDays($timeInfo.dayOffset) }
        elseif ($match.item -and $match.item.air_date) {
            try { $firstAirLocal = [datetime]::Parse([string]$match.item.air_date) } catch { }
            $firstAir = $firstAirLocal
        }

        [void]$shows.Add([pscustomobject]@{
                bgmId         = $bgmId
                bgmName       = $bgmName
                title         = $e.title
                titleJp       = $e.titleJp
                seasonKey     = $e.seasonKey
                weekday       = $e.weekday
                localWeekday  = $timeInfo.localWeekday
                timeJst       = $e.timeJst
                timeLocal     = $timeInfo.timeLocal
                dayOffset     = $timeInfo.dayOffset
                firstAir      = $(if ($firstAir) { $firstAir.ToString('yyyy-MM-dd') } else { '' })
                firstAirLocal = $(if ($firstAirLocal) { $firstAirLocal.ToString('yyyy-MM-dd') } else { '' })
                isAiring      = $isAiring
                isStreaming   = [bool]$e.isStreaming
                streamNote    = $e.streamNote
                epNote        = $e.epNote
                cover         = $cover
                tags          = @($e.tags)
                type          = $e.type
                regions       = @($e.regions)
                platforms     = @($e.platforms)
                staff         = $e.staff
                cast          = $e.cast
                site          = $e.site
                score         = $score
                station       = ''
                studio        = ''
                source        = 'yuc'
                followed      = $false
            })
    }

    # ---- 4. 为缺少 Bangumi 条目的新番解析 ID 并补充详情（评分/电视台/标签）----
    $resolved = 0
    if ((Get-Prop $Config.data 'resolveBangumiIds' $true) -and (Get-Prop $Config.data 'useBangumi' $true)) {
        $limit = [int](Get-Prop $Config.data 'maxResolvePerRefresh' 40)
        $targets = @($shows | Where-Object { $_.bgmId -eq 0 -and -not $_.isStreaming })
        # 优先解析最近会播出的
        $targets = @($targets | Sort-Object { $_.localWeekday })
        foreach ($s in $targets) {
            if ($resolved -ge $limit) { break }
            $kw = $(if ($s.titleJp) { $s.titleJp } else { $s.title })
            $hit = Find-BangumiSubjectId -Keyword $kw -Config $Config -Force:$Force
            if (-not $hit -and $s.titleJp) { $hit = Find-BangumiSubjectId -Keyword $s.title -Config $Config -Force:$Force }
            $resolved++
            Start-Sleep -Milliseconds 120      # 对 Bangumi API 保持礼貌
            if ($hit) {
                $s.bgmId = [int]$hit.id
                if ($hit.rating -and $hit.rating.score) { $s.score = [double]$hit.rating.score }
            }
        }
        if ($targets.Count -gt 0) { [void](& $report ("解析 Bangumi 条目：{0}/{1}" -f [math]::Min($resolved, $limit), $targets.Count)) }
    }

    # ---- 5. 取条目详情补充「播放电视台 / 标签」----
    $detailBudget = [int](Get-Prop $Config.data 'maxResolvePerRefresh' 40)
    $detailUsed = 0
    foreach ($s in $shows) {
        if ($s.bgmId -le 0) { continue }
        if ($s.station -and $s.tags.Count -ge 1 -and $s.score -gt 0) { continue }
        if ($detailUsed -ge $detailBudget) { break }
        $det = Get-BangumiSubject -Id $s.bgmId -Config $Config -Force:$Force -MaxAgeMinutes 1440
        $detailUsed++
        Start-Sleep -Milliseconds 120
        if ($det.ok -and $det.data) {
            $info = ConvertFrom-BangumiSubject -Subject $det.data -TagCount 3
            if ($info) {
                if (-not $s.station) { $s.station = $info.station }
                if (-not $s.studio) { $s.studio = $info.studio }
                if ($s.score -le 0) { $s.score = $info.score }
                if (-not $s.titleJp) { $s.titleJp = $info.name }
                if (-not $s.cover -and $info.image) { $s.cover = $info.image }
                if (@($info.tags).Count -gt 0) {
                    $merged = New-Object System.Collections.ArrayList
                    $seenTag = @{}
                    foreach ($t in @($s.tags) + @($info.tags)) {
                        if ([string]::IsNullOrWhiteSpace($t)) { continue }
                        $key = (ConvertTo-NormName $t)
                        if (-not $key) { $key = [string]$t }
                        if ($seenTag.ContainsKey($key)) { continue }
                        $seenTag[$key] = $true
                        [void]$merged.Add([string]$t)
                        if ($merged.Count -ge 5) { break }
                    }
                    $s.tags = $merged.ToArray()
                }
                if ($info.startDate -and -not $s.firstAir) { $s.firstAir = $info.startDate }
            }
        }
    }

    # ---- 6. 在追（Bangumi 在看）----
    $followedCount = 0
    $followedUser = ''
    $followed = Get-FollowedInfo -Config $Config -Shows $shows -Force:$Force -Warnings $warnings
    if ($followed.ok) {
        $followedUser = $followed.username
        $followedCount = $followed.count
    }

    # ---- 7. 过滤（只保留新番；剔除已完结）----
    $dropAfter = [int](Get-Prop $Config.data 'dropEndedAfterDays' 14)
    $keep = New-Object System.Collections.ArrayList
    foreach ($s in $shows) {
        if ($s.isStreaming -and -not (Get-Prop $Config.data 'showStreaming' $true)) { continue }
        if ($s.isStreaming) { [void]$keep.Add($s); continue }
        $keepIt = $false
        if ($s.isAiring) { $keepIt = $true }
        elseif ($s.firstAirLocal) {
            $fa = $null
            try { $fa = [datetime]::Parse($s.firstAirLocal) } catch { }
            if ($fa) {
                if ($fa -ge $todayDate.AddDays(-$dropAfter)) { $keepIt = $true }
            } else { $keepIt = $true }
        } else {
            $keepIt = $true     # 无法判断时保留，宁可多显示
        }
        if ($keepIt) { [void]$keep.Add($s) }
    }

    $state = [pscustomobject]@{
        version      = 1
        builtAt      = (Get-Date).ToString('o')
        today        = $todayDate.ToString('yyyy-MM-dd')
        seasons      = @($seasonInfo)
        shows        = $keep.ToArray()
        warnings     = $warnings.ToArray()
        followedUser = $followedUser
        followedCount= $followedCount
        calendarOk   = $calOk
        sourceCount  = $entries.Count
    }
    Save-WidgetState $state | Out-Null
    [void](& $report ("完成：{0} 部新番（在追 {1} 部）" -f @($state.shows).Count, $followedCount))
    return $state
}

# ---------- 在追信息 ----------
function Get-FollowedInfo {
    param($Config, $Shows, [switch]$Force, $Warnings)
    $auth = Get-BangumiAuth
    $token = ''
    $username = ''
    if ($auth.accessToken) {
        $auth = Update-BangumiAuthToken -Config $Config
        $token = [string]$auth.accessToken
        $username = [string]$auth.username
    }
    if (-not $token -and (Get-Prop $Config.bangumi 'usePublicCollections' $false)) {
        $username = [string](Get-Prop $Config.bangumi 'username' '')
    }
    if (-not $token -and -not $username) {
        return [pscustomobject]@{ ok = $false; count = 0; username = ''; error = '未登录 Bangumi' }
    }

    $col = Get-BangumiCollections -Username $username -Token $token -Type 3 -Config $Config -Force:$Force -MaxAgeMinutes 180
    if (-not $col.ok) {
        if ($Warnings) { [void]$Warnings.Add("读取在看收藏失败：$($col.error)") }
        return [pscustomobject]@{ ok = $false; count = 0; username = $username; error = $col.error }
    }

    $idSet = @{}
    $nameSet = @{}
    foreach ($it in @($col.items)) {
        $sid = [int](Get-Prop $it 'subject_id' 0)
        if ($sid -gt 0) { $idSet[$sid] = $true }
        $subj = Get-Prop $it 'subject'
        if ($subj) {
            foreach ($n in @([string](Get-Prop $subj 'name_cn' ''), [string](Get-Prop $subj 'name' ''))) {
                foreach ($k in (Get-NameKeys $n)) { if ($k -and -not $nameSet.ContainsKey($k)) { $nameSet[$k] = $true } }
            }
        }
    }

    $count = 0
    foreach ($s in @($Shows)) {
        $hit = $false
        if ($s.bgmId -gt 0 -and $idSet.ContainsKey([int]$s.bgmId)) { $hit = $true }
        else {
            foreach ($k in @(Get-NameKeys $s.title) + @(Get-NameKeys $s.titleJp)) {
                if ($k -and $nameSet.ContainsKey($k)) { $hit = $true; break }
                foreach ($nk in $nameSet.Keys) {
                    if ($k.Length -ge 5 -and $nk.Length -ge 5 -and ($k.Contains($nk) -or $nk.Contains($k))) { $hit = $true; break }
                }
                if ($hit) { break }
            }
        }
        $s.followed = $hit
        if ($hit) { $count++ }
    }
    return [pscustomobject]@{ ok = $true; count = $count; username = $username; error = $null }
}

# ---------- 查询辅助 ----------
function Get-ShowsByDay {
    param($Shows, [int]$LocalWeekday)
    return @($Shows | Where-Object { -not $_.isStreaming -and $_.localWeekday -eq $LocalWeekday } | Sort-Object { $_.timeLocal })
}

function Get-StreamingShows {
    param($Shows)
    return @($Shows | Where-Object { $_.isStreaming })
}

# 下一部即将播出的新番
function Get-NextShow {
    param($Shows, [datetime]$Now = (Get-Date))
    $nowWd = Get-WeekdayIndex $Now
    $nowMin = $Now.Hour * 60 + $Now.Minute
    $best = $null; $bestDelta = [int]::MaxValue
    foreach ($s in @($Shows)) {
        if ($s.isStreaming) { continue }
        if ([string]::IsNullOrWhiteSpace($s.timeLocal)) { continue }
        if ($s.localWeekday -lt 0) { continue }
        $hm = [regex]::Match($s.timeLocal, '^(\d{1,2}):(\d{2})')
        if (-not $hm.Success) { continue }
        $min = [int]$hm.Groups[1].Value * 60 + [int]$hm.Groups[2].Value
        $delta = (($s.localWeekday - $nowWd) * 1440) + ($min - $nowMin)
        while ($delta -lt 0) { $delta += 7 * 1440 }
        if ($delta -lt $bestDelta) { $bestDelta = $delta; $best = $s }
    }
    if (-not $best) { return $null }
    return [pscustomobject]@{ show = $best; minutes = [int]$bestDelta }
}

function Test-NeedRefresh {
    param($State, $Config, [datetime]$Now = (Get-Date))
    if (-not $State) { return $true }
    if (-not $State.builtAt) { return $true }
    try { $built = [datetime]$State.builtAt } catch { return $true }
    if ($State.today -ne (Get-Date -Year $Now.Year -Month $Now.Month -Day $Now.Day).ToString('yyyy-MM-dd')) { return $true }
    $hours = [double](Get-Prop $Config.data 'refreshHours' 6)
    if (($Now - $built).TotalHours -ge $hours) { return $true }
    return $false
}

function Get-DailyRefreshTime {
    param($Config, [datetime]$Now = (Get-Date))
    $text = [string](Get-Prop $Config.data 'dailyRefreshAt' '04:10')
    $m = [regex]::Match($text, '^(\d{1,2}):(\d{2})$')
    if (-not $m.Success) { return $Now.Date.AddHours(4).AddMinutes(10) }
    return $Now.Date.AddHours([int]$m.Groups[1].Value).AddMinutes([int]$m.Groups[2].Value)
}
