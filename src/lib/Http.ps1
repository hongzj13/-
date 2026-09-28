# Http.ps1 -- HTTP 客户端：直连 / 系统代理 / 自定义 HTTP 代理，自动降级 + 磁盘缓存
# 目标运行时：Windows PowerShell 5.1

Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue

# 提升 TLS 兼容性（老系统默认不含 TLS1.2）
try {
    $protos = [System.Net.SecurityProtocolType]::Tls12
    if ([enum]::GetNames([System.Net.SecurityProtocolType]) -contains 'Tls13') {
        $protos = $protos -bor [System.Net.SecurityProtocolType]::Tls13
    }
    [System.Net.ServicePointManager]::SecurityProtocol = $protos
} catch { }

$script:LastGoodTransport = $null
$script:HostTransport = @{}
$script:TlsBypassReady = $null

# 忽略证书校验必须用「原生代码」实现：
# PowerShell 脚本块作为委托会在 .NET 工作线程上执行，而该线程没有 runspace，必然抛错。
function Initialize-TlsBypass {
    if ($null -ne $script:TlsBypassReady) { return $script:TlsBypassReady }
    $code = @"
using System;
using System.Net.Http;
using System.Net.Security;
using System.Security.Cryptography.X509Certificates;

public class InsecureHttpClientHandler : HttpClientHandler
{
    public InsecureHttpClientHandler()
    {
        this.ServerCertificateCustomValidationCallback =
            delegate(HttpRequestMessage m, X509Certificate2 c, X509Chain ch, SslPolicyErrors e) { return true; };
    }
}

public static class TlsBypass
{
    public static void Enable()
    {
        System.Net.ServicePointManager.ServerCertificateValidationCallback =
            delegate(object sender, X509Certificate cert, X509Chain chain, SslPolicyErrors errors) { return true; };
    }
}
"@
    try {
        Add-Type -TypeDefinition $code -ReferencedAssemblies @('System.Net.Http') -ErrorAction Stop
        $script:TlsBypassReady = $true
    } catch {
        Write-Log "TLS 辅助类型编译失败，将使用严格证书校验：$($_.Exception.Message)" 'WARN'
        $script:TlsBypassReady = $false
    }
    return $script:TlsBypassReady
}

