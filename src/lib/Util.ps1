# Util.ps1 -- 基础工具：路径、JSON 读写、HTML 文本处理、名称归一化、日志
# 目标运行时：Windows PowerShell 5.1（文件须保存为 UTF-8 with BOM）

# 引入 DPI 感知（高分屏清晰渲染）
. (Join-Path (Split-Path -Parent $PSCommandPath) 'Dpi.ps1')

function Get-Root {
    if ($Global:AnimeWidgetRoot) { return $Global:AnimeWidgetRoot }
    return (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath)))
}
function Get-DataDir { Join-Path (Get-Root) 'data' }
function Get-CacheDir { Join-Path (Get-DataDir) 'cache' }
function Get-LogPath { Join-Path (Get-DataDir) 'widget.log' }

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    try {
        $dir = Get-DataDir
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
        Add-Content -Path (Get-LogPath) -Value $line -Encoding UTF8
        if ($Global:AnimeWidgetVerbose) { Write-Host $line }
    } catch { }
}

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    try {
        $raw = Get-Content -Path $Path -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return ($raw | ConvertFrom-Json)
    } catch {
        Write-Log "JSON 读取失败 $Path : $($_.Exception.Message)" 'WARN'
        return $null
    }
}

function Write-JsonFile {
    param([string]$Path, $Object, [int]$Depth = 12)
    try {
        $dir = Split-Path -Parent $Path
        if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        $json = $Object | ConvertTo-Json -Depth $Depth
        [System.IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding($false)))
        return $true
    } catch {
        Write-Log "JSON 写入失败 $Path : $($_.Exception.Message)" 'ERROR'
        return $false
    }
}

function Get-Prop {
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] } else { return $Default }
    }
    $p = $Object.PSObject.Properties[$Name]
    if ($p -and $null -ne $p.Value) { return $p.Value }
    return $Default
}

function ConvertTo-HalfWidth {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $Text.ToCharArray()) {
        $c = [int][char]$ch
        if ($c -eq 0x3000) { [void]$sb.Append(' ') }
        elseif ($c -ge 0xFF01 -and $c -le 0xFF5E) { [void]$sb.Append([char]($c - 0xFEE0)) }
        else { [void]$sb.Append($ch) }
    }
    return $sb.ToString()
}

