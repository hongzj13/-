# Ui.ps1 -- 桌面小组件界面（无边框 / 置顶 / 半透明 / 可拖动 / 自绘）
# 单画布方案：整个窗口由一个 Paint 处理器绘制，鼠标命中测试决定交互，避免控件层级问题。
# 目标运行时：Windows PowerShell 5.1

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
try { [System.Windows.Forms.Application]::EnableVisualStyles() } catch { }

# ---------------- 主题 ----------------
# 预设配色（可更换背景）
$script:ThemePresets = @{
    'deep-purple' = @{ bg = '#100D18'; panel = '#1A1428'; rowHover = '#272041'; chipBg = '#2B2346'; chipBg2 = '#37295E'; line = '#2A2242'; text = '#F4F1FB'; sub = '#A99EC8'; dim = '#766B9E'; accent = '#9D7BFF'; star = '#C9B2FF'; warn = '#E48A8A' }
    'black'       = @{ bg = '#0B0B0E'; panel = '#16161C'; rowHover = '#1E1E25'; chipBg = '#23232C'; chipBg2 = '#30303C'; line = '#1F1F26'; text = '#F2F2F6'; sub = '#A6A6B4'; dim = '#757582'; accent = '#8A7BFF'; star = '#C3B4FF'; warn = '#E48A8A' }
    'deep-blue'   = @{ bg = '#0A111D'; panel = '#141C2C'; rowHover = '#1B2639'; chipBg = '#1F2C44'; chipBg2 = '#2A3B5E'; line = '#1D2840'; text = '#F0F4FB'; sub = '#A4B4CC'; dim = '#6E7F9C'; accent = '#6FA8FF'; star = '#9EC8FF'; warn = '#E48A8A' }
    'dark-green'  = @{ bg = '#0B120E'; panel = '#141E17'; rowHover = '#1C2A20'; chipBg = '#20352B'; chipBg2 = '#2C4834'; line = '#1E2E24'; text = '#F0F6F1'; sub = '#A4C2AC'; dim = '#6E8F78'; accent = '#7BD494'; star = '#A6E8B8'; warn = '#E48A8A' }
    'dark-red'    = @{ bg = '#160D10'; panel = '#211418'; rowHover = '#2C1A20'; chipBg = '#3A2028'; chipBg2 = '#4E2A34'; line = '#2E1B22'; text = '#F8EFF1'; sub = '#C9A5AE'; dim = '#8F6C75'; accent = '#FF8F9B'; star = '#FFB4BC'; warn = '#FF9E9E' }
    'light'       = @{ bg = '#F3F2F8'; panel = '#FFFFFF'; rowHover = '#E9E7F2'; chipBg = '#E5E2F0'; chipBg2 = '#D8D3EC'; line = '#DCD9E8'; text = '#201B33'; sub = '#5B5470'; dim = '#8B84A3'; accent = '#7C5CFF'; star = '#8A6BFF'; warn = '#C2454A' }
}

# 两色按比例混合（自定义背景时自动推导其余颜色）
function ConvertTo-MixHex {
    param([string]$HexA, [string]$HexB, [double]$AmountB)
    try {
        $a = [System.Drawing.ColorTranslator]::FromHtml($HexA)
        $b = [System.Drawing.ColorTranslator]::FromHtml($HexB)
        $r = [int][math]::Round($a.R + ($b.R - $a.R) * $AmountB)
        $g = [int][math]::Round($a.G + ($b.G - $a.G) * $AmountB)
        $bl = [int][math]::Round($a.B + ($b.B - $a.B) * $AmountB)
        return ('#{0:X2}{1:X2}{2:X2}' -f [math]::Max(0, [math]::Min(255, $r)), [math]::Max(0, [math]::Min(255, $g)), [math]::Max(0, [math]::Min(255, $bl)))
    } catch { return $HexA }
}

function New-Theme {
    param($Config)
    $name = 'deep-purple'
    if ($Config -and $Config.ui -and $Config.ui.theme) { $name = [string]$Config.ui.theme }

    $p = $null
    if ($name -eq 'custom') {
        # 自定义背景色：其余颜色由背景亮度自动推导
        $bg = [string](Get-Prop $Config.ui 'bgCustom' '#14121E')
        $isLight = $false
        try {
            $c = [System.Drawing.ColorTranslator]::FromHtml($bg)
            $isLight = ((0.299 * $c.R + 0.587 * $c.G + 0.114 * $c.B) / 255.0 -gt 0.55)
        } catch { }
        $textBase = $(if ($isLight) { '#0A0A0E' } else { '#FFFFFF' })
        $acc = [string](Get-Prop $Config.ui 'accent' '#9D7BFF')
        $p = @{
            bg       = $bg
            panel    = $(if ($isLight) { ConvertTo-MixHex $bg $textBase 0.07 } else { ConvertTo-MixHex $bg '#FFFFFF' 0.08 })
            rowHover = $(if ($isLight) { ConvertTo-MixHex $bg $textBase 0.10 } else { ConvertTo-MixHex $bg '#FFFFFF' 0.10 })
            chipBg   = $(if ($isLight) { ConvertTo-MixHex $bg $textBase 0.12 } else { ConvertTo-MixHex $bg '#FFFFFF' 0.14 })
            chipBg2  = $(if ($isLight) { ConvertTo-MixHex $bg $textBase 0.20 } else { ConvertTo-MixHex $bg '#FFFFFF' 0.24 })
            line     = $(if ($isLight) { ConvertTo-MixHex $bg $textBase 0.14 } else { ConvertTo-MixHex $bg '#FFFFFF' 0.12 })
            text     = $textBase
            sub      = ConvertTo-MixHex $bg $textBase 0.62
            dim      = ConvertTo-MixHex $bg $textBase 0.42
            accent   = $acc
            star     = ConvertTo-MixHex $bg $textBase 0.72
            warn     = '#E48A8A'
        }
    } else {
        $p = $script:ThemePresets[$name]
        if (-not $p) { $p = $script:ThemePresets['deep-purple']; $name = 'deep-purple' }
        $acc = [string](Get-Prop $Config.ui 'accent' $p.accent)
        $p.accent = $acc
    }

    return @{
        bg        = [System.Drawing.ColorTranslator]::FromHtml($p.bg)
        panel     = [System.Drawing.ColorTranslator]::FromHtml($p.panel)
        rowHover  = [System.Drawing.ColorTranslator]::FromHtml($p.rowHover)
        chipBg    = [System.Drawing.ColorTranslator]::FromHtml($p.chipBg)
        chipBg2   = [System.Drawing.ColorTranslator]::FromHtml($p.chipBg2)
        line      = [System.Drawing.ColorTranslator]::FromHtml($p.line)
        text      = [System.Drawing.ColorTranslator]::FromHtml($p.text)
        sub       = [System.Drawing.ColorTranslator]::FromHtml($p.sub)
        dim       = [System.Drawing.ColorTranslator]::FromHtml($p.dim)
        accent    = [System.Drawing.ColorTranslator]::FromHtml($p.accent)
        accentDim = [System.Drawing.ColorTranslator]::FromHtml($p.chipBg2)
        star      = [System.Drawing.ColorTranslator]::FromHtml($p.star)
        warn      = [System.Drawing.ColorTranslator]::FromHtml($p.warn)
        Name      = $name
    }
}

