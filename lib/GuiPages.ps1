#Requires -Version 5.1
# Tab pages. Every block is width-synced to its column, so text wraps inside
# the window instead of running past the edge.

function Update-StackLayout($Stack) {
    if (-not $Stack -or $Stack.IsDisposed) { return }
    if (-not $Script:StackLayoutBusy) { $Script:StackLayoutBusy = @{} }
    $id = $Stack.GetHashCode()
    if ($Script:StackLayoutBusy.ContainsKey($id)) { return }
    $Script:StackLayoutBusy[$id] = $true
    try {
        $padL = $Stack.Padding.Left
        $padT = $Stack.Padding.Top
        $flags = [System.Windows.Forms.TextFormatFlags]::WordBreak -bor [System.Windows.Forms.TextFormatFlags]::TextBoxControl
        # PowerShell enumerates Controls in add order. The title is added first, so it stays on top.
        $items = @($Stack.Controls)
        $contentBottom = $padT
        foreach ($pass in 0, 1) {
            $w = $Stack.ClientSize.Width - $Stack.Padding.Horizontal - 4
            try {
                if ($Stack.VerticalScroll.Visible -or $pass -eq 1) {
                    $needScroll = $contentBottom -gt ($Stack.ClientSize.Height - 4)
                    if ($Stack.VerticalScroll.Visible -or $needScroll) {
                        $w -= [System.Windows.Forms.SystemInformation]::VerticalScrollBarWidth
                    }
                }
            } catch { }
            if ($w -lt 64) { $w = 64 }
            $y = $padT
            foreach ($c in $items) {
                if ($c.Dock -ne 'None') { $c.Dock = 'None' }
                $tag = [string]$c.Tag
                $mTop = 0
                $mBot = 0
                try { $mTop = $c.Margin.Top; $mBot = $c.Margin.Bottom } catch { }
                $y += $mTop
                $h = $c.Height
                if ($tag -eq 'wrap') {
                    $inner = [Math]::Max(40, $w - 4)
                    if ($c -is [System.Windows.Forms.CheckBox]) { $inner = [Math]::Max(40, $w - 28) }
                    $proposed = New-Object System.Drawing.Size($inner, 2000)
                    $measured = [System.Windows.Forms.TextRenderer]::MeasureText([string]$c.Text, $c.Font, $proposed, $flags)
                    $padY = 0
                    try { $padY = $c.Padding.Vertical } catch { }
                    $h = $measured.Height + $padY + 8
                    if ($c -is [System.Windows.Forms.CheckBox] -and $h -lt 28) { $h = 28 }
                    if ($h -lt 20) { $h = 20 }
                    $c.AutoSize = $false
                    $c.MaximumSize = New-Object System.Drawing.Size($w, 0)
                } elseif ($c -is [System.Windows.Forms.FlowLayoutPanel]) {
                    $c.AutoSize = $false
                    $c.Width = $w
                    try { $c.PerformLayout() } catch { }
                    $bottom = 0
                    foreach ($child in @($c.Controls)) {
                        $b = $child.Bottom
                        try { $b += $child.Margin.Bottom } catch { }
                        if ($b -gt $bottom) { $bottom = $b }
                    }
                    $h = $bottom + $c.Padding.Bottom + 4
                    if ($h -lt 36) { $h = 36 }
                } elseif ($h -lt 8) {
                    $h = 24
                }
                $c.SetBounds($padL, $y, $w, $h)
                $y += $h + $mBot
            }
            $contentBottom = $y + $Stack.Padding.Bottom
            $Stack.AutoScrollMinSize = New-Object System.Drawing.Size(0, $contentBottom)
        }
    } finally {
        $Script:StackLayoutBusy.Remove($id)
    }
}

function New-Column($Theme) {
    $col = New-Object System.Windows.Forms.Panel
    $col.Tag = 'stack'
    $col.Dock = 'Fill'
    $col.AutoScroll = $true
    $col.BackColor = $Theme.Bg
    $col.Padding = New-Object System.Windows.Forms.Padding(16, 12, 12, 16)
    $col.Add_Resize({ param($s, $e) Update-StackLayout $s })
    $col.Add_ControlAdded({ param($s, $e) Update-StackLayout $s })
    return $col
}

