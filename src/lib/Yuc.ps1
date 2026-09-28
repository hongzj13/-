# Yuc.ps1 -- 長門番堂 (yuc.wiki) 新番表解析
# 页面结构（2020~2026 各季一致）：
#   日表头      <td class="date2">周一 (月)</td>
#   单部条目    <div class="div_date"><p class="imgtext4">21:00~</p><p class="imgep2">10/5~</p><img data-src="封面"></div>
#               <table><tr><td class="date_title_">名称</td></tr><tr class="tr_area"><p class="area">港台</p>...</tr></table>
#   网络放送    <div class="div_date_">…<p class="pmfs">10/20网络放送</p>…<p class="paomian">(全10话)</p>
#   底部详情    <!--#A01--> … <p class="title_cn_r"> / <p class="title_jp_r"> / class="type_a_r" / class="type_tag_r"
#               class="staff_r" / class="cast_r" / class="link_a_r" + <p class="broadcast_r">
# 目标运行时：Windows PowerShell 5.1

$script:PlatformHostMap = @(
    @{ pattern = 'gamer\.com\.tw';            name = '巴哈姆特動畫瘋'; region = '港台' },
    @{ pattern = 'ani\.gamer\.com\.tw';       name = '巴哈姆特動畫瘋'; region = '港台' },
    @{ pattern = 'crunchyroll\.com';          name = 'Crunchyroll';    region = '环大陆' },
    @{ pattern = 'netflix\.com';              name = 'Netflix';        region = '环大陆' },
    @{ pattern = 'disneyplus\.com';           name = 'Disney+';        region = '环大陆' },
    @{ pattern = 'primevideo\.com';           name = 'Prime Video';    region = '环大陆' },
    @{ pattern = 'hbomax\.com|max\.com';      name = 'HBO Max';        region = '环大陆' },
    @{ pattern = 'hulu\.com';                 name = 'Hulu';           region = '环大陆' },
    @{ pattern = 'hidive\.com';               name = 'HIDIVE';         region = '环大陆' },
    @{ pattern = 'bilibili\.com';             name = 'bilibili';       region = '内地' },
    @{ pattern = 'iqiyi\.com';                name = '爱奇艺';          region = '内地' },
    @{ pattern = 'v\.qq\.com';                name = '腾讯视频';        region = '内地' },
    @{ pattern = 'youku\.com';                name = '优酷';            region = '内地' },
    @{ pattern = 'mgtv\.com';                 name = '芒果TV';          region = '内地' },
    @{ pattern = 'wetv\.vip';                 name = 'WeTV';           region = '东南亚' },
    @{ pattern = 'muse\.';                    name = 'Muse木棉花';      region = '港台' },
    @{ pattern = 'kktv\.';                    name = 'KKTV';           region = '台湾' },
    @{ pattern = 'litv\.';                    name = 'LiTV';           region = '台湾' },
    @{ pattern = 'friday\.tw';                name = 'friDay影音';      region = '台湾' },
    @{ pattern = 'catchplay\.com';            name = 'CATCHPLAY+';     region = '台湾' },
    @{ pattern = 'myvideo\.';                 name = 'myVideo';        region = '台湾' },
    @{ pattern = 'viu\.com';                  name = 'Viu';            region = '香港' },
    @{ pattern = 'now\.com|nowe\.com';        name = 'Now E';          region = '香港' }
)

function Get-PlatformInfo {
    param([string]$Url, [string]$Label)
    $host_ = ''
    try { $host_ = ([uri]$Url).Host } catch { $host_ = $Url }
    foreach ($m in $script:PlatformHostMap) {
        if ($host_ -match $m.pattern) {
            return [pscustomobject]@{ name = $m.name; region = $(if ($Label) { $Label } else { $m.region }); url = $Url }
        }
    }
    if ($host_) {
        $short = $host_ -replace '^(www|ani|acg|m)\.', ''
        return [pscustomobject]@{ name = $short; region = $Label; url = $Url }
    }
    return [pscustomobject]@{ name = $Label; region = $Label; url = $Url }
}