function New-FontSafe {
    param([string]$Family, [float]$Size, [System.Drawing.FontStyle]$Style = [System.Drawing.FontStyle]::Regular)
    $candidates = @($Family, 'Microsoft YaHei', 'Microsoft YaHei UI', 'Segoe UI', 'SimSun')
    foreach ($f in $candidates) {
        if ([string]::IsNullOrWhiteSpace($f)) { continue }
        try {
            $font = New-Object System.Drawing.Font($f, $Size, $Style, [System.Drawing.GraphicsUnit]::Point)
            return $font
        } catch { }
    }
    return (New-Object System.Drawing.Font([System.Drawing.FontFamily]::GenericSansSerif, $Size, $Style))
}

# 像素字体：配合 DPI 缩放的 ScaleTransform 使用（Point 字体在 DPI 感知下会与 transform 双重缩放）
function New-FontPx {
    param([string]$Family, [float]$SizePx, [System.Drawing.FontStyle]$Style = [System.Drawing.FontStyle]::Regular)
    $candidates = @($Family, 'Microsoft YaHei', 'Microsoft YaHei UI', 'Segoe UI', 'SimSun')
    foreach ($f in $candidates) {
        if ([string]::IsNullOrWhiteSpace($f)) { continue }
        try {
            $font = New-Object System.Drawing.Font($f, $SizePx, $Style, [System.Drawing.GraphicsUnit]::Pixel)
            return $font
        } catch { }
    }
    return (New-Object System.Drawing.Font([System.Drawing.FontFamily]::GenericSansSerif, $SizePx, $Style, [System.Drawing.GraphicsUnit]::Pixel))
}

# 按「每页行数」计算窗口高度：头部 46 + 页签 34 + 页脚 32 + 行 + 余量
function Get-WidgetHeightForRows {
    param($Config)
    $rows = [int](Get-Prop $Config.ui 'rowsPerView' 3)
    if ($rows -lt 1) { $rows = 1 }
    if ($rows -gt 30) { $rows = 30 }
    return (46 + 34 + 32 + ($rows * 76) + 8)
}

function Set-DoubleBuffered {
    param($Control, [bool]$On = $true)
    try {
        $flags = [System.Reflection.BindingFlags]'Instance,NonPublic'
        $prop = $Control.GetType().GetProperty('DoubleBuffered', $flags)
        if ($prop) { $prop.SetValue($Control, $On, $null) }
    } catch { }
}