function New-OneColumn($Page, $Theme) {
    $col = New-Column $Theme
    $Page.Controls.Add($col)
    return $col
}

function New-TwoColumn($Page, $Theme, [int]$LeftPct) {
    $split = New-Object System.Windows.Forms.TableLayoutPanel
    $split.Dock = 'Fill'
    $split.ColumnCount = 2
    $split.RowCount = 1
    $split.BackColor = $Theme.Bg
    $split.Margin = New-Object System.Windows.Forms.Padding(0)
    $split.Padding = New-Object System.Windows.Forms.Padding(0)
    [void]$split.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, [single]$LeftPct)))
    [void]$split.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, [single](100 - $LeftPct))))
    [void]$split.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, [single]100)))
    $left = New-Column $Theme
    $right = New-Column $Theme
    $split.Controls.Add($left, 0, 0)
    $split.Controls.Add($right, 1, 0)
    $Page.Controls.Add($split)
    return @{ Left = $left; Right = $right }
}

function New-BodyLabel {
    param([string]$Text, $Color, $Font)
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $Text
    $lbl.ForeColor = $Color
    $lbl.Font = $Font
    $lbl.AutoSize = $true
    $lbl.Tag = 'wrap'
    $lbl.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 4)
    $lbl.MaximumSize = New-Object System.Drawing.Size(420, 0)
    $lbl.UseMnemonic = $false
    $lbl.Add_TextChanged({
        param($sender, $e)
        $p = $sender.Parent
        while ($p -and [string]$p.Tag -ne 'stack') { $p = $p.Parent }
        if ($p) { Update-StackLayout $p }
    })
    return $lbl
}

function Set-LabelChrome($Label, $Back) {
    $Label.BackColor = $Back
}

function New-StackCheck {
    param([string]$Text, [bool]$Checked)
    $c = New-PremiumCheck $Text (New-Object System.Drawing.Point(0, 0)) $Checked
    $c.Tag = 'wrap'
    $c.Margin = New-Object System.Windows.Forms.Padding(0, 3, 0, 3)
    $c.MaximumSize = New-Object System.Drawing.Size(420, 0)
    return $c
}

function New-InlineRow($Theme) {
    $row = New-Object System.Windows.Forms.FlowLayoutPanel
    $row.FlowDirection = 'LeftToRight'
    $row.WrapContents = $true
    $row.AutoSize = $true
    $row.AutoSizeMode = 'GrowAndShrink'
    $row.BackColor = $Theme.Bg
    $row.Tag = 'fillwidth'
    $row.Margin = New-Object System.Windows.Forms.Padding(0, 2, 0, 6)
    $row.Padding = New-Object System.Windows.Forms.Padding(0)
    return $row
}

function New-ButtonRow($Theme) {
    $row = New-InlineRow $Theme
    $gate = @{ Busy = $false }
    $row.Add_Resize({
        param($s, $e)
        if ($gate.Busy) { return }
        $gate.Busy = $true
        try {
            $max = $s.ClientSize.Width - 8
            if ($max -lt 72) { $max = 72 }
            foreach ($b in @($s.Controls)) {
                if ($b -isnot [System.Windows.Forms.Button]) { continue }
                $want = 0
                try { $want = [int]$b.AccessibleDescription } catch { $want = 0 }
                if ($want -le 0) { $want = $b.Width }
                if ($want -gt $max) { $want = $max }
                if ($b.Width -ne $want) { $b.Width = $want }
            }
        } finally {
            $gate.Busy = $false
        }
    }.GetNewClosure())
    return $row
}

function Add-RowButton($Row, $Button, [int]$PreferredWidth) {
    $Button.AccessibleDescription = [string]$PreferredWidth
    $Button.Width = $PreferredWidth
    $Button.Margin = New-Object System.Windows.Forms.Padding(0, 4, 8, 4)
    $Button.Anchor = 'None'
    $Row.Controls.Add($Button)
}