function Get-YucSeasonKey {
    param([datetime]$Date = (Get-Date))
    return (Get-SeasonInfo -Date $Date).Key
}

function Get-YucSeasonsToLoad {
    param($Config, [datetime]$Today = (Get-Date))
    $keys = New-Object System.Collections.ArrayList
    $si = Get-SeasonInfo -Date $Today
    [void]$keys.Add($si.Key)
    $lookahead = 21
    $cfgData = Get-Prop $Config 'data'
    if ($cfgData) { $lookahead = [int](Get-Prop $cfgData 'lookaheadDays' 21) }
    $daysToNext = ($si.NextStart - $Today).TotalDays
    if ($daysToNext -le $lookahead) {
        $nextSi = Get-SeasonInfo -Date $si.NextStart
        if (-not $keys.Contains($nextSi.Key)) { [void]$keys.Add($nextSi.Key) }
    }
    return $keys
}

function Get-YucSeasonPage {
    param(
        [Parameter(Mandatory = $true)][string]$SeasonKey,
        $Config,
        [switch]$Force,
        [int]$MaxAgeMinutes = 360
    )
    $base = 'https://yuc.wiki'
    $cfgData = Get-Prop $Config 'data'
    if ($cfgData) { $base = [string](Get-Prop $cfgData 'yucBaseUrl' 'https://yuc.wiki') }
    $url = $base.TrimEnd('/') + '/' + $SeasonKey + '/'
    $r = Get-CachedText -Url $url -MaxAgeMinutes $MaxAgeMinutes -Force:$Force -Network (Get-Prop $Config 'network') -CacheKey ('yuc:' + $SeasonKey)
    if (-not $r.ok) {
        return [pscustomobject]@{ ok = $false; seasonKey = $SeasonKey; url = $url; html = ''; error = $r.error; fetchedAt = $null }
    }
    return [pscustomobject]@{ ok = $true; seasonKey = $SeasonKey; url = $url; html = $r.text; error = $null; fetchedAt = $r.fetchedAt; fromCache = $r.fromCache }
}

function Resolve-YucAirDate {
    param([string]$DayText, [int]$SeasonYear, [int]$SeasonStartMonth)
    if ($DayText -notmatch '(\d{1,2})\s*/\s*(\d{1,2})') { return $null }
    $mm = [int]$Matches[1]; $dd = [int]$Matches[2]
    $yy = $SeasonYear
    if (($mm - $SeasonStartMonth) -gt 6) { $yy = $SeasonYear - 1 }
    elseif (($SeasonStartMonth - $mm) -gt 6) { $yy = $SeasonYear + 1 }
    try { return (Get-Date -Year $yy -Month $mm -Day $dd -Hour 0 -Minute 0 -Second 0) } catch { return $null }
}

