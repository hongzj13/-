# UiDialogs.ps1 -- 详情 / 设置 / 登录 对话框
# 目标运行时：Windows PowerShell 5.1

function New-DialogForm {
    param([string]$Title, [int]$Width = 420, [int]$Height = 520, $Config)
    $theme = New-Theme -Config $Config
    $form = New-Object System.Windows.Forms.Form
    $form.Text = $Title
    $form.Size = New-Object System.Drawing.Size($Width, $Height)
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.TopMost = $true
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#1E1E27')
    $form.ForeColor = $theme.text
    $form.Font = New-FontSafe -Family (Get-Prop $Config.ui 'fontFamily' 'Microsoft YaHei UI') -Size 9.5
    try { $form.Icon = New-WidgetIcon -Size 32 } catch { }
    return $form
}

function New-DialogLabel {
    param([string]$Text, [int]$X, [int]$Y, [int]$W, [int]$H = 20, [bool]$Bold = $false, [string]$Color = '#C8C8D6')
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $Text
    $lbl.Location = New-Object System.Drawing.Point($X, $Y)
    $lbl.Size = New-Object System.Drawing.Size($W, $H)
    $lbl.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($Color)
    if ($Bold) { $lbl.Font = New-FontSafe -Family 'Microsoft YaHei UI' -Size 10 -Style ([System.Drawing.FontStyle]::Bold) }
    return $lbl
}

function New-DialogButton {
    param([string]$Text, [int]$X, [int]$Y, [int]$W = 90, [int]$H = 30, [bool]$Primary = $false)
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $Text
    $btn.Location = New-Object System.Drawing.Point($X, $Y)
    $btn.Size = New-Object System.Drawing.Size($W, $H)
    $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btn.FlatAppearance.BorderSize = 0
    $btn.BackColor = $(if ($Primary) { [System.Drawing.ColorTranslator]::FromHtml('#3E5088') } else { [System.Drawing.ColorTranslator]::FromHtml('#2A2A38') })
    $btn.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#E9E9F2')
    $btn.FlatAppearance.MouseOverBackColor = [System.Drawing.ColorTranslator]::FromHtml('#39406A')
    return $btn
}

