# Bangumi.ps1 -- Bangumi (bgm.tv) API 客户端
#  日历      GET  https://api.bgm.tv/calendar
#  条目详情  GET  https://api.bgm.tv/v0/subjects/{id}
#  条目搜索  POST https://api.bgm.tv/v0/search/subjects
#  我的收藏  GET  https://api.bgm.tv/v0/users/-/collections      (需 Token)
#  公开收藏  GET  https://api.bgm.tv/v0/users/{user}/collections (公开)
#  当前用户  GET  https://api.bgm.tv/v0/users/-                  (需 Token)
#  加入在看  POST https://api.bgm.tv/v0/users/-/collections/{id}
#  OAuth     https://bgm.tv/oauth/authorize  +  https://bgm.tv/oauth/access_token
# 目标运行时：Windows PowerShell 5.1

$script:BgmApi = 'https://api.bgm.tv'
$script:BgmOauth = 'https://bgm.tv/oauth'

function Get-BangumiHeaders {
    param($Config, [string]$Token = '', [switch]$Json)
    $ua = 'anime-widget/1.0 (personal desktop widget)'
    $cfgNet = Get-Prop $Config 'network'
    if ($cfgNet) { $ua = [string](Get-Prop $cfgNet 'userAgent' $ua) }
    $h = @{ 'User-Agent' = $ua; 'Accept' = 'application/json' }
    if ($Json) { $h['Content-Type'] = 'application/json' }
    if ($Token) { $h['Authorization'] = 'Bearer ' + $Token }
    return $h
}

# ---------- 每日放送日历 ----------
function Get-BangumiCalendar {
    param($Config, [switch]$Force, [int]$MaxAgeMinutes = 360)
    $url = $script:BgmApi + '/calendar'
    $r = Get-JsonCached -Url $url -MaxAgeMinutes $MaxAgeMinutes -Force:$Force -Headers (Get-BangumiHeaders $Config) `
        -Network (Get-Prop $Config 'network') -CacheKey 'bgm:calendar'
    if (-not $r.ok) { return [pscustomobject]@{ ok = $false; days = @(); error = $r.error } }
    return [pscustomobject]@{ ok = $true; days = @($r.data); error = $null; fetchedAt = $r.fetchedAt; fromCache = $r.fromCache }
}

# 把日历整理成 { normName -> 条目 } 索引，便于名称匹配
function Get-BangumiCalendarIndex {
    param($Days)
    $index = @{}
    $entries = New-Object System.Collections.ArrayList
    $all = New-Object System.Collections.ArrayList
    foreach ($d in @($Days)) {
        foreach ($it in @($d.items)) {
            [void]$all.Add($it)
            $keys = New-Object System.Collections.ArrayList
            foreach ($n in @([string]$it.name_cn, [string]$it.name)) {
                if ([string]::IsNullOrWhiteSpace($n)) { continue }
                foreach ($k in (Get-NameKeys $n)) {
                    if (-not $k) { continue }
                    if (-not $keys.Contains($k)) { [void]$keys.Add($k) }
                    if (-not $index.ContainsKey($k)) { $index[$k] = $it }
                }
            }
            [void]$entries.Add([pscustomobject]@{ item = $it; keys = $keys.ToArray() })
        }
    }
    return [pscustomobject]@{ index = $index; entries = $entries.ToArray(); items = $all.ToArray() }
}
# ---------- 条目详情 ----------
$script:BgmTagStop = @(
    'TV', 'WEB', 'OVA', 'OAD', '剧场版', '日本', '中国', '国产', '动画', '漫画改', '小说改', '游戏改',
    '原创', '续作', '2026', '2025', '2024', '2023', '2022', '2021', '2020', '2026年7月', '2026年10月',
    '2026年4月', '2026年1月', '2025年10月', '2025年7月', '2025年4月', '2025年1月', 'TV动画', '日本动画'
)

function ConvertFrom-BangumiTags {
    param($Tags, [int]$Top = 4, [string[]]$Exclude = @())
    $out = New-Object System.Collections.ArrayList
    foreach ($t in @($Tags)) {
        if ($out.Count -ge $Top) { break }
        $name = [string]$t.name
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        if ($script:BgmTagStop -contains $name) { continue }
        if ($name -match '^\d{4}' ) { continue }
        if ($name -match '年\d+月$') { continue }
        if ($name -match '^[\x20-\x7E]+$') { continue }          # 纯拉丁标签多为动画公司 / 人名
        if ($t.count -and [int]$t.count -lt 120) { continue }     # 太冷门的标签不要
        $skip = $false
        foreach ($ex in @($Exclude)) { if ($ex -and $name -eq $ex) { $skip = $true; break } }
        if ($skip) { continue }
        [void]$out.Add($name)
    }
    return $out.ToArray()
}

function Get-BangumiSubject {
    param([int]$Id, $Config, [switch]$Force, [int]$MaxAgeMinutes = 1440)
    $url = $script:BgmApi + '/v0/subjects/' + $Id
    $r = Get-JsonCached -Url $url -MaxAgeMinutes $MaxAgeMinutes -Force:$Force -Headers (Get-BangumiHeaders $Config) `
        -Network (Get-Prop $Config 'network') -CacheKey ('bgm:subject:' + $Id)
    if (-not $r.ok) { return [pscustomobject]@{ ok = $false; data = $null; error = $r.error } }
    return [pscustomobject]@{ ok = $true; data = $r.data; error = $null }
}