function Add-PageTitle($Column, $Theme, [string]$Text) {
    $lbl = New-BodyLabel $Text $Theme.Text (New-Object System.Drawing.Font('Segoe UI Semibold', 16))
    Set-LabelChrome $lbl $Theme.Bg
    $lbl.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
    $Column.Controls.Add($lbl)
    return $lbl
}

function Add-Hint($Column, $Theme, [string]$Text) {
    $lbl = New-BodyLabel $Text $Theme.Muted (New-Object System.Drawing.Font('Segoe UI', 9.5))
    Set-LabelChrome $lbl $Theme.Bg
    $Column.Controls.Add($lbl)
    return $lbl
}

function Add-LiveStatus($Column, $Theme, [string]$Text) {
    $lbl = New-BodyLabel $Text $Theme.Text (New-Object System.Drawing.Font('Segoe UI Semibold', 9.5))
    Set-LabelChrome $lbl $Theme.PanelAlt
    $lbl.Padding = New-Object System.Windows.Forms.Padding(10, 8, 10, 8)
    $lbl.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 10)
    $Column.Controls.Add($lbl)
    return $lbl
}

function Add-GuiHomePage {
    param($Page, $Theme)
    $t = $Theme
    $col = New-OneColumn $Page $t
    $titleFont = New-Object System.Drawing.Font('Segoe UI Semibold', 16)
    $bodyFont = New-Object System.Drawing.Font('Segoe UI', 10)
    $smallFont = New-Object System.Drawing.Font('Segoe UI', 9.5)

    [void](Add-PageTitle $col $t 'Home')

    $homeScoreVal = New-BodyLabel '--' $t.Accent (New-Object System.Drawing.Font('Segoe UI Semibold', 28))
    Set-LabelChrome $homeScoreVal $t.Bg
    $homeScoreVal.Margin = New-Object System.Windows.Forms.Padding(0, 0, 16, 0)
    $homeGradeVal = New-BodyLabel 'Reading hardware...' $t.Text (New-Object System.Drawing.Font('Segoe UI Semibold', 12))
    Set-LabelChrome $homeGradeVal $t.Bg
    $homeGradeVal.Margin = New-Object System.Windows.Forms.Padding(0, 18, 0, 0)
    $scoreRow = New-InlineRow $t
    $scoreRow.Controls.Add($homeScoreVal)
    $scoreRow.Controls.Add($homeGradeVal)
    $col.Controls.Add($scoreRow)

    $homeLimiterVal = Add-Hint $col $t 'Scanning...'
    $homeLimiterVal.ForeColor = $t.Text
    $homeFixesVal = Add-Hint $col $t ''
    $homeFixesVal.Font = $smallFont

    $actions = New-ButtonRow $t
    $btnFixMyPc = New-PremiumButton 'Fix my PC for gaming' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(280, 44)) 'Cta'
    $btnWeekly = New-PremiumButton 'Run Weekly Full' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(180, 40)) 'Primary'
    $btnRefreshHome = New-PremiumButton 'Refresh' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(120, 40)) 'Ghost'
    Add-RowButton $actions $btnFixMyPc 280
    Add-RowButton $actions $btnWeekly 180
    Add-RowButton $actions $btnRefreshHome 120
    $col.Controls.Add($actions)

    $chkHomeRestore = New-StackCheck 'Create restore point' $true
    $chkHomeShader = New-StackCheck 'Clear GPU shader caches' $true
    $chkHomeGaming = New-StackCheck 'Apply gaming optimizations' $true
    $chkHomeWU = New-StackCheck 'Windows Update (slow)' $false
    $chkHomeWinget = New-StackCheck 'winget app upgrades (slow)' $false
    $checkRow = New-InlineRow $t
    foreach ($chk in @($chkHomeRestore, $chkHomeShader, $chkHomeGaming, $chkHomeWU, $chkHomeWinget)) {
        $chk.AutoSize = $true
        $chk.Margin = New-Object System.Windows.Forms.Padding(0, 2, 18, 2)
        $checkRow.Controls.Add($chk)
    }
    $col.Controls.Add($checkRow)

    $presetLbl = Add-Hint $col $t 'Presets'
    $presetLbl.Margin = New-Object System.Windows.Forms.Padding(0, 12, 0, 2)
    $presets = New-ButtonRow $t
    $btnPresetGamer = New-PremiumButton 'Gamer' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(110, 34)) 'Ghost'
    $btnPresetQuiet = New-PremiumButton 'Quiet' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(110, 34)) 'Ghost'
    $btnPresetFull = New-PremiumButton 'Full' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(110, 34)) 'Ghost'
    Add-RowButton $presets $btnPresetGamer 110
    Add-RowButton $presets $btnPresetQuiet 110
    Add-RowButton $presets $btnPresetFull 110
    $col.Controls.Add($presets)

    $chkScheduleWeekly = New-StackCheck 'Schedule Weekly Full (Sundays 6 PM)' $false
    $col.Controls.Add($chkScheduleWeekly)
    $lblScheduleStatus = Add-Hint $col $t 'Weekly schedule: off'
    $lblScheduleStatus.ForeColor = $t.Text
    Add-Hint $col $t 'Presets fill the checkboxes. Schedule runs your saved Home options while you are signed in.' | Out-Null

    $cpuCard = New-MetricCard 'E950' 'CPU'
    $gpuCard = New-MetricCard 'E7F4' 'GPU'
    $ramCard = New-MetricCard 'EDA2' 'RAM'
    foreach ($card in @($cpuCard.Panel, $gpuCard.Panel, $ramCard.Panel)) {
        $card.Dock = 'None'
        $card.Tag = 'fillwidth'
        $card.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 4)
        $col.Controls.Add($card)
    }

    return [ordered]@{
        BtnFixMyPc = $btnFixMyPc
        BtnPresetFull = $btnPresetFull
        BtnPresetGamer = $btnPresetGamer
        BtnPresetQuiet = $btnPresetQuiet
        BtnRefreshHome = $btnRefreshHome
        BtnWeekly = $btnWeekly
        ChkHomeGaming = $chkHomeGaming
        ChkHomeRestore = $chkHomeRestore
        ChkHomeShader = $chkHomeShader
        ChkHomeWinget = $chkHomeWinget
        ChkHomeWU = $chkHomeWU
        ChkScheduleWeekly = $chkScheduleWeekly
        CpuMain = $cpuCard.Main
        CpuStat = $cpuCard.Stat
        GpuMain = $gpuCard.Main
        GpuStat = $gpuCard.Stat
        HomeFixesVal = $homeFixesVal
        HomeGradeVal = $homeGradeVal
        HomeLimiterVal = $homeLimiterVal
        HomeScoreVal = $homeScoreVal
        LblScheduleStatus = $lblScheduleStatus
        RamMain = $ramCard.Main
        RamStat = $ramCard.Stat
    }
}