# 对话框离屏渲染（自检用）
function Render-DialogToFile {
    param($Form, [string]$Path)
    # 子控件需要真实句柄才能被 DrawToBitmap 绘制：以透明度 0 短暂显示一次
    try {
        $Form.ShowInTaskbar = $false
        $Form.Opacity = 0
        $Form.Show()
        [System.Windows.Forms.Application]::DoEvents()
        $Form.Refresh()
        [System.Windows.Forms.Application]::DoEvents()
    } catch { }
    $bmp = New-Object System.Drawing.Bitmap($Form.Width, $Form.Height)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try { $g.Clear([System.Drawing.ColorTranslator]::FromHtml('#3A3A44')) } finally { $g.Dispose() }
    try { $Form.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0, 0, $Form.Width, $Form.Height))) } catch { }
    $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    try { $Form.Hide() } catch { }
}
# ---------------- 详情 ----------------
# 模态显示：以小组件窗口为 Owner（置顶小组件上弹置顶对话框）
function Show-Modal {
    param($Form)
    $owner = $null
    if ($script:Ui -and $script:Ui.Form -and $script:Ui.Form.IsHandleCreated) { $owner = $script:Ui.Form }
    if ($owner) { $Form.ShowDialog($owner) | Out-Null } else { $Form.ShowDialog() | Out-Null }
}
function Show-DetailsDialog {
    param($Show, $Config, [string]$RenderTo = '')
    $form = New-DialogForm -Title '条目详情' -Width 500 -Height 560 -Config $Config
    $theme = New-Theme -Config $Config

    $pf = @()
    if ($Show.station) { $pf += ('日本：' + $Show.station) }
    foreach ($p in @($Show.platforms)) { $pf += ([string]$p.name + $(if ($p.region) { "（$($p.region)）" } else { '' })) }

    $lines = New-Object System.Collections.ArrayList
    [void]$lines.Add('【播出时间】')
    [void]$lines.Add(('北京时间：{0}（{1}）  日本时间：{2}' -f $Show.timeLocal, (Get-WeekdayName $Show.localWeekday), $(if ($Show.timeJst) { (Format-JstTimeDisplay $Show.timeJst) } else { '未知' })))
    if ($Show.firstAir -or $Show.firstAirLocal) { [void]$lines.Add(('首播：{0}（北京时间 {1}）' -f $Show.firstAir, $Show.firstAirLocal)) }
    if ($Show.epNote) { [void]$lines.Add(('话数：' + $Show.epNote)) }
    if ($Show.streamNote) { [void]$lines.Add(('放送：' + $Show.streamNote)) }
    [void]$lines.Add('')
    [void]$lines.Add('【作品信息】')
    [void]$lines.Add(('日文名：' + $(if ($Show.titleJp) { $Show.titleJp } else { '—' })))
    [void]$lines.Add(('改编类型：' + $(if ($Show.type) { $Show.type } else { '—' })))
    [void]$lines.Add(('标签：' + $(if ($Show.tags.Count -gt 0) { (@($Show.tags) -join ' / ') } else { '—' })))
    [void]$lines.Add(('Bangumi 评分：' + $(if ($Show.score -gt 0) { '{0:N1}' -f $Show.score } else { '暂无' })))
    [void]$lines.Add(('放送平台：' + $(if ($pf.Count -gt 0) { ($pf -join '、') } else { '未标注' })))
    if ($Show.followed) { [void]$lines.Add('状态：★ 我的在看') }
    [void]$lines.Add('')
    [void]$lines.Add('【制作】')
    [void]$lines.Add($(if ($Show.staff) { $Show.staff } else { '—' }))
    [void]$lines.Add('')
    [void]$lines.Add('【声优】')
    [void]$lines.Add($(if ($Show.cast) { $Show.cast } else { '—' }))

    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Multiline = $true
    $txt.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $txt.ReadOnly = $true
    $txt.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#17171E')
    $txt.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#D8D8E4')
    $txt.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $txt.Location = New-Object System.Drawing.Point(14, 52)
    $txt.Size = New-Object System.Drawing.Size(462, 410)
    $txt.Text = ($lines -join "`r`n")

    $form.Controls.Add((New-DialogLabel -Text $Show.title -X 14 -Y 12 -W 462 -H 26 -Bold $true -Color '#FFFFFF'))
    $form.Controls.Add($txt)

    $btnBgm = New-DialogButton -Text '打开 Bangumi' -X 14 -Y 474 -W 110
    $btnSite = New-DialogButton -Text '打开官网' -X 132 -Y 474 -W 100
    $btnFollow = New-DialogButton -Text '加入我的在看' -X 240 -Y 474 -W 120
    $btnClose = New-DialogButton -Text '关闭' -X 376 -Y 474 -W 100 -Primary $true
    $btnBgm.Enabled = ($Show.bgmId -gt 0)
    $btnSite.Enabled = -not [string]::IsNullOrWhiteSpace($Show.site)
    $btnBgm.add_Click({ if ($Show.bgmId -gt 0) { Open-Url ('https://bgm.tv/subject/' + $Show.bgmId) } })
    $btnSite.add_Click({ if ($Show.site) { Open-Url $Show.site } })
    $btnFollow.add_Click({
            $auth = Get-BangumiAuth
            if (-not $auth.accessToken) {
                [System.Windows.Forms.MessageBox]::Show('请先登录 Bangumi（设置 → Bangumi 登录）。', '未登录') | Out-Null
                return
            }
            if ($Show.bgmId -le 0) {
                [System.Windows.Forms.MessageBox]::Show('该条目还没有关联 Bangumi 条目。', '无法加入') | Out-Null
                return
            }
            $r = Add-BangumiCollection -SubjectId $Show.bgmId -Token $auth.accessToken -Config $Config -Type 3
            if ($r.ok) {
                $Show.followed = $true
                [System.Windows.Forms.MessageBox]::Show('已加入在看。', '成功') | Out-Null
            } else {
                [System.Windows.Forms.MessageBox]::Show(("失败：{0}" -f $r.error), '失败') | Out-Null
            }
        })
    $btnClose.add_Click({ $form.Close() })
    $form.Controls.AddRange(@($btnBgm, $btnSite, $btnFollow, $btnClose))

    if ($RenderTo) { Render-DialogToFile -Form $form -Path $RenderTo; $form.Dispose(); return }
    Show-Modal -Form $form
    $form.Dispose()
}