function ConvertFrom-BangumiSubject {
    param($Subject, [int]$TagCount = 4)
    if (-not $Subject) { return $null }
    $station = ''
    $weekday = ''
    $startDate = ''
    $epsText = ''
    $studio = ''
    foreach ($ib in @($Subject.infobox)) {
        $key = [string]$ib.key
        $val = $ib.value
        if ($val -is [array]) { $val = (($val | ForEach-Object { $_.v }) -join ' / ') }
        $val = [string]$val
        switch -Regex ($key) {
            '^播放电视台$' { $station = $val }
            '^其他电视台$' { if (-not $station) { $station = $val } }
            '^放送星期$' { $weekday = $val }
            '^放送开始$' { $startDate = $val }
            '^话数$' { $epsText = $val }
            '^动画制作$' { $studio = $val }
        }
    }
    $score = 0
    if ($Subject.rating -and $Subject.rating.score) { $score = [double]$Subject.rating.score }
    return [pscustomobject]@{
        id        = [int]$Subject.id
        name      = [string]$Subject.name
        nameCn    = [string]$Subject.name_cn
        score     = $score
        rank      = [int](Get-Prop (Get-Prop $Subject 'rating') 'rank' 0)
        date      = [string]$Subject.date
        eps       = [int](Get-Prop $Subject 'eps' 0)
        summary   = [string](Get-Prop $Subject 'summary' '')
        station   = $station
        weekday   = $weekday
        startDate = $startDate
        epsText   = $epsText
        studio    = $studio
        image     = [string](Get-Prop (Get-Prop $Subject 'images') 'large' '')
        tags      = @(ConvertFrom-BangumiTags -Tags $Subject.tags -Top $TagCount -Exclude @($studio))
    }
}