function New-RoundedPath {
    param([System.Drawing.Rectangle]$Rect, [int]$Radius = 10)
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $Radius * 2
    if ($d -le 0) { $path.AddRectangle($Rect); return $path }
    $path.AddArc($Rect.X, $Rect.Y, $d, $d, 180, 90)
    $path.AddArc($Rect.Right - $d, $Rect.Y, $d, $d, 270, 90)
    $path.AddArc($Rect.Right - $d, $Rect.Bottom - $d, $d, $d, 0, 90)
    $path.AddArc($Rect.X, $Rect.Bottom - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    return $path
}

function Fill-RoundedRect {
    param($G, [System.Drawing.Rectangle]$Rect, [System.Drawing.Color]$Color, [int]$Radius = 8)
    if ($Rect.Width -le 0 -or $Rect.Height -le 0) { return }
    $path = New-RoundedPath -Rect $Rect -Radius $Radius
    $brush = New-Object System.Drawing.SolidBrush($Color)
    try { $G.FillPath($brush, $path) } finally { $brush.Dispose(); $path.Dispose() }
}

function Draw-TextBlock {
    param(
        $G, [string]$Text, $Font, [System.Drawing.Color]$Color, [System.Drawing.Rectangle]$Rect,
        [string]$Align = 'Near', [bool]$Ellipsis = $true, [bool]$Wrap = $false
    )
    if ($Rect.Width -le 0 -or $Rect.Height -le 0) { return }
    $flags = [System.Windows.Forms.TextFormatFlags]::NoPrefix -bor [System.Windows.Forms.TextFormatFlags]::VerticalCenter
    if ($Ellipsis) { $flags = $flags -bor [System.Windows.Forms.TextFormatFlags]::EndEllipsis }
    if ($Wrap) { $flags = $flags -bor [System.Windows.Forms.TextFormatFlags]::WordBreak }
    if ($Align -eq 'Center') { $flags = $flags -bor [System.Windows.Forms.TextFormatFlags]::HorizontalCenter }
    elseif ($Align -eq 'Far') { $flags = $flags -bor [System.Windows.Forms.TextFormatFlags]::Right }
    [System.Windows.Forms.TextRenderer]::DrawText($G, $Text, $Font, $Rect, $Color, $flags)
}

function Draw-Chip {
    param($G, [System.Drawing.Rectangle]$Rect, [string]$Text, $Font, $Theme, [bool]$Accent = $false)
    $bg = $(if ($Accent) { $Theme.chipBg2 } else { $Theme.chipBg })
    $fg = $(if ($Accent) { $Theme.accent } else { $Theme.sub })
    Fill-RoundedRect -G $G -Rect $Rect -Color $bg -Radius ([math]::Min(8, [int]($Rect.Height / 2)))
    Draw-TextBlock -G $G -Text $Text -Font $Font -Color $fg -Rect $Rect -Align 'Center'
}

function Open-Url {
    param([string]$Url)
    if ([string]::IsNullOrWhiteSpace($Url)) { return $false }
    $opened = $false
    # 1) ShellExecute 打开默认浏览器
    try { Start-Process $Url | Out-Null; $opened = $true } catch { }
    # 2) Process.Start(字符串) 亦走 ShellExecute
    if (-not $opened) { try { [System.Diagnostics.Process]::Start($Url) | Out-Null; $opened = $true } catch { } }
    # 3) explorer.exe
    if (-not $opened) { try { Start-Process 'explorer.exe' -ArgumentList $Url | Out-Null; $opened = $true } catch { } }
    # 4) cmd start（对无默认关联的系统更稳）
    if (-not $opened) { try { Start-Process 'cmd.exe' -ArgumentList @('/c', 'start', '', $Url) | Out-Null; $opened = $true } catch { } }
    # 5) 兜底：复制到剪贴板并提示
    if (-not $opened) {
        try { [System.Windows.Forms.Clipboard]::SetText($Url) } catch { }
        try {
            [System.Windows.Forms.MessageBox]::Show(("无法自动打开浏览器，链接已复制到剪贴板，请手动粘贴到浏览器打开：`n`n{0}" -f $Url), '打开链接', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        } catch { }
    }
    return $opened
}

# ---------------- 图标（运行时绘制，无需外部文件）----------------
function New-WidgetBitmap {
    param([int]$Size = 32, [string]$Text = '番', [string]$Accent = '#9D7BFF')
    $bmp = New-Object System.Drawing.Bitmap($Size, $Size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
        $rect = New-Object System.Drawing.Rectangle(0, 0, $Size, $Size)
        $path = New-RoundedPath -Rect $rect -Radius ([int]($Size * 0.28))
        $bg = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml('#232336'))
        $g.FillPath($bg, $path)
        $pen = New-Object System.Drawing.Pen([System.Drawing.ColorTranslator]::FromHtml($Accent), [float]([math]::Max(1, $Size / 16)))
        $g.DrawPath($pen, $path)
        $font = New-FontSafe -Family 'Microsoft YaHei UI' -Size ([float]($Size * 0.46)) -Style ([System.Drawing.FontStyle]::Bold)
        $flags = [System.Windows.Forms.TextFormatFlags]::NoPrefix -bor [System.Windows.Forms.TextFormatFlags]::HorizontalCenter -bor [System.Windows.Forms.TextFormatFlags]::VerticalCenter
        [System.Windows.Forms.TextRenderer]::DrawText($g, $Text, $font, $rect, [System.Drawing.ColorTranslator]::FromHtml('#E9E9F2'), $flags)
        $font.Dispose(); $pen.Dispose(); $bg.Dispose(); $path.Dispose()
    } finally { $g.Dispose() }
    return $bmp
}

function New-WidgetIcon {
    param([int]$Size = 32)
    $bmp = New-WidgetBitmap -Size $Size
    try {
        $hIcon = $bmp.GetHicon()
        return [System.Drawing.Icon]::FromHandle($hIcon)
    } finally { $bmp.Dispose() }
}

# ---------------- 视图模型 ----------------
# 取当前标签页要显示的条目
function Get-UiShows {
    param($Ui)
    $all = @()
    if ($Ui.State -and $Ui.State.shows) { $all = @($Ui.State.shows) }
    if ($Ui.Tab -eq 'follow') {
        $list = @($all | Where-Object { $_.followed -and -not $_.isStreaming })
        return @($list | Sort-Object { $_.localWeekday }, { $_.timeLocal })
    }
    if ($Ui.Tab -eq 'stream') {
        return @($all | Where-Object { $_.isStreaming })
    }
    $day = $Ui.Day
    $list = @($all | Where-Object { -not $_.isStreaming -and $_.localWeekday -eq $day })
    return @($list | Sort-Object { $_.timeLocal })
}

# 平台名简短化，避免小组件里被截断
$script:PlatformShortNames = @{
    '巴哈姆特動畫瘋' = '巴哈姆特'
    'Muse木棉花'     = '木棉花'
    'Amazon Prime Video' = 'Prime Video'
    'friDay影音'     = 'friDay'
    'CATCHPLAY+'     = 'CATCHPLAY'
}

function Get-ShortPlatformName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return '' }
    if ($script:PlatformShortNames.ContainsKey($Name)) { return $script:PlatformShortNames[$Name] }
    return $Name
}