# 去掉 HTML 标签 / 实体，折叠空白；<br> 视为分隔符
function ConvertFrom-HtmlText {
    param([string]$Html, [string]$Separator = ' ', [switch]$Lines)
    if ([string]::IsNullOrEmpty($Html)) { return '' }
    $s = $Html
    $s = [regex]::Replace($s, '(?is)<\s*br\s*/?\s*>', $Separator)
    $s = [regex]::Replace($s, '(?is)<\s*/\s*(p|div|tr|li|td)\s*>', $Separator)
    $s = [regex]::Replace($s, '(?s)<!--.*?-->', '')
    $s = [regex]::Replace($s, '(?s)<[^>]+>', '')
    $s = [System.Net.WebUtility]::HtmlDecode($s)
    $s = $s -replace '[\u00A0\u3000]', ' '
    if ($Lines) {
        $parts = @($s -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        return ($parts -join "`n")
    }
    $s = [regex]::Replace($s, '\s+', ' ')
    return $s.Trim()
}

# 名称归一化：用于 yuc 中文名 / 日文名 与 Bangumi 名称的模糊匹配
function ConvertTo-NormName {
    param([string]$Name, [switch]$KeepSeason)
    if ([string]::IsNullOrWhiteSpace($Name)) { return '' }
    $s = ConvertTo-HalfWidth $Name
    $s = $s.ToLowerInvariant()
    if (-not $KeepSeason) {
        $s = [regex]::Replace($s, '(?i)\bseason\s*\d+', '')
        $s = [regex]::Replace($s, '(?i)\bpart\s*\.?\s*\d+', '')
        $s = [regex]::Replace($s, '(?i)\b\d+(st|nd|rd|th)\s*season\b', '')
        $s = [regex]::Replace($s, '第\s*[0-9一二三四五六七八九十]+\s*[期季部]', '')
        $s = [regex]::Replace($s, '[0-9]+\s*(クール|期|季)', '')
    }
    $s = [regex]::Replace($s, '[\s]', '')
    $s = [regex]::Replace($s, '[·・:：;；,，.。!！?？~～\-—_''"“”‘’()（）\[\]【】「」『』《》/\\|+&★☆]', '')
    return $s.Trim()
}

# 生成若干候选键（整名 + 去季名 + 去副标题），用于匹配打分
function Get-NameKeys {
    param([string]$Name)
    $keys = New-Object System.Collections.Generic.List[string]
    if ([string]::IsNullOrWhiteSpace($Name)) { return $keys }
    $full = ConvertTo-NormName $Name -KeepSeason
    $base = ConvertTo-NormName $Name
    foreach ($k in @($full, $base)) {
        if ($k -and $k.Length -ge 2 -and -not $keys.Contains($k)) { [void]$keys.Add($k) }
    }
    # 去掉副标题（以 ～ ~ - 空格 等分隔后的第一段）
    foreach ($src in @($full, $base)) {
        $head = ($src -split '[~～]')[0]
        if ($head -and $head.Length -ge 4 -and -not $keys.Contains($head)) { [void]$keys.Add($head) }
    }
    return $keys
}

# 季度计算：1/4/7/10 月
function Get-SeasonInfo {
    param([datetime]$Date = (Get-Date))
    $q = [int][math]::Floor(($Date.Month - 1) / 3) + 1
    $startMonth = ($q - 1) * 3 + 1
    $start = Get-Date -Year $Date.Year -Month $startMonth -Day 1 -Hour 0 -Minute 0 -Second 0
    $next = $start.AddMonths(3)
    return [pscustomobject]@{
        Year       = $Date.Year
        Quarter    = $q
        StartMonth = $startMonth
        Start      = $start
        End        = $next.AddDays(-1)
        NextStart  = $next
        Key        = ('{0}{1:D2}' -f $Date.Year, $startMonth)
        NextKey    = ('{0}{1:D2}' -f $next.Year, $next.Month)
        Label      = ('{0}年{1}月' -f $Date.Year, $startMonth)
    }
}

function Get-WeekdayIndex {
    param([datetime]$Date)
    # 0 = 周一 ... 6 = 周日
    return (([int]$Date.DayOfWeek) + 6) % 7
}

$script:WeekdayCn = @('周一', '周二', '周三', '周四', '周五', '周六', '周日')
$script:WeekdayShort = @('一', '二', '三', '四', '五', '六', '日')

function Get-WeekdayName {
    param([int]$Index)
    if ($Index -lt 0 -or $Index -gt 6) { return '' }
    return $script:WeekdayCn[$Index]
}

# 短小写工具
function Format-DateCn {
    param([datetime]$Date)
    return ('{0}月{1}日 {2}' -f $Date.Month, $Date.Day, $script:WeekdayCn[(Get-WeekdayIndex $Date)])
}

function Test-TextLike {
    param([string]$Text, [string]$Pattern)
    if ([string]::IsNullOrEmpty($Text)) { return $false }
    return [regex]::IsMatch($Text, $Pattern)
}

# ---------------- 后台任务（runspace）----------------
# 用于在 UI 不卡顿的前提下做网络抓取 / OAuth 等待
function Start-BackgroundJob {
    param([Parameter(Mandatory = $true)][scriptblock]$ScriptBlock, [object[]]$Arguments = @())
    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $rs.ApartmentState = [System.Threading.ApartmentState]::STA
    $rs.ThreadOptions = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread
    $rs.Open()
    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript($ScriptBlock.ToString())
    foreach ($a in @($Arguments)) { [void]$ps.AddArgument($a) }
    $handle = $ps.BeginInvoke()
    return [pscustomobject]@{ Ps = $ps; Runspace = $rs; Handle = $handle }
}

function Receive-BackgroundJob {
    param($Job)
    $out = @(); $err = @()
    if (-not $Job) { return [pscustomobject]@{ Output = @(); Error = @('任务不存在') } }
    try { $out = @($Job.Ps.EndInvoke($Job.Handle)) } catch { $err += $_.Exception.Message }
    try { foreach ($e in @($Job.Ps.Streams.Error)) { $err += $e.ToString() } } catch { }
    try { $Job.Ps.Dispose() } catch { }
    try { $Job.Runspace.Close(); $Job.Runspace.Dispose() } catch { }
    return [pscustomobject]@{ Output = $out; Error = $err }
}

# JST 时间显示规范化：25:00 -> 次日 01:00，避免出现 >24 小时的“25:00”
function Format-JstTimeDisplay {
    param([string]$TimeJst)
    if ([string]::IsNullOrWhiteSpace($TimeJst)) { return '' }
    $m = [regex]::Match($TimeJst, '^(\d{1,2}):(\d{2})')
    if (-not $m.Success) { return $TimeJst }
    $h = [int]$m.Groups[1].Value
    $mi = $m.Groups[2].Value
    if ($h -ge 24) { return ('次日{0:D2}:{1}' -f ($h - 24), $mi) }
    return ('{0:D2}:{1}' -f $h, $mi)
}