function Add-GuiCleanupPage {
    param($Page, $Theme)
    $t = $Theme
    $col = New-OneColumn $Page $t
    [void](Add-PageTitle $col $t 'Cleanup')
    $lblCleanupLive = Add-LiveStatus $col $t 'Ready - preview sizes or run cleanup.'

    $actions = New-ButtonRow $t
    $btnPreview = New-PremiumButton 'Preview sizes' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(150, 44)) 'Ghost'
    $btnCleanup = New-PremiumButton 'Run Cleanup' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(180, 44)) 'Primary'
    Add-RowButton $actions $btnPreview 150
    Add-RowButton $actions $btnCleanup 180
    $col.Controls.Add($actions)

    Add-Hint $col $t 'Safe free-space cleanup. Preview sizes first. Browser caches cover all profiles. Launcher caches need confirmation. The Windows Update download-cache wipe is opt-in.' | Out-Null

    $daysRow = New-InlineRow $t
    $daysLbl = New-BodyLabel 'Temp older than (days)' $t.Text (New-Object System.Drawing.Font('Segoe UI', 10))
    Set-LabelChrome $daysLbl $t.Bg
    $daysLbl.Margin = New-Object System.Windows.Forms.Padding(0, 8, 12, 0)
    $daysNum = New-Object System.Windows.Forms.NumericUpDown
    $daysNum.Minimum = 0
    $daysNum.Maximum = 30
    $daysNum.Value = 2
    $daysNum.Width = 72
    $daysNum.BackColor = $t.PanelAlt
    $daysNum.ForeColor = $t.Text
    $daysNum.BorderStyle = 'FixedSingle'
    $daysNum.Margin = New-Object System.Windows.Forms.Padding(0, 6, 0, 0)
    $daysRow.Controls.Add($daysLbl)
    $daysRow.Controls.Add($daysNum)
    $col.Controls.Add($daysRow)

    $chkCleanShader = New-StackCheck 'GPU shader caches' $true
    $chkSteam = New-StackCheck 'Steam downloading cache' $false
    $chkEpic = New-StackCheck 'Epic cache / logs / Data / EMS / staging' $false
    $chkRiot = New-StackCheck 'Riot Client cache/logs' $false
    $chkWuCache = New-StackCheck 'Windows Update download cache (stops wuauserv briefly)' $false
    foreach ($chk in @($chkCleanShader, $chkSteam, $chkEpic, $chkRiot, $chkWuCache)) {
        $col.Controls.Add($chk)
    }

    return [ordered]@{
        BtnCleanup = $btnCleanup
        BtnPreview = $btnPreview
        ChkCleanShader = $chkCleanShader
        ChkEpic = $chkEpic
        ChkRiot = $chkRiot
        ChkSteam = $chkSteam
        ChkWuCache = $chkWuCache
        DaysNum = $daysNum
        LblCleanupLive = $lblCleanupLive
    }
}