function Get-ShortTypeName {
    param([string]$Type)
    if ([string]::IsNullOrWhiteSpace($Type)) { return '' }
    $t = $Type -replace '动画$', ''
    switch -Regex ($t) {
        '^原创' { return '原创' }
        '^漫画' { return '漫画改' }
        '^小说' { return '小说改' }
        '^游戏' { return '游戏改' }
        '^韩漫' { return '韩漫改' }
        '^其他' { return '其他改' }
        default { return $t }
    }
}
function Get-PlatformText {
    param($Show, [int]$MaxCount = 2)
    $parts = New-Object System.Collections.ArrayList
    foreach ($p in @($Show.platforms)) {
        $n = Get-ShortPlatformName ([string](Get-Prop $p 'name' ''))
        if ($n -and -not $parts.Contains($n)) { [void]$parts.Add($n) }
        if ($parts.Count -ge $MaxCount) { break }
    }
    if ($parts.Count -eq 0 -and $Show.station) {
        $st = [string]$Show.station
        $st = ($st -split '[/／、]')[0].Trim()
        if ($st) { [void]$parts.Add($st) }
    }
    return ($parts -join ' · ')
}

function Measure-ChipWidth {
    param($G, [string]$Text, $Font, [int]$MaxWidth)
    if ([string]::IsNullOrWhiteSpace($Text)) { return 0 }
    $size = [System.Windows.Forms.TextRenderer]::MeasureText($Text, $Font)
    $w = $size.Width + 16
    if ($w -gt $MaxWidth) { $w = $MaxWidth }
    return $w
}

