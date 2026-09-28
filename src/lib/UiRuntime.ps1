# UiRuntime.ps1 -- 事件绑定 / 定时刷新 / 托盘 / 后台刷新流程
# 目标运行时：Windows PowerShell 5.1

# 物理像素坐标 -> 逻辑坐标（96dpi 基准），供命中测试使用
function Get-LogicalPoint {
    param($Ui, [System.Drawing.Point]$P)
    $s = [double]$Ui.DpiScale
    if (-not $s -or $s -le 0) { $s = 1.0 }
    return (New-Object System.Drawing.Point([int][math]::Round($P.X / $s), [int][math]::Round($P.Y / $s)))
}

function Save-WindowPos {
    param($Ui)
    try {
        $form = $script:Ui.Form
        if (-not $form) { return }
        $s = [double]$Ui.DpiScale
        if (-not $s -or $s -le 0) { $s = 1.0 }
        $obj = [pscustomobject]@{ x = $form.Location.X; y = $form.Location.Y; w = [int]([math]::Round($form.Width / $s)); h = [int]([math]::Round($form.Height / $s)) }
        Write-JsonFile (Join-Path (Get-DataDir) 'window.json') $obj | Out-Null
    } catch { }
}

function Set-UiState {
    param($Ui, $State)
    $Ui.State = $State
    $Ui.ScrollY = 0
    $Ui.HoverRow = -1
    if ($null -ne $State -and $State.warnings -and @($State.warnings).Count -gt 0) {
        $Ui.LastError = (@($State.warnings) -join ' / ')
    }
    $script:Ui.Form.Invalidate()
}

# ---------------- 后台刷新 ----------------
function Start-WidgetRefresh {
    param($Ui, [switch]$Force)
    if ($Ui.Refreshing) { return }
    $form = $script:Ui.Form
    $Ui.Refreshing = $true
    $Ui.StatusText = '正在刷新…'
    if ($form) { $form.Invalidate() }
    try {
        $worker = {
            param($root, $force)
            $Global:AnimeWidgetRoot = $root
            . (Join-Path $root 'src\lib\Util.ps1')
            . (Join-Path $root 'src\lib\Http.ps1')
            . (Join-Path $root 'src\lib\Yuc.ps1')
            . (Join-Path $root 'src\lib\Bangumi.ps1')
            . (Join-Path $root 'src\lib\Data.ps1')
            $cfg = Get-WidgetConfig
            return (Build-WidgetData -Config $cfg -Force:([bool]$force))
        }
        $Ui.Job = Start-BackgroundJob -ScriptBlock $worker -Arguments @((Get-Root), [bool]$Force)
        $Ui.PollTimer.Start()
    } catch {
        $Ui.Refreshing = $false
        $Ui.LastError = "刷新启动失败：$($_.Exception.Message)"
        Write-Log $Ui.LastError 'ERROR'
        if ($form) { $form.Invalidate() }
    }
}