# ---------------- 设置 ----------------
function Show-SettingsDialog {
    param($Config, [scriptblock]$OnSaved, [string]$RenderTo = '')
    $form = New-DialogForm -Title '新番小组件 · 设置' -Width 470 -Height 728 -Config $Config

    $y = 14
    $form.Controls.Add((New-DialogLabel -Text '数据源' -X 16 -Y $y -W 200 -H 22 -Bold $true))
    $y += 26
    $cbYuc = New-Object System.Windows.Forms.CheckBox
    $cbYuc.Text = 'yuc.wiki（長門番堂）新番表 —— 播出时间 / 标签 / 版权平台'
    $cbYuc.Location = New-Object System.Drawing.Point(20, $y)
    $cbYuc.Size = New-Object System.Drawing.Size(430, 22)
    $cbYuc.Checked = [bool](Get-Prop $Config.data 'useYuc' $true)
    $cbYuc.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#C8C8D6')
    $form.Controls.Add($cbYuc); $y += 26
    $cbBgm = New-Object System.Windows.Forms.CheckBox
    $cbBgm.Text = 'Bangumi —— 中文名 / 评分 / 放送电视台 / 我的在看'
    $cbBgm.Location = New-Object System.Drawing.Point(20, $y)
    $cbBgm.Size = New-Object System.Drawing.Size(430, 22)
    $cbBgm.Checked = [bool](Get-Prop $Config.data 'useBangumi' $true)
    $cbBgm.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#C8C8D6')
    $form.Controls.Add($cbBgm); $y += 32

    $form.Controls.Add((New-DialogLabel -Text '网络' -X 16 -Y $y -W 200 -H 22 -Bold $true)); $y += 26
    $form.Controls.Add((New-DialogLabel -Text '代理模式' -X 20 -Y ($y + 3) -W 70))
    $cbProxy = New-Object System.Windows.Forms.ComboBox
    $cbProxy.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $cbProxy.Location = New-Object System.Drawing.Point(92, $y)
    $cbProxy.Size = New-Object System.Drawing.Size(120, 24)
    [void]$cbProxy.Items.AddRange(@('自动（推荐）', '直连', '系统代理', '自定义代理'))
    $modeMap = @{ 'auto' = 0; 'direct' = 1; 'system' = 2; 'custom' = 3 }
    $mode = [string](Get-Prop $Config.network 'proxyMode' 'auto')
    $cbProxy.SelectedIndex = $(if ($modeMap.ContainsKey($mode)) { $modeMap[$mode] } else { 0 })
    $form.Controls.Add($cbProxy)
    $txtProxy = New-Object System.Windows.Forms.TextBox
    $txtProxy.Location = New-Object System.Drawing.Point(220, $y)
    $txtProxy.Size = New-Object System.Drawing.Size(230, 24)
    $txtProxy.Text = [string](Get-Prop $Config.network 'proxyUrl' 'http://127.0.0.1:7897')
    $txtProxy.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#17171E')
    $txtProxy.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#D8D8E4')
    $txtProxy.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $form.Controls.Add($txtProxy); $y += 30
    $form.Controls.Add((New-DialogLabel -Text '（Bangumi API 在国内常需代理；yuc.wiki 一般可直连）' -X 92 -Y $y -W 360 -H 18 -Color '#8A8A9E')); $y += 24
    $cbTls = New-Object System.Windows.Forms.CheckBox
    $cbTls.Text = '忽略 HTTPS 证书错误（代理中间人 / 自签证书时勾选）'
    $cbTls.Location = New-Object System.Drawing.Point(20, $y)
    $cbTls.Size = New-Object System.Drawing.Size(430, 22)
    $cbTls.Checked = [bool](Get-Prop $Config.network 'allowInsecureTls' $true)
    $cbTls.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#C8C8D6')
    $form.Controls.Add($cbTls); $y += 32

    $form.Controls.Add((New-DialogLabel -Text '显示与刷新' -X 16 -Y $y -W 200 -H 22 -Bold $true)); $y += 26
    $cbTop = New-Object System.Windows.Forms.CheckBox
    $cbTop.Text = '窗口置顶'
    $cbTop.Location = New-Object System.Drawing.Point(20, $y)
    $cbTop.Size = New-Object System.Drawing.Size(110, 22)
    $cbTop.Checked = [bool](Get-Prop $Config.ui 'topMost' $true)
    $cbTop.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#C8C8D6')
    $form.Controls.Add($cbTop)
    $form.Controls.Add((New-DialogLabel -Text '不透明度' -X 150 -Y ($y + 3) -W 60))
    $numOpacity = New-Object System.Windows.Forms.NumericUpDown
    $numOpacity.Location = New-Object System.Drawing.Point(212, $y)
    $numOpacity.Size = New-Object System.Drawing.Size(60, 24)
    $numOpacity.DecimalPlaces = 2
    $numOpacity.Increment = 0.05
    $numOpacity.Minimum = 0.3
    $numOpacity.Maximum = 1.0
    $numOpacity.Value = [decimal](Get-Prop $Config.ui 'opacity' 0.96)
    $form.Controls.Add($numOpacity)
    $form.Controls.Add((New-DialogLabel -Text '刷新间隔(小时)' -X 286 -Y ($y + 3) -W 90))
    $numRefresh = New-Object System.Windows.Forms.NumericUpDown
    $numRefresh.Location = New-Object System.Drawing.Point(382, $y)
    $numRefresh.Size = New-Object System.Drawing.Size(60, 24)
    $numRefresh.Minimum = 1
    $numRefresh.Maximum = 48
    $numRefresh.Value = [decimal](Get-Prop $Config.data 'refreshHours' 6)
    $form.Controls.Add($numRefresh); $y += 28
    $form.Controls.Add((New-DialogLabel -Text '每页显示番剧数' -X 20 -Y ($y + 3) -W 90))
    $numRows = New-Object System.Windows.Forms.NumericUpDown
    $numRows.Location = New-Object System.Drawing.Point(114, $y)
    $numRows.Size = New-Object System.Drawing.Size(56, 24)
    $numRows.Minimum = 1
    $numRows.Maximum = 20
    $numRows.Value = [decimal](Get-Prop $Config.ui 'rowsPerView' 3)
    $form.Controls.Add($numRows)
    $y += 28
    # 主题（可更换背景）
    $form.Controls.Add((New-DialogLabel -Text '主题背景' -X 20 -Y ($y + 3) -W 60))
    $cbTheme = New-Object System.Windows.Forms.ComboBox
    $cbTheme.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $cbTheme.Location = New-Object System.Drawing.Point(84, $y)
    $cbTheme.Size = New-Object System.Drawing.Size(120, 24)
    [void]$cbTheme.Items.AddRange(@('深紫（默认）', '纯黑', '深蓝', '墨绿', '暗红', '浅色', '自定义'))
    $themeKeys = @('deep-purple', 'black', 'deep-blue', 'dark-green', 'dark-red', 'light', 'custom')
    $curTheme = [string](Get-Prop $Config.ui 'theme' 'deep-purple')
    $themeIdx = [array]::IndexOf($themeKeys, $curTheme)
    if ($themeIdx -lt 0) { $themeIdx = 0 }
    $cbTheme.SelectedIndex = $themeIdx
    $form.Controls.Add($cbTheme)
    $script:bgCustomHex = [string](Get-Prop $Config.ui 'bgCustom' '#14121E')
    $lblBg = New-DialogLabel -Text $script:bgCustomHex -X 214 -Y ($y + 3) -W 86 -Color '#C8C8D6'
    $form.Controls.Add($lblBg)
    try { $lblBg.BackColor = [System.Drawing.ColorTranslator]::FromHtml($script:bgCustomHex) } catch { }
    $btnBg = New-DialogButton -Text '选择背景色' -X 306 -Y ($y - 4) -W 106 -H 26
    $form.Controls.Add($btnBg)
    $btnBg.add_Click({
            $cd = New-Object System.Windows.Forms.ColorDialog
            $cd.FullOpen = $true
            try { $cd.Color = [System.Drawing.ColorTranslator]::FromHtml($script:bgCustomHex) } catch { }
            if ($cd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                $script:bgCustomHex = ('#{0:X2}{1:X2}{2:X2}' -f $cd.Color.R, $cd.Color.G, $cd.Color.B)
                $lblBg.Text = $script:bgCustomHex
                $lblBg.BackColor = $cd.Color
                $cbTheme.SelectedIndex = 6
            }
        })
    $y += 28
    $cbJst = New-Object System.Windows.Forms.CheckBox
    $cbJst.Text = '在每行显示日本时间（北京时间为主）'
    $cbJst.Location = New-Object System.Drawing.Point(20, $y)
    $cbJst.Size = New-Object System.Drawing.Size(260, 22)
    $cbJst.Checked = [bool](Get-Prop $Config.data 'showJstTime' $true)
    $cbJst.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#C8C8D6')
    $form.Controls.Add($cbJst)
    $cbStream = New-Object System.Windows.Forms.CheckBox
    $cbStream.Text = '显示网络放送'
    $cbStream.Location = New-Object System.Drawing.Point(290, $y)
    $cbStream.Size = New-Object System.Drawing.Size(150, 22)
    $cbStream.Checked = [bool](Get-Prop $Config.data 'showStreaming' $true)
    $cbStream.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#C8C8D6')
    $form.Controls.Add($cbStream); $y += 28
    $cbResolve = New-Object System.Windows.Forms.CheckBox
    $cbResolve.Text = '自动解析 Bangumi 条目（补充评分 / 电视台）'
    $cbResolve.Location = New-Object System.Drawing.Point(20, $y)
    $cbResolve.Size = New-Object System.Drawing.Size(320, 22)
    $cbResolve.Checked = [bool](Get-Prop $Config.data 'resolveBangumiIds' $true)
    $cbResolve.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#C8C8D6')
    $form.Controls.Add($cbResolve)
    $form.Controls.Add((New-DialogLabel -Text '每次上限' -X 348 -Y ($y + 3) -W 60))
    $numMax = New-Object System.Windows.Forms.NumericUpDown
    $numMax.Location = New-Object System.Drawing.Point(404, $y)
    $numMax.Size = New-Object System.Drawing.Size(52, 24)
    $numMax.Minimum = 0
    $numMax.Maximum = 300
    $numMax.Value = [decimal](Get-Prop $Config.data 'maxResolvePerRefresh' 40)
    $form.Controls.Add($numMax); $y += 34

    $form.Controls.Add((New-DialogLabel -Text 'Bangumi 账号' -X 16 -Y $y -W 200 -H 22 -Bold $true)); $y += 26
    $auth = Get-BangumiAuth
    $loginText = '未登录'
    if ($auth.accessToken) { $loginText = ('已登录：' + $(if ($auth.username) { $auth.username } else { 'Token 用户' })) }
    elseif (Get-Prop $Config.bangumi 'usePublicCollections' $false) { $loginText = ('未登录（读取公开收藏：' + (Get-Prop $Config.bangumi 'username' '未填写') + '）') }
    $lblLogin = New-DialogLabel -Text $loginText -X 20 -Y $y -W 260 -Color '#9A9AAE'
    $form.Controls.Add($lblLogin)
    $btnLogin = New-DialogButton -Text '登录 / 管理' -X 290 -Y ($y - 6) -W 110 -H 26 -Primary $true
    $btnLogout = New-DialogButton -Text '注销' -X 406 -Y ($y - 6) -W 50 -H 26
    $form.Controls.Add($btnLogin); $form.Controls.Add($btnLogout); $y += 28
    $form.Controls.Add((New-DialogLabel -Text '公开收藏用户名（可选，无需 Token）' -X 20 -Y $y -W 230))
    $txtUser = New-Object System.Windows.Forms.TextBox
    $txtUser.Location = New-Object System.Drawing.Point(252, ($y - 2))
    $txtUser.Size = New-Object System.Drawing.Size(100, 24)
    $txtUser.Text = [string](Get-Prop $Config.bangumi 'username' '')
    $txtUser.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#17171E')
    $txtUser.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#D8D8E4')
    $form.Controls.Add($txtUser)
    $cbPublic = New-Object System.Windows.Forms.CheckBox
    $cbPublic.Text = '公开读取'
    $cbPublic.Location = New-Object System.Drawing.Point(354, $y)
    $cbPublic.Size = New-Object System.Drawing.Size(100, 22)
    $cbPublic.Checked = [bool](Get-Prop $Config.bangumi 'usePublicCollections' $false)
    $cbPublic.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#C8C8D6')
    $form.Controls.Add($cbPublic); $y += 34

    $form.Controls.Add((New-DialogLabel -Text ('数据目录：' + (Get-DataDir)) -X 16 -Y $y -W 440 -H 18 -Color '#6E6E85'))

    $btnSave = New-DialogButton -Text '保存并刷新' -X 200 -Y 640 -W 120 -H 32 -Primary $true
    $btnCancel = New-DialogButton -Text '取消' -X 330 -Y 640 -W 90 -H 32
    $form.Controls.Add($btnSave); $form.Controls.Add($btnCancel)

    $btnLogin.add_Click({
            Show-LoginDialog -Config $Config | Out-Null
            $a = Get-BangumiAuth
            if ($a.accessToken) { $lblLogin.Text = ('已登录：' + $(if ($a.username) { $a.username } else { 'Token 用户' })) }
            else { $lblLogin.Text = '未登录' }
        })
    $btnLogout.add_Click({
            Save-BangumiAuth ([pscustomobject]@{ accessToken = ''; refreshToken = ''; expiresAt = $null; username = ''; userId = 0; appId = ''; appSecret = ''; redirectPort = 3721 })
            $lblLogin.Text = '未登录'
        })
    $btnSave.add_Click({
            $modes = @('auto', 'direct', 'system', 'custom')
            $Config.data.useYuc = [bool]$cbYuc.Checked
            $Config.data.useBangumi = [bool]$cbBgm.Checked
            $Config.data.refreshHours = [int]$numRefresh.Value
            $Config.data.showJstTime = [bool]$cbJst.Checked
            $Config.data.showStreaming = [bool]$cbStream.Checked
            $Config.data.resolveBangumiIds = [bool]$cbResolve.Checked
            $Config.data.maxResolvePerRefresh = [int]$numMax.Value
            $Config.network.proxyMode = $modes[$cbProxy.SelectedIndex]
            $Config.network.proxyUrl = $txtProxy.Text.Trim()
            $Config.network.allowInsecureTls = [bool]$cbTls.Checked
            $Config.ui.topMost = [bool]$cbTop.Checked
            $Config.ui.opacity = [double]$numOpacity.Value
            $rowsChanged = ([int]$numRows.Value -ne [int](Get-Prop $Config.ui 'rowsPerView' 3))
            $Config.ui.rowsPerView = [int]$numRows.Value
            $Config.ui.theme = $themeKeys[$cbTheme.SelectedIndex]
            $Config.ui.bgCustom = $script:bgCustomHex
            $Config.bangumi.username = $txtUser.Text.Trim()
            $Config.bangumi.usePublicCollections = [bool]$cbPublic.Checked

            Save-WidgetConfig -Config $Config | Out-Null
            $f = $script:Ui.Form
            if ($f) {
                $f.TopMost = [bool]$Config.ui.topMost
                $f.Opacity = [double]$Config.ui.opacity
                if ($rowsChanged) { $f.Height = Get-WidgetHeightForRows -Config $Config }
                $script:Ui.Theme = New-Theme -Config $Config
                $f.Invalidate()
            }
            if ($OnSaved) { & $OnSaved }
            elseif ($script:Ui -and $script:Ui.Form) { Start-WidgetRefresh -Ui $script:Ui -Force }
            $form.Close()
        })
    $btnCancel.add_Click({ $form.Close() })

    if ($RenderTo) { Render-DialogToFile -Form $form -Path $RenderTo; $form.Dispose(); return }
    Show-Modal -Form $form
    $form.Dispose()
}