# ---------- 名称 -> 条目 ID 解析（搜索接口，结果缓存 7 天）----------
function Find-BangumiSubjectId {
    param([string]$Keyword, $Config, [switch]$Force)
    if ([string]::IsNullOrWhiteSpace($Keyword)) { return $null }
    $payload = [pscustomobject]@{ keyword = $Keyword; filter = [pscustomobject]@{ type = @(2) } } | ConvertTo-Json -Depth 5 -Compress
    $url = $script:BgmApi + '/v0/search/subjects?limit=5'
    $r = Get-JsonCached -Url $url -Method 'POST' -Body $payload -MaxAgeMinutes 10080 -Force:$Force `
        -Headers (Get-BangumiHeaders $Config -Json) -Network (Get-Prop $Config 'network') -CacheKey ('bgm:search:' + $Keyword)
    if (-not $r.ok) { return $null }
    $items = @(Get-Prop $r.data 'data' @())
    if ($items.Count -eq 0) { return $null }
    return $items[0]
}

# ---------- 收藏（在看）----------
function Get-BangumiCollections {
    param(
        [string]$Username = '',
        [string]$Token = '',
        [int]$Type = 3,                       # 1想看 2看过 3在看 4搁置 5抛弃
        $Config,
        [switch]$Force,
        [int]$MaxAgeMinutes = 180,
        [int]$MaxPages = 6
    )
    $all = New-Object System.Collections.ArrayList
    $base = ''
    if ($Token) { $base = $script:BgmApi + '/v0/users/-/collections' }
    elseif ($Username) { $base = $script:BgmApi + '/v0/users/' + [uri]::EscapeDataString($Username) + '/collections' }
    else { return [pscustomobject]@{ ok = $false; items = @(); error = '未登录且未设置用户名' } }

    $total = $null
    for ($page = 0; $page -lt $MaxPages; $page++) {
        $offset = $page * 100
        $url = '{0}?subject_type=2&type={1}&limit=100&offset={2}' -f $base, $Type, $offset
        $r = Get-JsonCached -Url $url -MaxAgeMinutes $MaxAgeMinutes -Force:$Force `
            -Headers (Get-BangumiHeaders $Config -Token $Token) -Network (Get-Prop $Config 'network') `
            -CacheKey ('bgm:collections:' + $Type + ':' + $(if ($Token) { 'me' } else { $Username }) + ':' + $offset)
        if (-not $r.ok) {
            if ($all.Count -gt 0) { break }
            return [pscustomobject]@{ ok = $false; items = @(); error = $r.error }
        }
        if ($null -eq $total) { $total = [int](Get-Prop $r.data 'total' 0) }
        $items = @(Get-Prop $r.data 'data' @())
        foreach ($it in $items) { [void]$all.Add($it) }
        if ($items.Count -lt 100) { break }
        if ($total -and $all.Count -ge $total) { break }
    }
    return [pscustomobject]@{ ok = $true; items = $all.ToArray(); total = $total; error = $null }
}

function Get-BangumiMe {
    param([string]$Token, $Config)
    if (-not $Token) { return [pscustomobject]@{ ok = $false; data = $null; error = '未提供 Token' } }
    $url = $script:BgmApi + '/v0/users/-'
    $r = Invoke-JsonApi -Url $url -Headers (Get-BangumiHeaders $Config -Token $Token) -Network (Get-Prop $Config 'network')
    return $r
}

function Add-BangumiCollection {
    param([int]$SubjectId, [string]$Token, $Config, [int]$Type = 3)
    if (-not $Token) { return [pscustomobject]@{ ok = $false; error = '未登录' } }
    $url = $script:BgmApi + '/v0/users/-/collections/' + $SubjectId
    $body = [pscustomobject]@{ type = $Type } | ConvertTo-Json -Compress
    $r = Invoke-HttpText -Url $url -Method 'POST' -Body $body -Headers (Get-BangumiHeaders $Config -Token $Token -Json) -Network (Get-Prop $Config 'network')
    return [pscustomobject]@{ ok = $r.ok; status = $r.status; error = $r.error }
}

# ---------- 本地授权信息 ----------
function Get-AuthPath { Join-Path (Get-DataDir) 'auth.json' }

function Get-BangumiAuth {
    $a = Read-JsonFile (Get-AuthPath)
    if (-not $a) {
        return [pscustomobject]@{ accessToken = ''; refreshToken = ''; expiresAt = $null; username = ''; userId = 0; appId = ''; appSecret = ''; redirectPort = 3721 }
    }
    return $a
}

function Save-BangumiAuth {
    param($Auth)
    Write-JsonFile (Get-AuthPath) $Auth | Out-Null
}

# Token 过期时自动刷新
function Update-BangumiAuthToken {
    param($Config, [switch]$Force)
    $auth = Get-BangumiAuth
    if (-not $auth.accessToken) { return $auth }
    $expired = $true
    if ($auth.expiresAt) {
        try { $expired = ((Get-Date) -gt ([datetime]$auth.expiresAt).AddMinutes(-30)) } catch { $expired = $true }
    }
    if (-not $expired -and -not $Force) { return $auth }
    if (-not $auth.refreshToken -or -not $auth.appId -or -not $auth.appSecret) { return $auth }

    $redirect = 'http://localhost:{0}/callback' -f (Get-Prop $auth 'redirectPort' 3721)
    $form = @{
        grant_type    = 'refresh_token'
        client_id     = $auth.appId
        client_secret = $auth.appSecret
        refresh_token = $auth.refreshToken
        redirect_uri  = $redirect
    }
    $pairs = @()
    foreach ($k in $form.Keys) { $pairs += ('{0}={1}' -f $k, [uri]::EscapeDataString([string]$form[$k])) }
    $r = Invoke-HttpText -Url ($script:BgmOauth + '/access_token') -Method 'POST' -Body ($pairs -join '&') `
        -Headers @{ 'Content-Type' = 'application/x-www-form-urlencoded'; 'Accept' = 'application/json' } -Network (Get-Prop $Config 'network')
    if ($r.ok) {
        try {
            $j = $r.text | ConvertFrom-Json
            $auth.accessToken = [string]$j.access_token
            if ($j.refresh_token) { $auth.refreshToken = [string]$j.refresh_token }
            $auth.expiresAt = (Get-Date).AddSeconds([int]$j.expires_in).ToString('o')
            Save-BangumiAuth $auth
            Write-Log 'Bangumi Token 已刷新' 'INFO'
        } catch { Write-Log "Token 刷新解析失败：$($_.Exception.Message)" 'WARN' }
    } else {
        Write-Log "Token 刷新失败：$($r.error)" 'WARN'
    }
    return $auth
}