function New-HttpClient {
    param(
        [string]$ProxyKind = 'direct',   # direct | system | custom
        [string]$ProxyUrl = '',
        [int]$TimeoutSec = 25,
        [bool]$AllowInsecureTls = $true,
        [string]$UserAgent = 'anime-widget/1.0'
    )

    $handler = $null
    if ($AllowInsecureTls -and (Initialize-TlsBypass)) {
        try { $handler = New-Object InsecureHttpClientHandler } catch { $handler = $null }
        try { [TlsBypass]::Enable() } catch { }
    }
    if (-not $handler) { $handler = New-Object System.Net.Http.HttpClientHandler }
    $handler.AllowAutoRedirect = $true
    $handler.AutomaticDecompression = ([System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate)

    switch ($ProxyKind) {
        'direct' { $handler.UseProxy = $false }
        'system' {
            $handler.UseProxy = $true
            try { $handler.Proxy = [System.Net.WebRequest]::GetSystemWebProxy() } catch { $handler.UseProxy = $false }
        }
        'custom' {
            if ([string]::IsNullOrWhiteSpace($ProxyUrl)) { throw '未配置代理地址' }
            if ($ProxyUrl -match '^(?i)socks') {
                throw 'SOCKS 代理需要 .NET 6+（当前为 Windows PowerShell 5.1）。请改用 HTTP 代理端口，例如 Clash 的混合端口 http://127.0.0.1:7897'
            }
            $handler.UseProxy = $true
            $uri = $ProxyUrl
            if ($uri -notmatch '^(?i)https?://') { $uri = 'http://' + $uri }
            $handler.Proxy = New-Object System.Net.WebProxy($uri, $true)
        }
    }


    $client = New-Object System.Net.Http.HttpClient($handler)
    $client.Timeout = [TimeSpan]::FromSeconds([math]::Max(5, $TimeoutSec))
    try {
        $client.DefaultRequestHeaders.TryAddWithoutValidation('User-Agent', $UserAgent) | Out-Null
        $client.DefaultRequestHeaders.TryAddWithoutValidation('Accept-Language', 'zh-CN,zh;q=0.9,ja;q=0.8,en;q=0.7') | Out-Null
    } catch { }
    return $client
}

function Get-ResponseText {
    param($Response)
    $bytes = $Response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
    if ($null -eq $bytes) { return '' }
    $charset = $null
    try {
        if ($Response.Content.Headers.ContentType -and $Response.Content.Headers.ContentType.CharSet) {
            $charset = $Response.Content.Headers.ContentType.CharSet.Trim('"')
        }
    } catch { }
    $encoding = $null
    if ($charset) { try { $encoding = [System.Text.Encoding]::GetEncoding($charset) } catch { } }
    if (-not $encoding) { $encoding = New-Object System.Text.UTF8Encoding($false) }
    $text = $encoding.GetString($bytes)
    # 若 UTF-8 解码出现大量替换字符，尝试 GB18030（部分中文站点）
    $bad = ([regex]::Matches($text, [string][char]0xFFFD)).Count
    if (-not $charset -and $bad -gt 3) {
        try {
            $gbk = [System.Text.Encoding]::GetEncoding(54936)
            $alt = $gbk.GetString($bytes)
            if (([regex]::Matches($alt, [string][char]0xFFFD)).Count -lt $bad) { $text = $alt }
        } catch { }
    }
    return $text
}

# 单一通道请求；返回 @{ ok; status; text; error }
function Invoke-HttpOnce {
    param(
        [string]$Url,
        [string]$Method = 'GET',
        [hashtable]$Headers,
        [string]$Body,
        [string]$ProxyKind = 'direct',
        [string]$ProxyUrl = '',
        [int]$TimeoutSec = 25,
        [bool]$AllowInsecureTls = $true,
        [string]$UserAgent = 'anime-widget/1.0'
    )
    $client = $null
    try {
        $client = New-HttpClient -ProxyKind $ProxyKind -ProxyUrl $ProxyUrl -TimeoutSec $TimeoutSec -AllowInsecureTls $AllowInsecureTls -UserAgent $UserAgent
        $httpMethod = New-Object System.Net.Http.HttpMethod($Method.ToUpper())
        $req = New-Object System.Net.Http.HttpRequestMessage($httpMethod, $Url)
        if ($Headers) {
            foreach ($k in $Headers.Keys) {
                $req.Headers.TryAddWithoutValidation($k, [string]$Headers[$k]) | Out-Null
            }
        }
        if (-not [string]::IsNullOrEmpty($Body)) {
            $req.Content = New-Object System.Net.Http.StringContent($Body, [System.Text.Encoding]::UTF8)
            if (-not ($Headers -and $Headers.ContainsKey('Content-Type'))) {
                $req.Content.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse('application/json')
            }
        }
        $resp = $client.SendAsync($req, [System.Net.Http.HttpCompletionOption]::ResponseContentRead).GetAwaiter().GetResult()
        $text = Get-ResponseText -Response $resp
        $status = [int]$resp.StatusCode
        $err = $null
        if ($status -ge 400) { $err = "HTTP $status" }
        return [pscustomobject]@{
            ok = ($status -ge 200 -and $status -lt 400); status = $status; text = $text
            via = $ProxyKind; error = $err
        }
    } catch {
        $inner = $_.Exception
        while ($inner.InnerException) { $inner = $inner.InnerException }
        $msg = $_.Exception.Message
        if ($inner -and $inner.Message -and ($inner.Message -ne $msg)) { $msg = $inner.Message }
        return [pscustomobject]@{ ok = $false; status = 0; text = ''; via = $ProxyKind; error = $msg }
    } finally {
        if ($client) { try { $client.Dispose() } catch { } }
    }
}

# 自动选择通道：自定义代理 -> 系统代理 -> 直连，记住上次成功的通道
function Invoke-HttpText {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [string]$Method = 'GET',
        [hashtable]$Headers,
        [string]$Body,
        $Network,
        [int]$TimeoutSec = 0
    )
    $mode = 'auto'; $proxyUrl = ''; $allowInsecure = $true; $ua = 'anime-widget/1.0'; $t = 25
    if ($Network) {
        if ($Network.proxyMode) { $mode = [string]$Network.proxyMode }
        if ($Network.proxyUrl) { $proxyUrl = [string]$Network.proxyUrl }
        if ($null -ne $Network.allowInsecureTls) { $allowInsecure = [bool]$Network.allowInsecureTls }
        if ($Network.userAgent) { $ua = [string]$Network.userAgent }
        if ($Network.timeoutSec) { $t = [int]$Network.timeoutSec }
    }
    if ($TimeoutSec -gt 0) { $t = $TimeoutSec }

    $candidates = New-Object System.Collections.ArrayList
    $addCustom = { if (-not [string]::IsNullOrWhiteSpace($proxyUrl)) {
            [void]$candidates.Add([pscustomobject]@{ kind = 'custom'; url = $proxyUrl }) } }
    $addSystem = { [void]$candidates.Add([pscustomobject]@{ kind = 'system'; url = '' }) }
    $addDirect = { [void]$candidates.Add([pscustomobject]@{ kind = 'direct'; url = '' }) }

    switch ($mode) {
        'direct' { & $addDirect }
        'system' { & $addSystem; & $addDirect }
        'custom' { & $addCustom; & $addDirect }
        default {
            $order = @()
            if ($script:LastGoodTransport) { $order += $script:LastGoodTransport }
            & $addCustom; & $addSystem; & $addDirect
            if ($order.Count -gt 0) {
                $sorted = New-Object System.Collections.ArrayList
                foreach ($pref in $order) {
                    foreach ($c in $candidates) { if ($c.kind -eq $pref -and -not ($sorted | Where-Object { $_.kind -eq $c.kind })) { [void]$sorted.Add($c) } }
                }
                foreach ($c in $candidates) { if (-not ($sorted | Where-Object { $_.kind -eq $c.kind })) { [void]$sorted.Add($c) } }
                $candidates = $sorted
            }
        }
    }

    # 同一站点优先复用上次成功的通道（例如 yuc.wiki 直连、api.bgm.tv 走代理）
    try {
        $hostKey = ([uri]$Url).Host
        if ($hostKey -and $script:HostTransport.ContainsKey($hostKey)) {
            $prefer = $script:HostTransport[$hostKey]
            $reordered = New-Object System.Collections.ArrayList
            foreach ($c in $candidates) { if ($c.kind -eq $prefer) { [void]$reordered.Add($c) } }
            foreach ($c in $candidates) { if ($c.kind -ne $prefer) { [void]$reordered.Add($c) } }
            $candidates = $reordered
        }
    } catch { $hostKey = '' }

    $errors = @()
    foreach ($c in $candidates) {
        $attemptTimeout = $t
        if ($mode -eq 'auto' -and $c.kind -ne $script:LastGoodTransport -and $candidates.Count -gt 1) {
            $attemptTimeout = [math]::Min($t, 8)   # 探测其他通道时缩短超时，避免长时间卡住
        }
        $r = Invoke-HttpOnce -Url $Url -Method $Method -Headers $Headers -Body $Body `
            -ProxyKind $c.kind -ProxyUrl $c.url -TimeoutSec $attemptTimeout -AllowInsecureTls $allowInsecure -UserAgent $ua
        if ($r.ok) {
            $script:LastGoodTransport = $c.kind
            if ($hostKey) { $script:HostTransport[$hostKey] = $c.kind }
            if ($c.kind -ne 'direct') { Write-Log "使用代理通道 $($c.kind)($($c.url)) 请求 $Url" 'DEBUG' }
            return $r
        }
        $errors += ("{0}: {1}" -f $c.kind, $r.error)
        if ($r.status -ge 400) { return $r }   # 服务器已回应（如 404/403），无需换通道
    }
    return [pscustomobject]@{ ok = $false; status = 0; text = ''; via = $mode; error = ($errors -join ' | ') }
}

# 带磁盘缓存的取文本
function Get-CachedText {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [int]$MaxAgeMinutes = 360,
        [switch]$Force,
        [hashtable]$Headers,
        [string]$Method = 'GET',
        [string]$Body,
        $Network,
        [string]$CacheKey = ''
    )
    $dir = Get-CacheDir
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    if ([string]::IsNullOrEmpty($CacheKey)) { $CacheKey = $Url }
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $hash = [System.BitConverter]::ToString($md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Method + '|' + $CacheKey + '|' + $Body))).Replace('-', '').ToLower()
    $metaPath = Join-Path $dir ($hash + '.meta.json')
    $bodyPath = Join-Path $dir ($hash + '.body')

    if (-not $Force -and (Test-Path $metaPath) -and (Test-Path $bodyPath)) {
        $meta = Read-JsonFile $metaPath
        if ($meta -and $meta.fetchedAt) {
            $age = ((Get-Date) - [datetime]$meta.fetchedAt).TotalMinutes
            if ($age -le $MaxAgeMinutes) {
                $text = [System.IO.File]::ReadAllText($bodyPath, [System.Text.Encoding]::UTF8)
                return [pscustomobject]@{ ok = $true; text = $text; fromCache = $true; fetchedAt = [datetime]$meta.fetchedAt; via = 'cache'; error = $null }
            }
        }
    }

    $r = Invoke-HttpText -Url $Url -Method $Method -Headers $Headers -Body $Body -Network $Network
    if ($r.ok) {
        try {
            [System.IO.File]::WriteAllText($bodyPath, $r.text, (New-Object System.Text.UTF8Encoding($false)))
            Write-JsonFile $metaPath ([pscustomobject]@{ url = $Url; fetchedAt = (Get-Date).ToString('o'); via = $r.via; status = $r.status }) | Out-Null
        } catch { Write-Log "缓存写入失败：$($_.Exception.Message)" 'WARN' }
        return [pscustomobject]@{ ok = $true; text = $r.text; fromCache = $false; fetchedAt = (Get-Date); via = $r.via; error = $null }
    }

    # 网络失败时回退到过期缓存
    if ((Test-Path $metaPath) -and (Test-Path $bodyPath)) {
        $meta = Read-JsonFile $metaPath
        $text = [System.IO.File]::ReadAllText($bodyPath, [System.Text.Encoding]::UTF8)
        Write-Log "网络失败，使用过期缓存：$Url ($($r.error))" 'WARN'
        return [pscustomobject]@{ ok = $true; text = $text; fromCache = $true; stale = $true; fetchedAt = [datetime](Get-Prop $meta 'fetchedAt' (Get-Date)); via = 'stale-cache'; error = $r.error }
    }

    return [pscustomobject]@{ ok = $false; text = ''; fromCache = $false; fetchedAt = $null; via = $r.via; error = $r.error }
}

function Get-JsonCached {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [int]$MaxAgeMinutes = 360,
        [switch]$Force,
        [hashtable]$Headers,
        [string]$Method = 'GET',
        [string]$Body,
        $Network,
        [string]$CacheKey = ''
    )
    $r = Get-CachedText -Url $Url -MaxAgeMinutes $MaxAgeMinutes -Force:$Force -Headers $Headers -Method $Method -Body $Body -Network $Network -CacheKey $CacheKey
    if (-not $r.ok) { return [pscustomobject]@{ ok = $false; data = $null; error = $r.error; fetchedAt = $null; fromCache = $false } }
    try {
        $data = $r.text | ConvertFrom-Json
        return [pscustomobject]@{ ok = $true; data = $data; error = $null; fetchedAt = $r.fetchedAt; fromCache = $r.fromCache; stale = (Get-Prop $r 'stale' $false) }
    } catch {
        return [pscustomobject]@{ ok = $false; data = $null; error = "JSON 解析失败：$($_.Exception.Message)"; fetchedAt = $r.fetchedAt; fromCache = $r.fromCache }
    }
}

function Invoke-JsonApi {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [string]$Method = 'GET',
        [hashtable]$Headers,
        [string]$Body,
        $Network,
        [int]$TimeoutSec = 0
    )
    $r = Invoke-HttpText -Url $Url -Method $Method -Headers $Headers -Body $Body -Network $Network -TimeoutSec $TimeoutSec
    if (-not $r.ok) { return [pscustomobject]@{ ok = $false; data = $null; status = $r.status; error = $r.error } }
    try {
        $data = $r.text | ConvertFrom-Json
        return [pscustomobject]@{ ok = $true; data = $data; status = $r.status; error = $null }
    } catch {
        return [pscustomobject]@{ ok = $false; data = $null; status = $r.status; error = "JSON 解析失败：$($_.Exception.Message)" }
    }
}