# ---------------- 登录 ----------------
function Show-LoginDialog {
    param($Config, [string]$RenderTo = '')
    $form = New-DialogForm -Title 'Bangumi 登录' -Width 480 -Height 470 -Config $Config

    $auth = Get-BangumiAuth
    $status = '当前状态：未登录'
    if ($auth.accessToken) { $status = ('当前状态：已登录 ' + $(if ($auth.username) { $auth.username } else { '(Token)' })) }
    $lblStatus = New-DialogLabel -Text $status -X 16 -Y 12 -W 440 -H 24 -Bold $true -Color '#FFFFFF'
    $form.Controls.Add($lblStatus)
    $form.Controls.Add((New-DialogLabel -Text '登录后小组件会读取你的「在看」列表，在对应番剧上标注 ★ 与播出时间。' -X 16 -Y 36 -W 440 -H 20 -Color '#9A9AAE'))

    # 方式一：访问令牌
    $form.Controls.Add((New-DialogLabel -Text '方式一 · 访问令牌（推荐，30 秒完成）' -X 16 -Y 66 -W 440 -H 22 -Bold $true))
    # 令牌页地址：只读文本框（可选中复制）+ 打开按钮
    $txtTokenUrl = New-Object System.Windows.Forms.TextBox
    $txtTokenUrl.ReadOnly = $true
    $txtTokenUrl.Location = New-Object System.Drawing.Point(16, 86)
    $txtTokenUrl.Size = New-Object System.Drawing.Size(298, 22)
    $txtTokenUrl.Text = 'https://next.bgm.tv/demo/access-token'
    $txtTokenUrl.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#17171E')
    $txtTokenUrl.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#9FB4FF')
    $txtTokenUrl.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $form.Controls.Add($txtTokenUrl)
    $btnTokenPage = New-DialogButton -Text '打开/复制' -X 320 -Y 84 -W 120 -H 26
    $form.Controls.Add($btnTokenPage)
    $txtToken = New-Object System.Windows.Forms.TextBox
    $txtToken.Location = New-Object System.Drawing.Point(18, 112)
    $txtToken.Size = New-Object System.Drawing.Size(424, 24)
    $txtToken.Text = [string]$auth.accessToken
    $txtToken.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#17171E')
    $txtToken.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#D8D8E4')
    $form.Controls.Add($txtToken)
    $btnVerify = New-DialogButton -Text '校验并保存' -X 18 -Y 142 -W 110 -H 28 -Primary $true
    $form.Controls.Add($btnVerify)
    $lblTokenMsg = New-DialogLabel -Text '' -X 136 -Y 146 -W 310 -H 20 -Color '#9A9AAE'
    $form.Controls.Add($lblTokenMsg)

    # 方式二：OAuth
    $form.Controls.Add((New-DialogLabel -Text '方式二 · OAuth 应用授权（需自建应用）' -X 16 -Y 186 -W 440 -H 22 -Bold $true))
    $form.Controls.Add((New-DialogLabel -Text '在 bgm.tv/dev/app 创建应用，回调地址填 http://localhost:端口/callback' -X 16 -Y 208 -W 440 -H 20 -Color '#9A9AAE'))
    $form.Controls.Add((New-DialogLabel -Text 'App ID' -X 18 -Y 236 -W 50))
    $txtAppId = New-Object System.Windows.Forms.TextBox
    $txtAppId.Location = New-Object System.Drawing.Point(70, 233)
    $txtAppId.Size = New-Object System.Drawing.Size(110, 24)
    $txtAppId.Text = [string](Get-Prop $auth 'appId' (Get-Prop $Config.bangumi 'oauthAppId' ''))
    $txtAppId.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#17171E')
    $txtAppId.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#D8D8E4')
    $form.Controls.Add($txtAppId)
    $form.Controls.Add((New-DialogLabel -Text 'App Secret' -X 184 -Y 236 -W 76))
    $txtAppSecret = New-Object System.Windows.Forms.TextBox
    $txtAppSecret.Location = New-Object System.Drawing.Point(262, 233)
    $txtAppSecret.Size = New-Object System.Drawing.Size(110, 24)
    $txtAppSecret.Text = [string](Get-Prop $auth 'appSecret' (Get-Prop $Config.bangumi 'oauthAppSecret' ''))
    $txtAppSecret.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#17171E')
    $txtAppSecret.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#D8D8E4')
    $form.Controls.Add($txtAppSecret)
    $form.Controls.Add((New-DialogLabel -Text '端口' -X 376 -Y 236 -W 32))
    $numPort = New-Object System.Windows.Forms.NumericUpDown
    $numPort.Location = New-Object System.Drawing.Point(410, 233)
    $numPort.Size = New-Object System.Drawing.Size(52, 24)
    $numPort.Minimum = 1024
    $numPort.Maximum = 65535
    $numPort.Value = [decimal](Get-Prop $Config.bangumi 'oauthRedirectPort' 3721)
    $form.Controls.Add($numPort)
    $btnOauth = New-DialogButton -Text '开始网页授权' -X 18 -Y 266 -W 120 -H 28 -Primary $true
    $form.Controls.Add($btnOauth)
    $lblOauthMsg = New-DialogLabel -Text '' -X 146 -Y 270 -W 300 -H 20 -Color '#9A9AAE'
    $form.Controls.Add($lblOauthMsg)

    # 方式三：公开收藏
    $form.Controls.Add((New-DialogLabel -Text '方式三 · 只读公开收藏（不登录，仅按用户名读取在看）' -X 16 -Y 308 -W 440 -H 22 -Bold $true))
    $form.Controls.Add((New-DialogLabel -Text 'Bangumi 用户名' -X 18 -Y 336 -W 132))
    $txtUser = New-Object System.Windows.Forms.TextBox
    $txtUser.Location = New-Object System.Drawing.Point(152, 333)
    $txtUser.Size = New-Object System.Drawing.Size(130, 24)
    $txtUser.Text = [string](Get-Prop $Config.bangumi 'username' '')
    $txtUser.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#17171E')
    $txtUser.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#D8D8E4')
    $form.Controls.Add($txtUser)
    $btnPublic = New-DialogButton -Text '保存并启用' -X 292 -Y 332 -W 110 -H 26
    $form.Controls.Add($btnPublic)

    $btnClose = New-DialogButton -Text '关闭' -X 360 -Y 384 -W 90 -H 30
    $form.Controls.Add($btnClose)

    $btnTokenPage.add_Click({
            $url = 'https://next.bgm.tv/demo/access-token'
            try { [System.Windows.Forms.Clipboard]::SetText($url) } catch { }
            $ok = Open-Url $url
            if ($ok) {
                [System.Windows.Forms.MessageBox]::Show(
                    ("已在浏览器打开令牌页，链接也已复制到剪贴板。`n`n若浏览器页面打不开/一直转圈：next.bgm.tv 国内通常需要代理（Clash 等）。请开代理后用浏览器打开：`n`n{0}" -f $url),
                    '令牌页面', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            }
        })
    $btnVerify.add_Click({
            $token = $txtToken.Text.Trim()
            if (-not $token) { $lblTokenMsg.Text = '请先粘贴令牌'; return }
            $lblTokenMsg.Text = '正在校验…'
            $form.Refresh()
            $t = Test-BangumiToken -Token $token -Config $Config
            if ($t.ok) {
                $a = Get-BangumiAuth
                $a.accessToken = $token
                $a.username = $t.username
                $a.userId = $t.userId
                Save-BangumiAuth $a
                $lblTokenMsg.Text = ('成功：' + $(if ($t.nickname) { $t.nickname } else { $t.username }))
                $lblStatus.Text = '当前状态：已登录 ' + $t.username
                $Config.bangumi.usePublicCollections = $false
                Save-WidgetConfig -Config $Config | Out-Null
            } else {
                $errText = [string]$t.error
                # 网络不通时也能先保存令牌，稍后联网再校验
                $saveAnyway = [System.Windows.Forms.MessageBox]::Show(
                    ("校验失败（网络无法连接 Bangumi API）：`n`n{0}`n`n是否仍保存该令牌？保存后等网络/代理就绪即可使用；你也可以在设置里改代理地址后再试。" -f $errText),
                    '校验失败', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
                if ($saveAnyway -eq [System.Windows.Forms.DialogResult]::Yes) {
                    $a = Get-BangumiAuth
                    $a.accessToken = $token
                    Save-BangumiAuth $a
                    $lblTokenMsg.Text = '已保存（校验未通过：' + $errText + '）'
                    $lblStatus.Text = '当前状态：已保存令牌（待校验）'
                } else {
                    $lblTokenMsg.Text = '失败：' + $errText
                }
            }
        })
    $btnOauth.add_Click({
            $appId = $txtAppId.Text.Trim()
            $secret = $txtAppSecret.Text.Trim()
            if (-not $appId -or -not $secret) { $lblOauthMsg.Text = '请填写 App ID 与 Secret'; return }
            $port = [int]$numPort.Value
            $Config.bangumi.oauthAppId = $appId
            $Config.bangumi.oauthAppSecret = $secret
            $Config.bangumi.oauthRedirectPort = $port
            Save-WidgetConfig -Config $Config | Out-Null
            $lblOauthMsg.Text = '等待浏览器授权…'
            $form.Refresh()
            $job = Start-BackgroundJob -ScriptBlock {
                param($root, $appId, $secret, $port)
                $Global:AnimeWidgetRoot = $root
                . (Join-Path $root 'src\lib\Util.ps1')
                . (Join-Path $root 'src\lib\Http.ps1')
                . (Join-Path $root 'src\lib\Yuc.ps1')
                . (Join-Path $root 'src\lib\Bangumi.ps1')
                . (Join-Path $root 'src\lib\Data.ps1')
                $cfg = Get-WidgetConfig
                return (Start-BangumiOAuthFlow -AppId $appId -AppSecret $secret -Port $port -Config $cfg)
            } -Arguments @((Get-Root), $appId, $secret, $port)

            $timer = New-Object System.Windows.Forms.Timer
            $timer.Interval = 500
            $timer.add_Tick({
                    if (-not $job.Handle.IsCompleted) { return }
                    $timer.Stop()
                    $res = Receive-BackgroundJob -Job $job
                    $o = $null
                    foreach ($item in $res.Output) { if ($item -and $item.PSObject.Properties['ok']) { $o = $item } }
                    if ($o -and $o.ok) {
                        $a = Get-BangumiAuth
                        $lblStatus.Text = '当前状态：已登录 ' + $(if ($a.username) { $a.username } else { '(OAuth)' })
                        $lblOauthMsg.Text = '授权成功'
                        $txtToken.Text = [string]$a.accessToken
                        $Config.bangumi.usePublicCollections = $false
                        Save-WidgetConfig -Config $Config | Out-Null
                    } else {
                        $lblOauthMsg.Text = '失败：' + $(if ($o) { $o.error } else { ($res.Error -join ' ') })
                    }
                })
            $timer.Start()
        })
    $btnPublic.add_Click({
            $u = $txtUser.Text.Trim()
            if (-not $u) { return }
            $Config.bangumi.username = $u
            $Config.bangumi.usePublicCollections = $true
            Save-WidgetConfig -Config $Config | Out-Null
            $t = Get-BangumiCollections -Username $u -Type 3 -Config $Config -Force -MaxAgeMinutes 1
            if ($t.ok) { $lblStatus.Text = ('当前状态：公开读取 ' + $u + ('（在看 ' + $t.items.Count + ' 部）')) }
            else { $lblStatus.Text = ('公开读取失败：' + $t.error) }
        })
    $btnClose.add_Click({ $form.Close() })

    if ($RenderTo) { Render-DialogToFile -Form $form -Path $RenderTo; $form.Dispose(); return }
    Show-Modal -Form $form
    $form.Dispose()
}
