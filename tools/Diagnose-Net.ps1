# Diagnose-Net.ps1 -- 诊断各站点/各通道的连通性，打印内层异常
param([string]$Root = (Split-Path -Parent (Split-Path -Parent $PSCommandPath)))
$Global:AnimeWidgetRoot = (Resolve-Path -LiteralPath $Root).Path
. (Join-Path $Global:AnimeWidgetRoot 'src\lib\Util.ps1')
. (Join-Path $Global:AnimeWidgetRoot 'src\lib\Http.ps1')

function Show-ErrorChain {
    param($Ex, [int]$Depth = 0)
    if (-not $Ex -or $Depth -gt 4) { return }
    $pad = ' ' * (6 + $Depth * 2)
    Write-Host ("{0}{1}: {2}" -f $pad, $Ex.GetType().Name, $Ex.Message)
    if ($Ex.InnerException) { Show-ErrorChain -Ex $Ex.InnerException -Depth ($Depth + 1) }
}

Write-Host ('SecurityProtocol = ' + [System.Net.ServicePointManager]::SecurityProtocol)
Write-Host ('DefaultWebProxy   = ' + [System.Net.WebRequest]::DefaultWebProxy)
$wp = [System.Net.WebRequest]::GetSystemWebProxy()
Write-Host ('SystemWebProxy for api.bgm.tv = ' + $wp.GetProxy((New-Object uri 'https://api.bgm.tv/calendar')))
Write-Host ''

# 证书回调能否成功挂上（PowerShell 5.1 的委托转换）
try {
    $h = New-HttpClient -ProxyKind 'direct' -TimeoutSec 20 -AllowInsecureTls $true
    $hh = $h.GetType().GetField('_handler', [System.Reflection.BindingFlags]'Instance,NonPublic')
    Write-Host 'New-HttpClient OK（证书回调已尝试设置）'
    $h.Dispose()
} catch { Write-Host ('New-HttpClient 失败：' + $_.Exception.Message) }
Write-Host ''

$targets = @(
    @{ name = 'yuc.wiki 直连'; url = 'https://yuc.wiki/202610/'; kind = 'direct'; proxy = '' },
    @{ name = 'yuc.wiki 代理'; url = 'https://yuc.wiki/202610/'; kind = 'custom'; proxy = 'http://127.0.0.1:7897' },
    @{ name = 'bgm 日历 代理'; url = 'https://api.bgm.tv/calendar'; kind = 'custom'; proxy = 'http://127.0.0.1:7897' },
    @{ name = 'bgm 日历 直连'; url = 'https://api.bgm.tv/calendar'; kind = 'direct'; proxy = '' },
    @{ name = 'example.com 代理'; url = 'https://example.com/'; kind = 'custom'; proxy = 'http://127.0.0.1:7897' }
)

foreach ($t in $targets) {
    foreach ($insecure in @($true, $false)) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $r = Invoke-HttpOnce -Url $t.url -Method 'GET' -Headers @{ 'User-Agent' = 'anime-widget/1.0' } `
            -ProxyKind $t.kind -ProxyUrl $t.proxy -TimeoutSec 20 -AllowInsecureTls $insecure -UserAgent 'anime-widget/1.0'
        $sw.Stop()
        Write-Host ("--- {0} | insecure={1} -> ok={2} status={3} len={4} {5}ms" -f $t.name, $insecure, $r.ok, $r.status, $r.text.Length, $sw.ElapsedMilliseconds)
        if (-not $r.ok) { Write-Host ("      error: " + $r.error) }
    }
}

Write-Host ''
Write-Host '--- 直接看 HttpClient 内层异常（直连 yuc.wiki, insecure=true）---'
try {
    $client = New-HttpClient -ProxyKind 'direct' -TimeoutSec 20 -AllowInsecureTls $true -UserAgent 'anime-widget/1.0'
    $resp = $client.GetAsync('https://yuc.wiki/202610/').GetAwaiter().GetResult()
    Write-Host ('  status = ' + [int]$resp.StatusCode)
    $client.Dispose()
} catch {
    Write-Host ('  异常：' + $_.Exception.GetType().FullName)
    Show-ErrorChain -Ex $_.Exception
}