function Add-GuiUpdatesPage {
    param($Page, $Theme)
    $t = $Theme
    $col = New-OneColumn $Page $t
    [void](Add-PageTitle $col $t 'Updates')
    $lblUpdatesLive = Add-LiveStatus $col $t 'Ready - Windows Update and winget when you need them.'

    $actions = New-ButtonRow $t
    $btnUpdates = New-PremiumButton 'Run Updates' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(170, 44)) 'Primary'
    $btnAmd = New-PremiumButton 'Open AMD Adrenalin' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(190, 44)) 'Ghost'
    $btnNv = New-PremiumButton 'Open NVIDIA App' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(170, 44)) 'Ghost'
    Add-RowButton $actions $btnUpdates 170
    Add-RowButton $actions $btnAmd 190
    Add-RowButton $actions $btnNv 170
    $col.Controls.Add($actions)

    Add-Hint $col $t 'Installs Windows Update, then every normal winget app in one silent pass. Apps winget excludes from that pass (such as Unity editors) get their own silent upgrade and a result in the log. Self-updaters (Roblox, Discord, Steam, Epic) are skipped. Apps whose version winget cannot read are named and left alone.' | Out-Null

    $chkUpdRestore = New-StackCheck 'Create restore point first' $true
    $chkUpdWU = New-StackCheck 'Windows Update' $true
    $chkUpdWinget = New-StackCheck 'winget upgrades' $true
    foreach ($chk in @($chkUpdRestore, $chkUpdWU, $chkUpdWinget)) {
        $col.Controls.Add($chk)
    }

    return [ordered]@{
        BtnAmd = $btnAmd
        BtnNv = $btnNv
        BtnUpdates = $btnUpdates
        ChkUpdRestore = $chkUpdRestore
        ChkUpdWinget = $chkUpdWinget
        ChkUpdWU = $chkUpdWU
        LblUpdatesLive = $lblUpdatesLive
    }
}