# ---------- OAuth 授权（本机 127.0.0.1 回调，无需管理员权限）----------
function Start-BangumiOAuthFlow {
    param(
        [Parameter(Mandatory = $true)][string]$AppId,
        [Parameter(Mandatory = $true)][string]$AppSecret,
        [int]$Port = 3721,
        $Config,
        [int]$TimeoutSec = 180
    )
    $redirect = 'http://localhost:{0}/callback' -f $Port
    $authUrl = '{0}/authorize?client_id={1}&response_type=code&redirect_uri={2}' -f $script:BgmOauth, [uri]::EscapeDataString($AppId), [uri]::EscapeDataString($redirect)

    $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, $Port)
    try { $listener.Start() } catch { return [pscustomobject]@{ ok = $false; error = "无法监听本地端口 $Port ：$($_.Exception.Message)" } }

    try { Start-Process $authUrl | Out-Null } catch { Write-Log "打开浏览器失败，请手动访问：$authUrl" 'WARN' }

    $code = ''; $errMsg = ''
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    try {
        while ((Get-Date) -lt $deadline -and -not $code -and -not $errMsg) {
            if (-not $listener.Pending()) { Start-Sleep -Milliseconds 250; continue }
            $client = $listener.AcceptTcpClient()
            try {
                $stream = $client.GetStream()
                $stream.ReadTimeout = 5000
                $buf = New-Object byte[] 8192
                $n = $stream.Read($buf, 0, $buf.Length)
                $req = [System.Text.Encoding]::ASCII.GetString($buf, 0, $n)
                $line = ($req -split "`r`n")[0]
                $q = ''
                $qm = [regex]::Match($line, '^GET\s+([^\s]+)')
                if ($qm.Success) { $q = $qm.Groups[1].Value }
                $mc = [regex]::Match($q, '[?&]code=([^&\s]+)')
                $me = [regex]::Match($q, '[?&]error=([^&\s]+)')
                if ($mc.Success) { $code = [uri]::UnescapeDataString($mc.Groups[1].Value) }
                elseif ($me.Success) { $errMsg = [uri]::UnescapeDataString($me.Groups[1].Value) }

                $html = if ($code) { '<h2>授权成功，可以关闭此页面，回到桌面小组件。</h2>' } else { '<h2>授权失败，请回到小组件重试。</h2>' }
                $body = "<html><head><meta charset='utf-8'><title>Bangumi 授权</title></head><body style='font-family:Microsoft YaHei UI;background:#1b1b22;color:#e6e6f0;padding:40px'>$html</body></html>"
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
                $head = "HTTP/1.1 200 OK`r`nContent-Type: text/html; charset=utf-8`r`nContent-Length: $($bytes.Length)`r`nConnection: close`r`n`r`n"
                $hb = [System.Text.Encoding]::ASCII.GetBytes($head)
                $stream.Write($hb, 0, $hb.Length)
                $stream.Write($bytes, 0, $bytes.Length)
                $stream.Flush()
            } finally {
                try { $client.Close() } catch { }
            }
        }
    } finally {
        try { $listener.Stop() } catch { }
    }

    if (-not $code) {
        return [pscustomobject]@{ ok = $false; error = $(if ($errMsg) { "授权被拒绝：$errMsg" } else { '等待授权超时（未收到回调）' }) }
    }

    $form = @{
        grant_type    = 'authorization_code'
        client_id     = $AppId
        client_secret = $AppSecret
        code          = $code
        redirect_uri  = $redirect
    }
    $pairs = @()
    foreach ($k in $form.Keys) { $pairs += ('{0}={1}' -f $k, [uri]::EscapeDataString([string]$form[$k])) }
    $r = Invoke-HttpText -Url ($script:BgmOauth + '/access_token') -Method 'POST' -Body ($pairs -join '&') `
        -Headers @{ 'Content-Type' = 'application/x-www-form-urlencoded'; 'Accept' = 'application/json' } -Network (Get-Prop $Config 'network')
    if (-not $r.ok) { return [pscustomobject]@{ ok = $false; error = "换取 Token 失败：$($r.error)" } }
    try {
        $j = $r.text | ConvertFrom-Json
    } catch {
        return [pscustomobject]@{ ok = $false; error = "Token 响应解析失败：$($r.text)" }
    }

    $auth = Get-BangumiAuth
    $auth.accessToken = [string]$j.access_token
    $auth.refreshToken = [string]$j.refresh_token
    $auth.expiresAt = (Get-Date).AddSeconds([int]$j.expires_in).ToString('o')
    $auth.userId = [int](Get-Prop $j 'user_id' 0)
    $auth.appId = $AppId
    $auth.appSecret = $AppSecret
    $auth.redirectPort = $Port
    Save-BangumiAuth $auth

    $me = Get-BangumiMe -Token $auth.accessToken -Config $Config
    if ($me.ok -and $me.data) {
        $auth = Get-BangumiAuth
        $auth.username = [string](Get-Prop $me.data 'username' '')
        $auth.userId = [int](Get-Prop $me.data 'id' 0)
        Save-BangumiAuth $auth
    }
    return [pscustomobject]@{ ok = $true; error = $null; username = $auth.username }
}

function Test-BangumiToken {
    param([string]$Token, $Config)
    $me = Get-BangumiMe -Token $Token -Config $Config
    if ($me.ok -and $me.data) {
        return [pscustomobject]@{ ok = $true; username = [string](Get-Prop $me.data 'username' ''); userId = [int](Get-Prop $me.data 'id' 0); nickname = [string](Get-Prop $me.data 'nickname' ''); error = $null }
    }
    return [pscustomobject]@{ ok = $false; username = ''; userId = 0; nickname = ''; error = $me.error }
}