function Complete-WidgetRefresh {
    param($Ui)
    $form = $script:Ui.Form
    try {
        $res = Receive-BackgroundJob -Job $Ui.Job
        if (@($res.Error).Count -gt 0) {
            $msg = (@($res.Error) -join ' | ')
            Write-Log "刷新期间错误：$msg" 'WARN'
            $Ui.LastError = $msg
        }
        $state = $null
        foreach ($o in @($res.Output)) {
            if ($o -and $o.PSObject.Properties['shows']) { $state = $o }
        }
        if ($state) {
            Set-UiState -Ui $Ui -State $state
            if ($state.warnings -and @($state.warnings).Count -gt 0) {
                Write-Log ("刷新警告：" + (@($state.warnings) -join ' / ')) 'WARN'
            }
        } else {
            $Ui.LastError = '刷新未返回数据'
        }
    } catch {
        $Ui.LastError = "刷新失败：$($_.Exception.Message)"
        Write-Log $Ui.LastError 'ERROR'
    } finally {
        $Ui.Job = $null
        $Ui.Refreshing = $false
        try { $Ui.PollTimer.Stop() } catch { }
        if ($form) { $form.Invalidate() }
    }
}
# ---------------- 交互动作 ----------------
function Invoke-RowAction {
    param($Ui, $Show, [string]$Action = 'open')
    switch ($Action) {
        'open' {
            if ($Show.bgmId -gt 0) { Open-Url ('https://bgm.tv/subject/' + $Show.bgmId) }
            elseif ($Show.site) { Open-Url $Show.site }
        }
        'bgm' { if ($Show.bgmId -gt 0) { Open-Url ('https://bgm.tv/subject/' + $Show.bgmId) } }
        'site' { if ($Show.site) { Open-Url $Show.site } }
        'pv' { if ($Show.pv) { Open-Url $Show.pv } }
        'copy' { try { [System.Windows.Forms.Clipboard]::SetText($Show.title) } catch { } }
        'details' { Show-DetailsDialog -Show $Show -Config $Ui.Config }
        'follow' {
            $auth = Get-BangumiAuth
            if (-not $auth.accessToken) {
                [System.Windows.Forms.MessageBox]::Show('请先在「设置 → Bangumi 登录」中登录，才能写入在看列表。', '未登录') | Out-Null
                return
            }
            if ($Show.bgmId -le 0) {
                [System.Windows.Forms.MessageBox]::Show('该条目还没有关联到 Bangumi 条目，暂时无法加入在看。', '无法加入') | Out-Null
                return
            }
            $r = Add-BangumiCollection -SubjectId $Show.bgmId -Token $auth.accessToken -Config $Ui.Config -Type 3
            if ($r.ok) {
                $Show.followed = $true
                [System.Windows.Forms.MessageBox]::Show(("已把「{0}」加入在看。" -f $Show.title), '成功') | Out-Null
                $script:Ui.Form.Invalidate()
            } else {
                [System.Windows.Forms.MessageBox]::Show(("加入在看失败：{0}`n（Token 需要收集写权限）" -f $r.error), '失败') | Out-Null
            }
        }
    }
}

function Show-RowMenu {
    param($Ui, $Show, [System.Drawing.Point]$ScreenPoint)
    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $itemOpen = $menu.Items.Add('打开 Bangumi 条目')
    $itemDetail = $menu.Items.Add('查看详情')
    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    $itemSite = $menu.Items.Add('打开动画官网')
    $itemPv = $menu.Items.Add('打开 PV')
    $itemCopy = $menu.Items.Add('复制名称')
    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    $itemFollow = $menu.Items.Add('加入我的在看（Bangumi）')
    $itemOpen.add_Click({ Invoke-RowAction -Ui $Ui -Show $Show -Action 'bgm' })
    $itemDetail.add_Click({ Invoke-RowAction -Ui $Ui -Show $Show -Action 'details' })
    $itemSite.add_Click({ Invoke-RowAction -Ui $Ui -Show $Show -Action 'site' })
    $itemPv.add_Click({ Invoke-RowAction -Ui $Ui -Show $Show -Action 'pv' })
    $itemCopy.add_Click({ Invoke-RowAction -Ui $Ui -Show $Show -Action 'copy' })
    $itemFollow.add_Click({ Invoke-RowAction -Ui $Ui -Show $Show -Action 'follow' })
    if ($Show.bgmId -le 0) { $itemOpen.Enabled = $false }
    if (-not $Show.site) { $itemSite.Enabled = $false }
    if (-not $Show.pv) { $itemPv.Enabled = $false }
    $menu.Show($ScreenPoint)
}

function Get-RegionAt {
    param($Ui, [System.Drawing.Point]$Point)
    foreach ($r in $Ui.Regions) {
        if ($null -eq $r.rect) { continue }
        # 关键：行区域只在「列表区」内可命中。
        # 滚屏后行的矩形会向上盖住标题栏/页签、向下盖住页脚，
        # 若不限制就会把“点标题栏拖动”误判成“点某一行”，导致无法拖拽移动。
        if ($r.kind -eq 'row') {
            if ($Ui.Layout -and -not $Ui.Layout.List.Contains($Point)) { continue }
        }
        if ($r.rect.Contains($Point)) { return $r }
    }
    return $null
}

function Update-WidgetScrollBounds {
    param($Ui)
    $layout = $Ui.Layout
    if (-not $layout) { return }
    $count = @($Ui.VisibleShows).Count
    $content = ($count * [int]$Ui.RowHeight) + 8
    $Ui.MaxScroll = [math]::Max(0, ($content - $layout.List.Height))
}