function Add-GuiGamingPage {
    param($Page, $Theme)
    $t = $Theme
    $cols = New-TwoColumn $Page $t 58
    $left = $cols.Left
    $right = $cols.Right

    [void](Add-PageTitle $left $t 'Gaming')
    $optScoreVal = New-BodyLabel '--' $t.Accent (New-Object System.Drawing.Font('Segoe UI Semibold', 28))
    Set-LabelChrome $optScoreVal $t.Bg
    $optScoreVal.Margin = New-Object System.Windows.Forms.Padding(0, 0, 16, 0)
    $optGradeVal = New-BodyLabel '/100' $t.Text (New-Object System.Drawing.Font('Segoe UI Semibold', 12))
    Set-LabelChrome $optGradeVal $t.Bg
    $optGradeVal.Margin = New-Object System.Windows.Forms.Padding(0, 18, 0, 0)
    $scoreRow = New-InlineRow $t
    $scoreRow.Controls.Add($optScoreVal)
    $scoreRow.Controls.Add($optGradeVal)
    $left.Controls.Add($scoreRow)

    $optLimiterVal = Add-Hint $left $t 'Scanning...'
    $optLimiterVal.ForeColor = $t.Text
    $fixesTitle = Add-Hint $left $t 'Top fixes'
    $fixesTitle.ForeColor = $t.Text
    $fixesTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9.5)
    $optFixesVal = Add-Hint $left $t ''

    $rowGm = New-GameStatusRow 'E7FC' 'Game Mode'
    $rowDvr = New-GameStatusRow 'E722' 'Xbox Game DVR'
    $rowRelive = New-GameStatusRow 'E7F4' 'AMD ReLive'
    $rowPower = New-GameStatusRow 'E945' 'Power Plan'
    $rowDiscord = New-GameStatusRow 'E8BD' 'Discord HW accel'
    foreach ($row in @($rowGm.Panel, $rowDvr.Panel, $rowRelive.Panel, $rowPower.Panel, $rowDiscord.Panel)) {
        $row.Dock = 'None'
        $row.Tag = 'fillwidth'
        $row.Margin = New-Object System.Windows.Forms.Padding(0, 2, 0, 2)
        $left.Controls.Add($row)
    }

    [void](Add-PageTitle $right $t 'Actions')
    $btnGamingOpt = New-PremiumButton 'Apply gaming optimize' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(240, 42)) 'Primary'
    $btnApplyOptFixes = New-PremiumButton 'Apply recommended fixes' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(240, 42)) 'Ghost'
    $btnFixPower = New-PremiumButton 'Fix power plan (Ultimate)' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(240, 42)) 'Ghost'
    $btnRestorePower = New-PremiumButton 'Restore previous power plan' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(240, 42)) 'Ghost'
    $btnDiscordOff = New-PremiumButton 'Discord HW accel OFF' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(240, 42)) 'Ghost'
    $btnScanScore = New-PremiumButton 'Scan optimization score' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(240, 42)) 'Ghost'
    $btnRefreshGame = New-PremiumButton 'Refresh status' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(240, 42)) 'Ghost'
    foreach ($pair in @(
        @{ B = $btnGamingOpt; W = 240 },
        @{ B = $btnApplyOptFixes; W = 240 },
        @{ B = $btnFixPower; W = 240 },
        @{ B = $btnRestorePower; W = 240 },
        @{ B = $btnDiscordOff; W = 240 },
        @{ B = $btnScanScore; W = 240 },
        @{ B = $btnRefreshGame; W = 240 }
    )) {
        $line = New-ButtonRow $t
        Add-RowButton $line $pair.B $pair.W
        $right.Controls.Add($line)
    }
    Add-Hint $right $t 'Score is config and setup for how the PC feels in games, not a measure of GPU power. Fullscreen and an FPS cap near the refresh rate help 1% lows.' | Out-Null

    return [ordered]@{
        BtnApplyOptFixes = $btnApplyOptFixes
        BtnDiscordOff = $btnDiscordOff
        BtnFixPower = $btnFixPower
        BtnRestorePower = $btnRestorePower
        BtnGamingOpt = $btnGamingOpt
        BtnRefreshGame = $btnRefreshGame
        BtnScanScore = $btnScanScore
        DiscordVal = $rowDiscord.Value
        GameDvrVal = $rowDvr.Value
        GameModeVal = $rowGm.Value
        OptFixesVal = $optFixesVal
        OptGradeVal = $optGradeVal
        OptLimiterVal = $optLimiterVal
        OptScoreVal = $optScoreVal
        PowerVal = $rowPower.Value
        ReLiveVal = $rowRelive.Value
    }
}