# ---------------- 主窗口 ----------------
function New-WidgetWindow {
    param($Config, $State)

    $theme = New-Theme -Config $Config
    $w = [int](Get-Prop $Config.ui 'width' 404)
    $h = Get-WidgetHeightForRows -Config $Config
    $fontFamily = [string](Get-Prop $Config.ui 'fontFamily' 'Microsoft YaHei UI')
    $rowsPerView = [int](Get-Prop $Config.ui 'rowsPerView' 3)
    $scale = Get-DpiScale

    # 小组件自绘字体用「像素」单位，配合绘制时的 ScaleTransform 做 DPI 清晰缩放
    $fonts = @{
        title  = New-FontPx -Family $fontFamily -SizePx 16 -Style ([System.Drawing.FontStyle]::Bold)
        sub    = New-FontPx -Family $fontFamily -SizePx 12
        tab    = New-FontPx -Family $fontFamily -SizePx 13
        tabSel = New-FontPx -Family $fontFamily -SizePx 13 -Style ([System.Drawing.FontStyle]::Bold)
        time   = New-FontPx -Family $fontFamily -SizePx 18 -Style ([System.Drawing.FontStyle]::Bold)
        timeS  = New-FontPx -Family $fontFamily -SizePx 12 -Style ([System.Drawing.FontStyle]::Bold)
        rowT   = New-FontPx -Family $fontFamily -SizePx 15 -Style ([System.Drawing.FontStyle]::Bold)
        rowS   = New-FontPx -Family $fontFamily -SizePx 12
        small  = New-FontPx -Family $fontFamily -SizePx 11
        btn    = New-FontPx -Family $fontFamily -SizePx 12.5
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = '新番桌面小组件'
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
    $form.Size = New-Object System.Drawing.Size([int]($w * $scale), [int]($h * $scale))
    $form.BackColor = $theme.bg
    $form.ForeColor = $theme.text
    $form.ShowInTaskbar = $false
    $form.TopMost = [bool](Get-Prop $Config.ui 'topMost' $true)
    $form.Opacity = [double](Get-Prop $Config.ui 'opacity' 1.0)
    $form.MinimumSize = New-Object System.Drawing.Size([int](300 * $scale), [int](300 * $scale))
    try { $form.Icon = (New-WidgetIcon -Size 32) } catch { }
    Set-DoubleBuffered -Control $form -On $true

    $path = New-RoundedPath -Rect (New-Object System.Drawing.Rectangle(0, 0, [int]($w * $scale), [int]($h * $scale))) -Radius ([int](14 * $scale))
    $form.Region = New-Object System.Drawing.Region($path)

    # 记住位置
    $posFile = Join-Path (Get-DataDir) 'window.json'
    $pos = Read-JsonFile $posFile
    if ($pos -and (Get-Prop $Config.ui 'rememberPosition' $true)) {
        try {
            $x = [int]$pos.x; $y = [int]$pos.y
            $screen = [System.Windows.Forms.Screen]::FromPoint((New-Object System.Drawing.Point($x, $y)))
            if ($screen -and $screen.Bounds.Contains((New-Object System.Drawing.Point($x, $y)))) {
                $form.Location = New-Object System.Drawing.Point($x, $y)
            } else {
                $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
                $form.Location = New-Object System.Drawing.Point(($wa.Right - [int]($w * $scale) - 24), ($wa.Top + 80))
            }
        } catch { $form.Location = New-Object System.Drawing.Point(1200, 80) }
    } else {
        $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
        $form.Location = New-Object System.Drawing.Point(($wa.Right - [int]($w * $scale) - 24), ($wa.Top + 80))
    }

    # 恢复上次尺寸（顺序必须在读取 window.json 之后；window.json 存的是逻辑尺寸）
    if ($pos -and (Get-Prop $Config.ui 'rememberSize' $true)) {
        try {
            $sw2 = [int](Get-Prop $pos 'w' $w); $sh2 = [int](Get-Prop $pos 'h' $h)
            if ($sw2 -ge 300 -and $sh2 -gt $h) {
                $w = $sw2; $h = $sh2
                $form.Size = New-Object System.Drawing.Size([int]($w * $scale), [int]($h * $scale))
                $rp = New-RoundedPath -Rect (New-Object System.Drawing.Rectangle(0, 0, [int]($w * $scale) - 1, [int]($h * $scale) - 1)) -Radius ([int](14 * $scale))
                $form.Region = New-Object System.Drawing.Region($rp)
            }
        } catch { }
    }

    # 状态容器
    $ui = @{
        Config    = $Config
        Theme     = $theme
        Fonts     = $fonts
        State     = $State
        Day       = (Get-WeekdayIndex (Get-Date))
        Tab       = 'day'
        ScrollY   = 0
        HoverRow  = -1
        HoverBtn  = -1
        HoverTab  = -1
        Regions   = @()
        Refreshing = $false
        StatusText = ''
        LastError = ''
        Ps        = $null
        Handle    = $null
        Runspace  = $null
        Dragging  = $false
        DragStart = $null
        Resizing  = $false
        ResizeStart = $null
        Notify    = $null
        RowHeight = 76
        RowsPerView = $rowsPerView
        DpiScale  = $scale
        LogicalWidth  = $w
        LogicalHeight = $h
        TabsFile  = $posFile
    }
    $ui.Form = $form
    $script:Ui = $ui

    # 绘制入口（真实运行与离屏渲染共用同一函数）
    $form.Add_Paint({
            param($sender, $e)
            try {
                Update-UiRegions -Ui $script:Ui
                Update-WidgetScrollBounds -Ui $script:Ui
                Draw-Widget -G $e.Graphics -Ui $script:Ui
            } catch {
                Write-Log "绘制异常：$($_.Exception.Message) @ $($_.ScriptStackTrace)" 'ERROR'
            }
        })

    return @{ Form = $form; Ui = $ui; Theme = $theme; Fonts = $fonts }
}

function Get-WidgetLayout {
    param($Ui)
    $w = $Ui.LogicalWidth
    $h = $Ui.LogicalHeight
    if (-not $w) { $w = 404 }
    if (-not $h) { $h = 348 }
    $headerH = 46
    $tabsH = 34
    $footerH = 32
    return @{
        Width    = $w
        Height   = $h
        Header   = (New-Object System.Drawing.Rectangle(0, 0, $w, $headerH))
        Tabs     = (New-Object System.Drawing.Rectangle(0, $headerH, $w, $tabsH))
        List     = (New-Object System.Drawing.Rectangle(0, ($headerH + $tabsH), $w, ($h - $headerH - $tabsH - $footerH)))
        Footer   = (New-Object System.Drawing.Rectangle(0, ($h - $footerH), $w, $footerH))
        HeaderH  = $headerH
        TabsH    = $tabsH
        FooterH  = $footerH
    }
}

# 计算当前布局下的命中区域（按钮 / 标签 / 行）
function Update-UiRegions {
    param($Ui)
    $layout = Get-WidgetLayout -Ui $Ui
    $regions = New-Object System.Collections.ArrayList

    # 顶部按钮
    $buttons = @(
        @{ name = 'refresh'; text = '刷新' },
        @{ name = 'follow';  text = '追番' },
        @{ name = 'settings'; text = '设置' },
        @{ name = 'minimize'; text = '—' },
        @{ name = 'close';   text = '×' }
    )
    $bw = 46; $bh = 22; $gap = 6
    $right = $layout.Width - 10
    $reversed = @($buttons[($buttons.Count - 1)..0])
    $xs = @{}
    foreach ($b in $reversed) {
        $width = $(if ($b.name -eq 'close' -or $b.name -eq 'minimize') { 24 } else { $bw })
        $rect = New-Object System.Drawing.Rectangle(($right - $width), 12, $width, $bh)
        $xs[$b.name] = $rect
        [void]$regions.Add(@{ kind = 'button'; name = $b.name; rect = $rect })
        $right = $right - $width - $gap
    }

    # 星期标签：一…日 + 追番 + 网络放送
    $count = 9
    $tabW = [int](($layout.Width - 20) / $count)
    for ($i = 0; $i -lt 7; $i++) {
        $x = 10 + ($i * $tabW)
        $rect = New-Object System.Drawing.Rectangle($x, ($layout.Tabs.Y + 5), ($tabW - 3), ($layout.TabsH - 10))
        [void]$regions.Add(@{ kind = 'tab'; name = 'day'; day = $i; rect = $rect })
    }
    $x8 = 10 + (7 * $tabW)
    [void]$regions.Add(@{ kind = 'tab'; name = 'follow'; day = -1; rect = (New-Object System.Drawing.Rectangle($x8, ($layout.Tabs.Y + 5), ($tabW - 3), ($layout.TabsH - 10))) })
    $x9 = 10 + (8 * $tabW)
    [void]$regions.Add(@{ kind = 'tab'; name = 'stream'; day = -2; rect = (New-Object System.Drawing.Rectangle($x9, ($layout.Tabs.Y + 5), ($tabW - 3), ($layout.TabsH - 10))) })

    # 列表行
    $shows = @(Get-UiShows -Ui $Ui)
    $rowH = [int]$Ui.RowHeight
    $y = $layout.List.Y + 4 - [int]$Ui.ScrollY
    for ($i = 0; $i -lt $shows.Count; $i++) {
        $rect = New-Object System.Drawing.Rectangle(6, $y, ($layout.Width - 12), ($rowH - 4))
        [void]$regions.Add(@{ kind = 'row'; index = $i; show = $shows[$i]; rect = $rect })
        $y += $rowH
    }

    $Ui.Regions = $regions.ToArray()
    $Ui.Layout = $layout
    $Ui.VisibleShows = $shows
}

# ---------------- 绘制 ----------------
# 绘制顺序（关键）：
#   1) 背景 -> 2) 列表行（裁剪在列表区）-> 3) 滚动条
#   -> 4) 顶部栏/页签条/底部栏（实心面板，最后绘制，彻底覆盖任何越界像素）
# 这样滚屏时行的内容永远不会出现在上/下栏里，也不会出现“透明栏”。
function Draw-Widget {
    param($G, $Ui)
    $theme = $Ui.Theme
    $fonts = $Ui.Fonts
    $layout = $Ui.Layout
    $w = $layout.Width
    $h = $layout.Height
    $state = $Ui.State

    # DPI 缩放：所有逻辑坐标（96dpi 基准）经 transform 映射到物理像素，字体用像素单位，整体清晰锐利
    $scale = [double]$Ui.DpiScale
    if (-not $scale -or $scale -le 0) { $scale = 1.0 }
    $G.ScaleTransform($scale, $scale)

    $G.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $G.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

    # ---------- 1. 整窗背景 ----------
    $bgBrush = New-Object System.Drawing.SolidBrush($theme.bg)
    $G.FillRectangle($bgBrush, 0, 0, $w, $h)
    $bgBrush.Dispose()

    # ---------- 2. 列表行（先画，严格裁剪在列表区内） ----------
    $shows = @($Ui.VisibleShows)
    $todayWd = Get-WeekdayIndex (Get-Date)
    if ($shows.Count -eq 0) {
        $msg = '今天没有新番播出'
        if ($Ui.Refreshing -and -not $state) { $msg = '首次抓取中，请稍候…（可能需 1~2 分钟）' }
        elseif ($Ui.Tab -eq 'follow') { $msg = '还没有在追的新番（设置里登录 Bangumi 后自动标注）' }
        elseif ($Ui.Tab -eq 'stream') { $msg = '没有网络放送条目' }
        Draw-TextBlock -G $G -Text $msg -Font $fonts.sub -Color $theme.dim -Rect (New-Object System.Drawing.Rectangle(16, ($layout.List.Y + 40), ($w - 32), 40)) -Align 'Center' -Ellipsis $false
    } else {
        $listClip = $layout.List
        $listClip.Y -= 6
        $listClip.Height += 12   # 留 6px 余量，行内渐变/圆角不贴边生硬
        foreach ($r in $Ui.Regions) {
            if ($r.kind -ne 'row') { continue }
            $rect = $r.rect
            if ($rect.Bottom -lt $layout.List.Y - 4 -or $rect.Y -gt $layout.List.Bottom + 4) { continue }
            Draw-ShowRow -G $G -Ui $Ui -Show $r.show -Rect $rect -Hover ($Ui.HoverRow -eq $r.index) -Clip $listClip
        }
    }

    # ---------- 3. 滚动指示条 ----------
    if ($Ui.MaxScroll -gt 0) {
        $listH = $layout.List.Height
        $contentH = ($shows.Count * [int]$Ui.RowHeight) + 8
        $barH = [math]::Max(28, [int]($listH * ($listH / [double]$contentH)))
        $barY = $layout.List.Y + [int](($listH - $barH) * ($Ui.ScrollY / [double]$Ui.MaxScroll))
        Fill-RoundedRect -G $G -Rect (New-Object System.Drawing.Rectangle(($w - 5), $barY, 3, $barH)) -Color $theme.chipBg -Radius 1
    }

    # ---------- 4. 顶部栏（实心面板，覆盖行上方任何残留） ----------
    $panelBrush = New-Object System.Drawing.SolidBrush($theme.panel)
    $G.FillRectangle($panelBrush, 0, 0, $w, $layout.Header.Bottom)

    $titleText = '今日新番'
    if ($Ui.Tab -eq 'follow') { $titleText = '我的追番' }
    elseif ($Ui.Tab -eq 'stream') { $titleText = '网络放送' }
    elseif ($Ui.Day -ne $todayWd) { $titleText = (Get-WeekdayName $Ui.Day) + '新番' }
    Draw-TextBlock -G $G -Text $titleText -Font $fonts.title -Color $theme.text -Rect (New-Object System.Drawing.Rectangle(12, 8, 150, 22)) -Align 'Near'

    $dateText = Format-DateCn (Get-Date)
    Draw-TextBlock -G $G -Text $dateText -Font $fonts.sub -Color $theme.sub -Rect (New-Object System.Drawing.Rectangle(12, 27, 200, 16))

    foreach ($r in $Ui.Regions) {
        if ($r.kind -ne 'button') { continue }
        $hover = ($Ui.HoverBtn -eq $r.name)
        $isClose = ($r.name -eq 'close')
        $isIcon = ($r.name -eq 'close' -or $r.name -eq 'minimize')
        if ($hover) {
            $bgc = $(if ($isClose) { $theme.warn } else { $theme.chipBg })
            Fill-RoundedRect -G $G -Rect $r.rect -Color $bgc -Radius 7
        }
        $fg = $(if ($hover) { $theme.text } else { $theme.sub })
        $font = $(if ($isIcon) { $fonts.title } else { $fonts.btn })
        $text = ''
        switch ($r.name) {
            'refresh' { $text = $(if ($Ui.Refreshing) { '…' } else { '刷新' }) }
            'follow' { $text = '追番' }
            'settings' { $text = '设置' }
            'minimize' { $text = '—' }
            'close' { $text = '×' }
        }
        Draw-TextBlock -G $G -Text $text -Font $font -Color $fg -Rect $r.rect -Align 'Center'
    }

    # ---------- 5. 页签条（实心背景条 + 页签） ----------
    $bgBrush2 = New-Object System.Drawing.SolidBrush($theme.bg)
    $G.FillRectangle($bgBrush2, 0, $layout.Header.Bottom, $w, $layout.TabsH)
    $bgBrush2.Dispose()
    $showsAll = @()
    if ($state -and $state.shows) { $showsAll = @($state.shows) }
    foreach ($r in $Ui.Regions) {
        if ($r.kind -ne 'tab') { continue }
        if ($null -eq $r.rect) { continue }
        $selected = $false
        $label = ''
        $badge = ''
        if ($r.name -eq 'day') {
            $selected = ($Ui.Tab -eq 'day' -and $Ui.Day -eq $r.day)
            $label = $script:WeekdayShort[$r.day]
            $badge = @($showsAll | Where-Object { -not $_.isStreaming -and $_.localWeekday -eq $r.day }).Count
            if ($r.day -eq $todayWd -and -not $selected) { $label = $label + '·' }
        } elseif ($r.name -eq 'follow') {
            $selected = ($Ui.Tab -eq 'follow')
            $label = '追'
            $badge = @($showsAll | Where-Object { $_.followed -and -not $_.isStreaming }).Count
        } else {
            $selected = ($Ui.Tab -eq 'stream')
            $label = '网播'
            $badge = @($showsAll | Where-Object { $_.isStreaming }).Count
        }
        if ($selected) {
            Fill-RoundedRect -G $G -Rect $r.rect -Color $theme.chipBg2 -Radius 8
        } elseif ($Ui.HoverTab -eq $r.name) {
            Fill-RoundedRect -G $G -Rect $r.rect -Color $theme.rowHover -Radius 8
        }
        $fg = $(if ($selected) { $theme.accent } else { $theme.sub })
        $fnt = $(if ($selected) { $fonts.tabSel } else { $fonts.tab })
        $txt = $label
        if ($badge -gt 0 -and $r.name -eq 'follow') { $txt = '★' + $badge }
        elseif ($badge -gt 0 -and $r.name -eq 'stream') { $txt = '网播' + $badge }
        Draw-TextBlock -G $G -Text $txt -Font $fnt -Color $fg -Rect $r.rect -Align 'Center'
    }

    # ---------- 6. 底部栏（实心面板） ----------
    $G.FillRectangle($panelBrush, 0, $layout.Footer.Y, $w, $layout.FooterH)
    $dayShows = @($shows | Where-Object { -not $_.isStreaming })
    $followedCount = @($showsAll | Where-Object { $_.followed }).Count
    $leftText = ''
    if ($Ui.Tab -eq 'follow') { $leftText = ('在追 ' + $dayShows.Count + ' 部') }
    elseif ($Ui.Tab -eq 'stream') { $leftText = ('网络放送 ' + $dayShows.Count + ' 部') }
    else { $leftText = ((Get-WeekdayName $Ui.Day) + ' 共 ' + $dayShows.Count + ' 部') }
    if ($followedCount -gt 0) { $leftText += (' · ★' + $followedCount) }
    Draw-TextBlock -G $G -Text $leftText -Font $fonts.small -Color $theme.sub -Rect (New-Object System.Drawing.Rectangle(12, ($layout.Footer.Y + 7), 180, 18))

    $rightText = ''
    if ($Ui.Refreshing) { $rightText = '正在刷新…' }
    else {
        $next = Get-NextShow -Shows $showsAll
        if ($next -and (Get-Prop $Ui.Config.data 'showNextUp' $true) -and $next.minutes -le 720) {
            $mins = $next.minutes
            $when = $(if ($mins -lt 60) { "$mins 分钟后" } else { ('{0} 小时 {1} 分后' -f [int]($mins / 60), ($mins % 60)) })
            $rightText = ('下一部 {0} {1}' -f $next.show.timeLocal, $when)
        } elseif ($state -and $state.builtAt) {
            try { $rightText = '更新于 ' + ([datetime]$state.builtAt).ToString('MM-dd HH:mm') } catch { $rightText = '' }
        }
    }
    $rightColor = $(if ($Ui.Refreshing) { $theme.accent } else { $theme.sub })
    Draw-TextBlock -G $G -Text $rightText -Font $fonts.small -Color $rightColor -Rect (New-Object System.Drawing.Rectangle(($w - 232), ($layout.Footer.Y + 7), 220, 18)) -Align 'Far'

    $panelBrush.Dispose()

    # ---------- 7. 分隔线与外框（最后画，保证边缘完整） ----------
    $penLine = New-Object System.Drawing.Pen($theme.line, 1)
    $G.DrawLine($penLine, 0, $layout.Header.Bottom, $w, $layout.Header.Bottom)
    $G.DrawLine($penLine, 0, $layout.Tabs.Bottom, $w, $layout.Tabs.Bottom)
    $G.DrawLine($penLine, 0, $layout.Footer.Y, $w, $layout.Footer.Y)
    $path = New-RoundedPath -Rect (New-Object System.Drawing.Rectangle(0, 0, ($w - 1), ($h - 1))) -Radius 14
    $G.DrawPath($penLine, $path)
    $penLine.Dispose(); $path.Dispose()

    # ---------- 8. 右下角缩放提示 ----------
    $G.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None
    $grip = New-Object System.Drawing.Pen($theme.dim, 1)
    for ($i = 0; $i -lt 3; $i++) {
        $off = $i * 4
        $G.DrawLine($grip, ($w - 8 - $off), ($h - 4), ($w - 4), ($h - 8 - $off))
    }
    $grip.Dispose()
}
function Draw-ShowRow {
    param($G, $Ui, $Show, [System.Drawing.Rectangle]$Rect, [bool]$Hover, [System.Drawing.Rectangle]$Clip)
    $theme = $Ui.Theme
    $fonts = $Ui.Fonts
    $x = $Rect.X
    $y = $Rect.Y
    $wid = $Rect.Width
    $hei = $Rect.Height

    # 关键：所有行内绘制（含分隔线）都在列表区域内裁剪，滚屏时才不会压到标题栏/页签
    $gs = $G.Save()
    $G.SetClip($Clip)
    try {
        if ($Hover) {
            Fill-RoundedRect -G $G -Rect $Rect -Color $theme.rowHover -Radius 10
        }

        # ---- 左侧：北京时间 / 日本时间 / 在追 ----
        $timeRect = New-Object System.Drawing.Rectangle(($x + 8), ($y + 10), 68, 22)
        $todayWd = Get-WeekdayIndex (Get-Date)
        $timeColor = $(if ($Show.localWeekday -eq $todayWd) { $theme.accent } else { $theme.text })
        if ($Show.isStreaming) {
            Draw-TextBlock -G $G -Text '网' -Font $fonts.time -Color $theme.accent -Rect $timeRect -Align 'Near'
            Draw-TextBlock -G $G -Text '放送' -Font $fonts.small -Color $theme.dim -Rect (New-Object System.Drawing.Rectangle(($x + 32), ($y + 16), 40, 16))
        } else {
            $timeText = $(if ($Show.timeLocal) { $Show.timeLocal } else { '--:--' })
            Draw-TextBlock -G $G -Text $timeText -Font $fonts.time -Color $timeColor -Rect $timeRect -Align 'Near' -Ellipsis $false
            $sub = ''
            if ($Ui.Config.data.showJstTime -and $Show.timeJst) { $sub = ('JST ' + (Format-JstTimeDisplay $Show.timeJst)) }
            Draw-TextBlock -G $G -Text $sub -Font $fonts.small -Color $theme.dim -Rect (New-Object System.Drawing.Rectangle(($x + 8), ($y + 32), 74, 14))
            if ($Show.followed) {
                Draw-TextBlock -G $G -Text '★ 在追' -Font $fonts.small -Color $theme.star -Rect (New-Object System.Drawing.Rectangle(($x + 8), ($y + 50), 46, 15)) -Align 'Near' -Ellipsis $false
            }
        }

        # ---- 右侧：平台 / 评分与类型 / 首播或话数 ----
        $rightW = 96
        $rightX = $x + $wid - $rightW - 6
        $chipText = Get-PlatformText -Show $Show -MaxCount 2
        if ($chipText) {
            $chipW = Measure-ChipWidth -G $G -Text $chipText -Font $fonts.small -MaxWidth $rightW
            Draw-Chip -G $G -Rect (New-Object System.Drawing.Rectangle($rightX, ($y + 8), $chipW, 18)) -Text $chipText -Font $fonts.small -Theme $theme -Accent $true
        }
        $metaText = ''
        if ($Show.score -gt 0) { $metaText = ('★ ' + ('{0:N1}' -f $Show.score)) }
        $shortType = Get-ShortTypeName ([string]$Show.type)
        if ($shortType) {
            if ($metaText) { $metaText += ' · ' }
            $metaText += $shortType
        }
        $metaColor = $(if ($Show.followed) { $theme.star } else { $theme.dim })
        Draw-TextBlock -G $G -Text $metaText -Font $fonts.small -Color $metaColor -Rect (New-Object System.Drawing.Rectangle($rightX, ($y + 30), $rightW, 16)) -Align 'Far'

        $premiereText = ''
        if ($Show.epNote) { $premiereText = [string]$Show.epNote }
        elseif ($Show.firstAirLocal) {
            try {
                $fa = [datetime]::Parse($Show.firstAirLocal)
                $today = (Get-Date).Date
                if ($fa -gt $today) { $premiereText = ('首播 ' + $fa.ToString('M/d')) }
            } catch { }
        }
        if ($premiereText) {
            Draw-TextBlock -G $G -Text $premiereText -Font $fonts.small -Color $theme.dim -Rect (New-Object System.Drawing.Rectangle($rightX, ($y + 50), $rightW, 14)) -Align 'Far'
        }

        # ---- 中部三行：中文名 / 日文名 / 标签 ----
        $textX = $x + 80
        $textW = $rightX - $textX - 8
        if ($textW -lt 60) { $textW = 60 }

        Draw-TextBlock -G $G -Text $Show.title -Font $fonts.rowT -Color $theme.text -Rect (New-Object System.Drawing.Rectangle($textX, ($y + 8), $textW, 19))

        # 日文名始终显示
        if ($Show.titleJp -and ($Show.titleJp -ne $Show.title)) {
            Draw-TextBlock -G $G -Text $Show.titleJp -Font $fonts.rowS -Color $theme.sub -Rect (New-Object System.Drawing.Rectangle($textX, ($y + 26), $textW, 17))
        }

        $tagText = ''
        if (@($Show.tags).Count -gt 0) { $tagText = (@($Show.tags) | Select-Object -First 4) -join ' · ' }
        if ($Ui.Tab -eq 'follow' -and $Show.localWeekday -ge 0) {
            $tagText = ((Get-WeekdayName $Show.localWeekday) + ' · ' + $tagText).TrimEnd(' ·')
        }
        if (-not $tagText) { $tagText = [string]$Show.type }
        Draw-TextBlock -G $G -Text $tagText -Font $fonts.small -Color $theme.dim -Rect (New-Object System.Drawing.Rectangle($textX, ($y + 45), $textW, 16))

        # 行分隔线（画在裁剪区内）
        $pen = New-Object System.Drawing.Pen($theme.line, 1)
        $G.DrawLine($pen, ($x + 8), ($Rect.Bottom - 1), ($Rect.Right - 8), ($Rect.Bottom - 1))
        $pen.Dispose()
    } finally {
        $G.Restore($gs)
    }
}