# ---------------- 托盘 ----------------
function Initialize-Tray {
    param($Ui)
    if (-not (Get-Prop $Ui.Config.ui 'showTrayIcon' $true)) { return }
    try {
        $notify = New-Object System.Windows.Forms.NotifyIcon
        $notify.Icon = New-WidgetIcon -Size 32
        $notify.Text = '新番桌面小组件'
        $notify.Visible = $true
        $menu = New-Object System.Windows.Forms.ContextMenuStrip
        $miShow = $menu.Items.Add('显示 / 隐藏')
        $miRefresh = $menu.Items.Add('立即刷新')
        $miSettings = $menu.Items.Add('设置')
        [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
        $miExit = $menu.Items.Add('退出')
        $miShow.add_Click({
                $f = $script:Ui.Form
                $f.Visible = -not $f.Visible
                if ($f.Visible) { $f.Activate() }
            })
        $miRefresh.add_Click({ Start-WidgetRefresh -Ui $script:Ui -Force })
        $miSettings.add_Click({ Show-SettingsDialog -Config $script:Ui.Config })
        $miExit.add_Click({ $script:Ui.Exiting = $true; $script:Ui.Form.Close() })
        $notify.ContextMenuStrip = $menu
        $notify.add_MouseDoubleClick({
                $f = $script:Ui.Form
                $f.Visible = -not $f.Visible
                if ($f.Visible) { $f.Activate() }
            })
        $Ui.Notify = $notify
    } catch {
        Write-Log "托盘图标创建失败：$($_.Exception.Message)" 'WARN'
    }
}

# ---------------- 主循环 ----------------
function Start-Widget {
    param($Config, $State)
    $win = New-WidgetWindow -Config $Config -State $State
    $form = $win.Form
    $Ui = $win.Ui
    $Ui.Exiting = $false
    $Ui.MaxScroll = 0

    Update-UiRegions -Ui $Ui


    # ---- 鼠标移动 ----
    $form.Add_MouseMove({
            param($sender, $e)
            $Ui = $script:Ui
            $form = $Ui.Form
            $s = [double]$Ui.DpiScale
            if (-not $s -or $s -le 0) { $s = 1.0 }
            if ($Ui.Dragging) {
                $cursor = [System.Windows.Forms.Cursor]::Position
                $form.Location = New-Object System.Drawing.Point(($cursor.X - [int]($Ui.DragOffset.X * $s)), ($cursor.Y - [int]($Ui.DragOffset.Y * $s)))
                return
            }
            if ($Ui.Resizing) {
                $cursor = [System.Windows.Forms.Cursor]::Position
                $nw = [math]::Max(300, (($cursor.X - $form.Location.X) / $s))
                $nh = [math]::Max(200, (($cursor.Y - $form.Location.Y) / $s))
                $pw = [int]($nw * $s); $ph = [int]($nh * $s)
                $form.Size = New-Object System.Drawing.Size($pw, $ph)
                $p = New-RoundedPath -Rect (New-Object System.Drawing.Rectangle(0, 0, ($pw - 1), ($ph - 1))) -Radius ([int](14 * $s))
                $form.Region = New-Object System.Drawing.Region($p)
                $form.Invalidate()
                return
            }
            $lp = Get-LogicalPoint -Ui $Ui -P $e.Location
            $r = Get-RegionAt -Ui $Ui -Point $lp
            $hb = -1; $ht = -1; $hr = -1
            if ($r) {
                if ($r.kind -eq 'button') { $hb = $r.name }
                elseif ($r.kind -eq 'tab') { $ht = $r.name }
                elseif ($r.kind -eq 'row') { $hr = $r.index }
            }
            if ($hb -ne $Ui.HoverBtn -or $ht -ne $Ui.HoverTab -or $hr -ne $Ui.HoverRow) {
                $Ui.HoverBtn = $hb; $Ui.HoverTab = $ht; $Ui.HoverRow = $hr
                $form.Invalidate()
            }
            $resizeZone = ($e.X -ge ($form.ClientSize.Width - [int](16 * $s)) -and $e.Y -ge ($form.ClientSize.Height - [int](16 * $s)))
            $form.Cursor = $(if ($resizeZone) { [System.Windows.Forms.Cursors]::SizeNWSE } else { [System.Windows.Forms.Cursors]::Default })
        })

    # ---- 鼠标按下 ----
    $form.Add_MouseDown({
            param($sender, $e)
            $Ui = $script:Ui
            $form = $Ui.Form
            $s = [double]$Ui.DpiScale
            if (-not $s -or $s -le 0) { $s = 1.0 }
            $lp = Get-LogicalPoint -Ui $Ui -P $e.Location
            if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) {
                $r = Get-RegionAt -Ui $Ui -Point $lp
                if ($r -and $r.kind -eq 'row') {
                    Show-RowMenu -Ui $Ui -Show $r.show -ScreenPoint ($form.PointToScreen($e.Location))
                } else {
                    $menu = New-Object System.Windows.Forms.ContextMenuStrip
                    $m1 = $menu.Items.Add('立即刷新')
                    $m2 = $menu.Items.Add('设置')
                    $m3 = $menu.Items.Add('隐藏到托盘')
                    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
                    $m4 = $menu.Items.Add('退出')
                    $m1.add_Click({ Start-WidgetRefresh -Ui $script:Ui -Force })
                    $m2.add_Click({ Show-SettingsDialog -Config $script:Ui.Config })
                    $m3.add_Click({ $script:Ui.Form.Visible = $false })
                    $m4.add_Click({ $script:Ui.Exiting = $true; $script:Ui.Form.Close() })
                    $menu.Show($form.PointToScreen($e.Location))
                }
                return
            }
            if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
            $Ui.PressPoint = $lp
            $Ui.PressRegion = Get-RegionAt -Ui $Ui -Point $lp
            if ($e.X -ge ($form.ClientSize.Width - [int](16 * $s)) -and $e.Y -ge ($form.ClientSize.Height - [int](16 * $s))) {
                $Ui.Resizing = $true
                return
            }
            if (-not $Ui.PressRegion) {
                $Ui.Dragging = $true
                $Ui.DragOffset = $lp
            }
        })

    # ---- 鼠标抬起 ----
    $form.Add_MouseUp({
            param($sender, $e)
            $Ui = $script:Ui
            $form = $Ui.Form
            if ($Ui.Dragging) {
                $Ui.Dragging = $false
                Save-WindowPos -Ui $Ui
                return
            }
            if ($Ui.Resizing) {
                $Ui.Resizing = $false
                Save-WindowPos -Ui $Ui
                $form.Invalidate()
                return
            }
            if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
            if (-not $Ui.PressPoint) { return }
            $lp = Get-LogicalPoint -Ui $Ui -P $e.Location
            $moved = [math]::Abs($lp.X - $Ui.PressPoint.X) + [math]::Abs($lp.Y - $Ui.PressPoint.Y)
            if ($moved -gt 4) { $Ui.PressPoint = $null; return }
            $r = Get-RegionAt -Ui $Ui -Point $lp
            if (-not $r) { $Ui.PressPoint = $null; return }
            switch ($r.kind) {
                'button' {
                    switch ($r.name) {
                        'refresh' { Start-WidgetRefresh -Ui $Ui -Force }
                        'follow' { $Ui.Tab = 'follow'; $Ui.ScrollY = 0; $form.Invalidate() }
                        'settings' { Show-SettingsDialog -Config $Ui.Config }
                        'minimize' { $form.Visible = $false }
                        'close' { $Ui.Exiting = $true; $form.Close() }
                    }
                }
                'tab' {
                    if ($r.name -eq 'follow') { $Ui.Tab = 'follow' }
                    else { $Ui.Tab = 'day'; $Ui.Day = $r.day }
                    $Ui.ScrollY = 0
                    $form.Invalidate()
                }
                'row' {
                    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
                        Invoke-RowAction -Ui $Ui -Show $r.show -Action 'open'
                    }
                }
            }
            $Ui.PressPoint = $null
        })

    # ---- 滚轮 ----
    $form.Add_MouseWheel({
            param($sender, $e)
            $Ui = $script:Ui
            Update-WidgetScrollBounds -Ui $Ui
            $step = 76
            $delta = $(if ($e.Delta -gt 0) { -$step } else { $step })
            $newScroll = $Ui.ScrollY + $delta
            if ($newScroll -lt 0) { $newScroll = 0 }
            if ($newScroll -gt $Ui.MaxScroll) { $newScroll = $Ui.MaxScroll }
            if ($newScroll -ne $Ui.ScrollY) {
                $Ui.ScrollY = $newScroll
                $Ui.Form.Invalidate()
            }
        })

    # ---- 键盘 ----
    $form.Add_KeyDown({
            param($sender, $e)
            $Ui = $script:Ui
            switch ($e.KeyCode) {
                'Left' { $Ui.Tab = 'day'; $Ui.Day = (($Ui.Day + 6) % 7); $Ui.ScrollY = 0; $Ui.Form.Invalidate(); $e.Handled = $true }
                'Right' { $Ui.Tab = 'day'; $Ui.Day = (($Ui.Day + 1) % 7); $Ui.ScrollY = 0; $Ui.Form.Invalidate(); $e.Handled = $true }
                'Up' { $Ui.ScrollY = [math]::Max(0, ($Ui.ScrollY - 40)); $Ui.Form.Invalidate(); $e.Handled = $true }
                'Down' { $Ui.ScrollY = [math]::Min($Ui.MaxScroll, ($Ui.ScrollY + 40)); $Ui.Form.Invalidate(); $e.Handled = $true }
                'PageUp' {
                    $page = $(if ($Ui.Layout) { $Ui.Layout.List.Height } else { 228 }) - [int]$Ui.RowHeight
                    $Ui.ScrollY = [math]::Max(0, ($Ui.ScrollY - $page)); $Ui.Form.Invalidate(); $e.Handled = $true
                }
                'PageDown' {
                    $page = $(if ($Ui.Layout) { $Ui.Layout.List.Height } else { 228 }) - [int]$Ui.RowHeight
                    $Ui.ScrollY = [math]::Min($Ui.MaxScroll, ($Ui.ScrollY + $page)); $Ui.Form.Invalidate(); $e.Handled = $true
                }
                'Home' { $Ui.ScrollY = 0; $Ui.Form.Invalidate(); $e.Handled = $true }
                'End' { $Ui.ScrollY = $Ui.MaxScroll; $Ui.Form.Invalidate(); $e.Handled = $true }
                'Escape' { $Ui.Form.Visible = $false; $e.Handled = $true }
                'F5' { Start-WidgetRefresh -Ui $Ui -Force; $e.Handled = $true }
            }
        })

    $form.Add_Resize({
            param($sender, $e)
            if ($script:Ui -and $script:Ui.Form) {
                $w = $script:Ui.Form.ClientSize.Width
                $h = $script:Ui.Form.ClientSize.Height
                $s = [double]$script:Ui.DpiScale
                if (-not $s -or $s -le 0) { $s = 1.0 }
                $p = New-RoundedPath -Rect (New-Object System.Drawing.Rectangle(0, 0, ($w - 1), ($h - 1))) -Radius ([int](14 * $s))
                $script:Ui.Form.Region = New-Object System.Drawing.Region($p)
                # 同步逻辑尺寸（供绘制/命中测试使用）
                $script:Ui.LogicalWidth = [int][math]::Round($w / $s)
                $script:Ui.LogicalHeight = [int][math]::Round($h / $s)
                $script:Ui.Form.Invalidate()
            }
        })

    $form.Add_FormClosing({
            param($sender, $e)
            Write-Log ("窗口关闭事件，原因={0}" -f $e.CloseReason) 'INFO'
            Save-WindowPos -Ui $script:Ui
            if ($script:Ui.Notify) { try { $script:Ui.Notify.Visible = $false; $script:Ui.Notify.Dispose() } catch { } }
        })

    # ---- 定时器 ----
    $poll = New-Object System.Windows.Forms.Timer
    $poll.Interval = 400
    $poll.add_Tick({
            $Ui = $script:Ui
            if (-not $Ui.Refreshing) { $Ui.PollTimer.Stop(); return }
            if ($Ui.Job -and $Ui.Job.Handle.IsCompleted) {
                Complete-WidgetRefresh -Ui $Ui
            }
        })
    $Ui.PollTimer = $poll

    $tick = New-Object System.Windows.Forms.Timer
    $tick.Interval = 1000
    $tick.add_Tick({
            $Ui = $script:Ui
            # 每分钟重绘一次（页脚倒计时 / 跨日）
            $now = Get-Date
            if ($now.Second -eq 0) { $Ui.Form.Invalidate() }
            if (-not $Ui.Refreshing) {
                $need = Test-NeedRefresh -State $Ui.State -Config $Ui.Config -Now $now
                if ($need) { Start-WidgetRefresh -Ui $Ui }
            }
        })
    $tick.Start()

    Initialize-Tray -Ui $Ui

    try { $form.Show() } catch { Write-Log "Show 异常：$($_.Exception.Message)" 'ERROR' }
    try { $form.Activate() } catch { }
    Write-Log ("窗口已显示：DPI={0} 物理尺寸={1}x{2}" -f $Ui.DpiScale, $form.Width, $form.Height) 'INFO'
    [System.Windows.Forms.Application]::Run($form)

    Write-Log "消息循环结束" 'INFO'
    $tick.Stop(); $poll.Stop()
    try { $tick.Dispose(); $poll.Dispose() } catch { }
    try { $form.Dispose() } catch { }
}