function Add-GuiRepairPage {
    param($Page, $Theme)
    $t = $Theme
    $col = New-OneColumn $Page $t
    [void](Add-PageTitle $col $t 'Repair')
    $lblRepairLive = Add-LiveStatus $col $t 'Ready - only run when Windows feels broken.'

    $actions = New-ButtonRow $t
    $btnRepair = New-PremiumButton 'Run DISM + SFC' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(190, 46)) 'Danger'
    $btnRestoreOnly = New-PremiumButton 'Restore point only' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(180, 46)) 'Ghost'
    Add-RowButton $actions $btnRepair 190
    Add-RowButton $actions $btnRestoreOnly 180
    $col.Controls.Add($actions)

    Add-Hint $col $t 'Only when Windows feels broken. DISM and SFC can take 10-30 minutes or longer.' | Out-Null
    $chkRepRestore = New-StackCheck 'Create restore point first' $true
    $col.Controls.Add($chkRepRestore)

    return [ordered]@{
        BtnRepair = $btnRepair
        BtnRestoreOnly = $btnRestoreOnly
        ChkRepRestore = $chkRepRestore
        LblRepairLive = $lblRepairLive
    }
}

function Add-GuiDevicePage {
    param($Page, $Theme)
    $t = $Theme
    $cols = New-TwoColumn $Page $t 60
    $left = $cols.Left
    $right = $cols.Right

    [void](Add-PageTitle $left $t 'Device')
    $hostBox = New-Object System.Windows.Forms.Panel
    $hostBox.Height = 360
    $hostBox.Tag = 'fillwidth'
    $hostBox.BackColor = $t.Panel
    $hostBox.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 8)
    $hostBox.Padding = New-Object System.Windows.Forms.Padding(12)
    $deviceSummary = New-Object System.Windows.Forms.TextBox
    $deviceSummary.Multiline = $true
    $deviceSummary.ReadOnly = $true
    $deviceSummary.ScrollBars = 'Vertical'
    $deviceSummary.BorderStyle = 'None'
    $deviceSummary.Dock = 'Fill'
    $deviceSummary.BackColor = $t.Panel
    $deviceSummary.ForeColor = $t.Text
    $deviceSummary.Font = New-Object System.Drawing.Font('Consolas', 10)
    $deviceSummary.WordWrap = $true
    $hostBox.Controls.Add($deviceSummary)
    $left.Controls.Add($hostBox)

    [void](Add-PageTitle $right $t 'Quick actions')
    $btnRefreshDevice = New-PremiumButton 'Refresh' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(240, 40)) 'Ghost'
    $btnCopyRamTip = New-PremiumButton 'Copy RAM upgrade tip' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(240, 40)) 'Ghost'
    $btnOpenStorage = New-PremiumButton 'Open Storage settings' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(240, 40)) 'Muted'
    $btnCheckUpdate = New-PremiumButton 'Check / install app update' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(240, 40)) 'Ghost'
    $btnRestartNow = New-PremiumButton 'Restart PC now' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(240, 40)) 'Danger'
    foreach ($pair in @(
        @{ B = $btnRefreshDevice; W = 220 },
        @{ B = $btnCopyRamTip; W = 220 },
        @{ B = $btnOpenStorage; W = 220 },
        @{ B = $btnCheckUpdate; W = 220 },
        @{ B = $btnRestartNow; W = 220 }
    )) {
        $line = New-ButtonRow $t
        Add-RowButton $line $pair.B $pair.W
        $right.Controls.Add($line)
    }
    Add-Hint $right $t 'The optimization score lives on Gaming. Power plan and Game Mode fixes are there too.' | Out-Null

    return [ordered]@{
        BtnCheckUpdate = $btnCheckUpdate
        BtnCopyRamTip = $btnCopyRamTip
        BtnOpenStorage = $btnOpenStorage
        BtnRefreshDevice = $btnRefreshDevice
        BtnRestartNow = $btnRestartNow
        DeviceSummary = $deviceSummary
    }
}