function ConvertFrom-YucSeasonPage {
    param(
        [Parameter(Mandatory = $true)][string]$Html,
        [string]$SeasonKey = ''
    )
    $year = 0; $startMonth = 1
    if ($SeasonKey -match '^(\d{4})(\d{2})$') { $year = [int]$Matches[1]; $startMonth = [int]$Matches[2] }

    $schedule = New-Object System.Collections.ArrayList
    $details = New-Object System.Collections.ArrayList
    $title = ''; $seasonLabel = ''; $newCount = 0

    if ([string]::IsNullOrWhiteSpace($Html)) {
        return [pscustomobject]@{ ok = $false; schedule = @(); details = @(); title = ''; seasonLabel = ''; newCount = 0 }
    }

    $m = [regex]::Match($Html, '(?s)<h1 class="post-title"[^>]*>(.*?)</h1>')
    if ($m.Success) { $title = ConvertFrom-HtmlText $m.Groups[1].Value }

    $m = [regex]::Match($Html, '(?s)本期(.{0,120}?)共收录(.{0,240}?)部新番动画')
    if ($m.Success) {
        $seasonLabel = ConvertFrom-HtmlText $m.Groups[1].Value
        $cntText = ConvertFrom-HtmlText $m.Groups[2].Value
        $mc = [regex]::Match($cntText, '(\d+)')
        if ($mc.Success) { $newCount = [int]$mc.Groups[1].Value }
    }

    # ---- 日表 -> 分块 ----
    $dayRegex = [regex]'(?s)<td class="date2">(.*?)</td>'
    $dayMatches = $dayRegex.Matches($Html)
    $scheduleEnd = $Html.Length
    $sumIdx = $Html.IndexOf('本期')
    if ($sumIdx -gt 0) { $scheduleEnd = $sumIdx }

    for ($d = 0; $d -lt $dayMatches.Count; $d++) {
        $headText = ConvertFrom-HtmlText $dayMatches[$d].Groups[1].Value
        $start = $dayMatches[$d].Index + $dayMatches[$d].Length
        $stop = $scheduleEnd
        if ($d + 1 -lt $dayMatches.Count) { $stop = $dayMatches[$d + 1].Index }
        if ($stop -gt $scheduleEnd) { $stop = $scheduleEnd }
        if ($stop -le $start) { continue }
        $region = $Html.Substring($start, $stop - $start)

        $weekday = -1
        $isStreaming = $false
        $mk = [regex]::Match($headText, '[（(]([月火水木金土日])[）)]')
        if ($mk.Success) {
            $weekday = @('月', '火', '水', '木', '金', '土', '日').IndexOf($mk.Groups[1].Value)
        } elseif ($headText -match '网络放送|其他') {
            $isStreaming = $true
        } elseif ($headText -match '周([一二三四五六日])') {
            $weekday = @('一', '二', '三', '四', '五', '六', '日').IndexOf($Matches[1])
        }

        foreach ($b in [regex]::Matches($region, '(?s)<div style="float:left">\s*<div class="(div_date_?)"[^>]*>(?<head>.*?)</div>\s*<div>\s*<table[^>]*>(?<body>.*?)</table>')) {
            $bHead = $b.Groups['head'].Value
            $bBody = $b.Groups['body'].Value

            # 时间：新番用 imgtext4；往季/在播页部分条目用 imgtext5
            $timeJst = ''
            $mt = [regex]::Match($bHead, '<p class="imgtext\d*">([^<]*)</p>')
            if ($mt.Success) { $timeJst = ($mt.Groups[1].Value -replace '[~\s]', '') }

            # 日期格：未开播季为 "10/5~"；在播季改为 "(全12话)" 这类话数信息
            $dayText = ''
            $dayCell = ''
            $md = [regex]::Match($bHead, '<p class="imgep\d*">([^<]*)</p>')
            if ($md.Success) {
                $dayCell = ($md.Groups[1].Value -replace '[~\s]', '')
                if ($dayCell -match '^\d{1,2}/\d{1,2}$') { $dayText = $dayCell }
            }

            $cover = ''
            $mcv = [regex]::Match($bHead, 'data-src="([^"]+)"')
            if ($mcv.Success) { $cover = $mcv.Groups[1].Value }

            $name = ''
            $mn = [regex]::Match($bBody, '(?s)<td[^>]*class="date_title_+"[^>]*>(.*?)</td>')
            if ($mn.Success) { $name = ConvertFrom-HtmlText $mn.Groups[1].Value }
            if ([string]::IsNullOrWhiteSpace($name)) { continue }

            $labels = New-Object System.Collections.ArrayList
            $platforms = New-Object System.Collections.ArrayList
            $streamNote = ''
            $epNote = ''

            foreach ($ma in [regex]::Matches($bBody, '(?s)<p class="area">([^<]*)</p>')) {
                $lab = ConvertFrom-HtmlText $ma.Groups[1].Value
                if ($lab -and -not $labels.Contains($lab)) { [void]$labels.Add($lab) }
            }
            # 逐个版权单元格解析：href + 紧随其后的地区标签
            foreach ($cell in [regex]::Matches($bBody, '(?s)<td[^>]*>(?<cell>.*?)</td>')) {
                $cellHtml = $cell.Groups['cell'].Value
                $mh = [regex]::Match($cellHtml, 'href="([^"]+)"')
                if (-not $mh.Success) { continue }
                $url = $mh.Groups[1].Value
                if ($url -match '^(#|javascript)') { continue }
                $label = ''
                $ml = [regex]::Match($cellHtml, '<p class="area">([^<]*)</p>')
                if ($ml.Success) { $label = ConvertFrom-HtmlText $ml.Groups[1].Value }
                $pi = Get-PlatformInfo -Url $url -Label $label
                if (-not ($platforms | Where-Object { $_.url -eq $url })) { [void]$platforms.Add($pi) }
            }
            $ms = [regex]::Match($bBody, '(?s)<p class="pmfs2?">(.*?)</p>')
            if ($ms.Success) { $streamNote = ConvertFrom-HtmlText $ms.Groups[1].Value }
            $mp = [regex]::Match($bBody, '(?s)<p class="(pmex|paomian)">(.*?)</p>')
            if ($mp.Success) { $epNote = ConvertFrom-HtmlText $mp.Groups[2].Value }
            if (-not $epNote -and $dayCell -match '^[（(].*[）)]$') { $epNote = $dayCell }

            $firstAir = $null
            if ($dayText) { $firstAir = Resolve-YucAirDate -DayText $dayText -SeasonYear $year -SeasonStartMonth $startMonth }
            if (-not $firstAir -and $streamNote) { $firstAir = Resolve-YucAirDate -DayText $streamNote -SeasonYear $year -SeasonStartMonth $startMonth }

            [void]$schedule.Add([pscustomobject]@{
                    seasonKey   = $SeasonKey
                    title       = $name
                    weekday     = $weekday          # 0=周一 … 6=周日, -1=未知
                    timeJst     = $timeJst          # '21:00' / ''
                    dayText     = $dayText
                    firstAir    = $firstAir
                    cover       = $cover
                    regionLabels= @($labels)
                    platforms   = @($platforms)
                    isStreaming = [bool]$isStreaming
                    streamNote  = $streamNote
                    epNote      = $epNote
                })
        }
    }

    # ---- 底部详情 ----
    $chunks = @()
    $dsm = [regex]::Match($Html, '<p class="title_cn_r\d*">')
    $detailStart = $dsm.Index
    if ($detailStart -gt 0) {
        # 不依赖 <!--#A01--> 标记：页面前 6 条带该标记，其余没有，故按 title_cn_r 切块
        $chunks = [regex]::Split($Html.Substring($detailStart), '(?=<p class="title_cn_r\d*">)')
    }
    for ($i = 0; $i -lt $chunks.Count; $i++) {
        $c = $chunks[$i]
        $mcn = [regex]::Match($c, '(?s)<p class="title_cn_r\d*">(.*?)</p>')
        if (-not $mcn.Success) { continue }
        $titleCn = ConvertFrom-HtmlText $mcn.Groups[1].Value
        if ([string]::IsNullOrWhiteSpace($titleCn)) { continue }
        $mjp = [regex]::Match($c, '(?s)<p class="title_jp_r\d*">(.*?)</p>')
        $mtype = [regex]::Match($c, '(?s)<td class="type_[a-z]_r\d*">(.*?)</td>')
        $mtag = [regex]::Match($c, '(?s)<td class="type_tag_r\d*">(.*?)</td>')
        $mstaff = [regex]::Match($c, '(?s)<td rowspan="2" class="staff_r\d*">(.*?)</td>')
        $mcast = [regex]::Match($c, '(?s)<td rowspan="2" class="cast_r\d*">(.*?)</td>')
        $mbc = [regex]::Match($c, '(?s)<p class="broadcast_r\d*">(.*?)</p>')

        $tags = @()
        if ($mtag.Success) {
            $tags = @((ConvertFrom-HtmlText $mtag.Groups[1].Value) -split '[/／\s]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        }
        $site = ''; $pv = ''
        foreach ($a in [regex]::Matches($c, '(?s)<a href="([^"]+)"[^>]*>(.*?)</a>')) {
            $txt = ConvertFrom-HtmlText $a.Groups[2].Value
            if ($txt -match '官网') { $site = $a.Groups[1].Value }
            elseif ($txt -match 'PV|预告') { $pv = $a.Groups[1].Value }
        }

        [void]$details.Add([pscustomobject]@{
                titleCn   = $titleCn
                titleJp   = $(if ($mjp.Success) { ConvertFrom-HtmlText $mjp.Groups[1].Value } else { '' })
                type      = $(if ($mtype.Success) { ConvertFrom-HtmlText $mtype.Groups[1].Value } else { '' })
                tags      = $tags
                staff     = $(if ($mstaff.Success) { ConvertFrom-HtmlText $mstaff.Groups[1].Value -Separator "`n" -Lines } else { '' })
                cast      = $(if ($mcast.Success) { ConvertFrom-HtmlText $mcast.Groups[1].Value -Separator "`n" -Lines } else { '' })
                site      = $site
                pv        = $pv
                broadcast = $(if ($mbc.Success) { ConvertFrom-HtmlText $mbc.Groups[1].Value } else { '' })
                seasonKey = $SeasonKey
            })
    }

    return [pscustomobject]@{
        ok          = $true
        seasonKey   = $SeasonKey
        seasonYear  = $year
        title       = $title
        seasonLabel = $seasonLabel
        newCount    = $newCount
        schedule    = @($schedule)
        details     = @($details)
    }
}

# 把一季的日表与详情合并成条目列表
function Join-YucSeasonData {
    param($Parsed)
    $out = New-Object System.Collections.ArrayList
    if (-not $Parsed -or -not $Parsed.ok) { return $out }
    $detailIndex = @{}
    foreach ($d in $Parsed.details) {
        $key = ConvertTo-NormName $d.titleCn
        if ($key -and -not $detailIndex.ContainsKey($key)) { $detailIndex[$key] = $d }
    }
    foreach ($s in $Parsed.schedule) {
        $key = ConvertTo-NormName $s.title
        $det = $null
        if ($key -and $detailIndex.ContainsKey($key)) { $det = $detailIndex[$key] }
        else {
            # 详情名可能带 副标题 / 别名，尝试互相包含
            foreach ($k in $detailIndex.Keys) {
                if ($k.Length -ge 4 -and $key.Length -ge 4 -and ($k.Contains($key) -or $key.Contains($k))) { $det = $detailIndex[$k]; break }
            }
        }
        [void]$out.Add([pscustomobject]@{
                title      = $s.title
                titleJp    = $(if ($det) { $det.titleJp } else { '' })
                seasonKey  = $s.seasonKey
                weekday    = $s.weekday
                timeJst    = $s.timeJst
                firstAir   = $s.firstAir
                dayText    = $s.dayText
                cover      = $(if ($s.cover) { $s.cover } else { '' })
                tags       = $(if ($det) { @($det.tags) } else { @() })
                type       = $(if ($det) { $det.type } else { '' })
                staff      = $(if ($det) { $det.staff } else { '' })
                cast       = $(if ($det) { $det.cast } else { '' })
                site       = $(if ($det) { $det.site } else { '' })
                pv         = $(if ($det) { $det.pv } else { '' })
                broadcast  = $(if ($det) { $det.broadcast } else { '' })
                regions    = @($s.regionLabels)
                platforms  = @($s.platforms)
                isStreaming= $s.isStreaming
                streamNote = $s.streamNote
                epNote     = $s.epNote
            })
    }
    return $out
}
