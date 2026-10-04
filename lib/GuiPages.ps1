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
                    $innerW = $w - $c.Padding.Horizontal
                    if ($innerW -lt 48) { $innerW = 48 }
                    # A child we just resized sits at Y=0 until the flow layout
                    # finishes, so its Bottom can look shorter than the rows above
                    # it. Sum each child's height and margins instead.
                    $flowY = $c.Padding.Top
                    foreach ($child in @($c.Controls)) {
                        $cmTop = 0
                        $cmBot = 0
                        try { $cmTop = $child.Margin.Top; $cmBot = $child.Margin.Bottom } catch { }
                        $ch = $child.Height
                        if ([string]$child.Tag -eq 'wrap') {
                            $measureW = [Math]::Max(40, $innerW - 4)
                            if ($child -is [System.Windows.Forms.CheckBox]) { $measureW = [Math]::Max(40, $innerW - 28) }
                            $proposed = New-Object System.Drawing.Size($measureW, 4000)
                            $measured = [System.Windows.Forms.TextRenderer]::MeasureText([string]$child.Text, $child.Font, $proposed, $flags)
                            $padY = 0
                            try { $padY = $child.Padding.Vertical } catch { }
                            $ch = $measured.Height + $padY + 8
                            if ($child -is [System.Windows.Forms.CheckBox] -and $ch -lt 28) { $ch = 28 }
                            if ($ch -lt 20) { $ch = 20 }
                            $child.AutoSize = $false
                            $child.MaximumSize = New-Object System.Drawing.Size($innerW, 0)
                            if ($child.Height -ne $ch) { $child.Height = $ch }
                        }
                        if ($ch -lt 8) { $ch = 24 }
                        $flowY += $cmTop + $ch + $cmBot
                    }
                    $h = $flowY + $c.Padding.Bottom + 4
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

# WinForms raises Resize and TextChanged outside the script scope, so a plain
# call to Update-StackLayout becomes "the term is not recognized".
$Script:StackLayoutFn = ${function:Update-StackLayout}
$Script:CardLayoutGate = @{ Depth = 0 }
$Script:StackLayoutWarnGate = @{ Sent = $false }
$Script:LayoutWarnFn = $null
if (Get-Command Write-Warn -EA SilentlyContinue) { $Script:LayoutWarnFn = ${function:Write-Warn} }
Set-Item -Path 'function:global:Update-StackLayout' -Value $Script:StackLayoutFn

function New-Column($Theme) {
    $col = New-Object System.Windows.Forms.Panel
    $col.Tag = 'stack'
    $col.Dock = 'Fill'
    $col.AutoScroll = $true
    $col.BackColor = $Theme.Bg
    $col.Padding = New-Object System.Windows.Forms.Padding(16, 12, 12, 16)
    $layoutFn = $Script:StackLayoutFn
    $warnFn = $Script:LayoutWarnFn
    $warnGate = $Script:StackLayoutWarnGate
    $col.Add_Resize({
        param($s, $e)
        try { & $layoutFn $s } catch {
            if ($warnGate -and -not $warnGate.Sent) {
                $warnGate.Sent = $true
                if ($warnFn) { try { & $warnFn ("Page layout: {0}" -f $_.Exception.Message) } catch { } }
            }
        }
    }.GetNewClosure())
    $col.Add_ControlAdded({
        param($s, $e)
        try { & $layoutFn $s } catch {
            if ($warnGate -and -not $warnGate.Sent) {
                $warnGate.Sent = $true
                if ($warnFn) { try { & $warnFn ("Page layout: {0}" -f $_.Exception.Message) } catch { } }
            }
        }
    }.GetNewClosure())
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
    $layoutFn = $Script:StackLayoutFn
    $warnFn = $Script:LayoutWarnFn
    $warnGate = $Script:StackLayoutWarnGate
    $lbl.Add_TextChanged({
        param($sender, $e)
        $p = $sender.Parent
        while ($p -and [string]$p.Tag -ne 'stack') { $p = $p.Parent }
        if ($p) {
            try { & $layoutFn $p } catch {
                if ($warnGate -and -not $warnGate.Sent) {
                    $warnGate.Sent = $true
                    if ($warnFn) { try { & $warnFn ("Page layout: {0}" -f $_.Exception.Message) } catch { } }
                }
            }
        }
    }.GetNewClosure())
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
    $cols = New-TwoColumn $Page $t 58
    $left = $cols.Left
    $right = $cols.Right
    $titleFont = New-Object System.Drawing.Font('Segoe UI Semibold', 11)
    $smallFont = New-Object System.Drawing.Font('Segoe UI', 9)

    [void](Add-PageTitle $left $t 'Home')
    $sub = Add-Hint $left $t 'Setup score. Hardware you already own is part of the number. Top fixes are what you can change.'
    $sub.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 12)

    $scoreCard = New-FigmaCard $t
    $scoreCard.Controls.Add((New-CardLabel $t 'Setup score' $t.Muted $smallFont 6))
    $homeScoreVal = New-BodyLabel '--' $t.Text (New-Object System.Drawing.Font('Segoe UI Semibold', 26))
    Set-LabelChrome $homeScoreVal $t.Panel
    $homeGradeVal = New-BodyLabel 'Reading hardware...' $t.Accent (New-Object System.Drawing.Font('Segoe UI Semibold', 11))
    Set-LabelChrome $homeGradeVal $t.Panel
    $homeLimiterVal = New-CardLabel $t 'Scanning...' $t.Muted $smallFont 4
    $homeSecurityVal = New-CardLabel $t 'Security: Reading...' $t.Muted $smallFont 4
    $homeFixesVal = New-CardLabel $t '' $t.Muted $smallFont 0
    foreach ($lbl in @($homeScoreVal, $homeGradeVal, $homeLimiterVal, $homeSecurityVal, $homeFixesVal)) {
        $scoreCard.Controls.Add($lbl)
    }
    $left.Controls.Add($scoreCard)

    $cpuCard = New-MetricCard 'E950' 'CPU'
    $gpuCard = New-MetricCard 'E7F4' 'GPU'
    $ramCard = New-MetricCard 'EDA2' 'RAM'
    foreach ($card in @($cpuCard.Panel, $gpuCard.Panel, $ramCard.Panel)) {
        $card.Dock = 'None'
        $card.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
        $left.Controls.Add($card)
    }

    $actions = New-FigmaCard $t
    $actions.Controls.Add((New-CardLabel $t 'Actions' $t.Text $titleFont 8))
    $btnFixMyPc = Add-CardButton $actions (New-PremiumButton 'Fix my PC for gaming' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(280, 44)) 'Cta')
    $btnWeekly = Add-CardButton $actions (New-PremiumButton 'Run Weekly Full' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(280, 40)) 'Primary')
    $btnRefreshHome = Add-CardButton $actions (New-PremiumButton 'Refresh' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(280, 36)) 'Ghost')
    $right.Controls.Add($actions)

    $opts = New-FigmaCard $t
    $opts.Controls.Add((New-CardLabel $t 'Weekly Full options' $t.Text $titleFont 8))
    $chkHomeRestore = New-StackCheck 'Create restore point' $true
    $chkHomeShader = New-StackCheck 'Clear GPU shader caches' $true
    $chkHomeGaming = New-StackCheck 'Apply gaming optimizations' $true
    $chkHomeWU = New-StackCheck 'Windows Update (slow)' $false
    $chkHomeWinget = New-StackCheck 'winget app upgrades (slow)' $false
    foreach ($chk in @($chkHomeRestore, $chkHomeShader, $chkHomeGaming, $chkHomeWU, $chkHomeWinget)) {
        $chk.BackColor = $t.Panel
        $chk.Margin = New-Object System.Windows.Forms.Padding(0, 2, 0, 4)
        $opts.Controls.Add($chk)
    }
    $right.Controls.Add($opts)

    $sched = New-FigmaCard $t
    $sched.Controls.Add((New-CardLabel $t 'Presets and schedule' $t.Text $titleFont 8))
    $btnPresetGamer = Add-CardButton $sched (New-PremiumButton 'Gamer' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(280, 34)) 'Ghost')
    $btnPresetQuiet = Add-CardButton $sched (New-PremiumButton 'Quiet' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(280, 34)) 'Ghost')
    $btnPresetFull = Add-CardButton $sched (New-PremiumButton 'Full' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(280, 34)) 'Ghost')
    $chkScheduleWeekly = New-StackCheck 'Schedule Weekly Full (Sundays 6 PM)' $false
    $chkScheduleUpdates = New-StackCheck 'Weekly task may install updates' $false
    $chkScheduleGaming = New-StackCheck 'Weekly task may clear shaders and apply gaming settings' $false
    foreach ($chk in @($chkScheduleWeekly, $chkScheduleUpdates, $chkScheduleGaming)) {
        $chk.BackColor = $t.Panel
        $chk.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 4)
        $sched.Controls.Add($chk)
    }
    $lblScheduleStatus = New-CardLabel $t 'Weekly schedule: off' $t.Text $smallFont 4
    $lblLastScheduledRun = New-CardLabel $t 'No weekly run recorded yet.' $t.Muted $smallFont 4
    $sched.Controls.Add($lblScheduleStatus)
    $sched.Controls.Add($lblLastScheduledRun)
    $sched.Controls.Add((New-CardLabel $t 'The weekly task cleans temps and browser caches while you are signed in. Updates, shader cleanup, and gaming settings run only when the matching box is on. Home shows the last run the next time you open the app.' $t.Muted $smallFont 0))
    $right.Controls.Add($sched)

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
        ChkScheduleUpdates = $chkScheduleUpdates
        ChkScheduleGaming = $chkScheduleGaming
        ChkScheduleWeekly = $chkScheduleWeekly
        CpuMain = $cpuCard.Main
        CpuStat = $cpuCard.Stat
        GpuMain = $gpuCard.Main
        GpuStat = $gpuCard.Stat
        HomeFixesVal = $homeFixesVal
        HomeGradeVal = $homeGradeVal
        HomeLimiterVal = $homeLimiterVal
        HomeScoreVal = $homeScoreVal
        HomeSecurityVal = $homeSecurityVal
        LblLastScheduledRun = $lblLastScheduledRun
        LblScheduleStatus = $lblScheduleStatus
        RamMain = $ramCard.Main
        RamStat = $ramCard.Stat
    }
}

function Add-GuiCleanupPage {
    param($Page, $Theme)
    $t = $Theme
    $cols = New-TwoColumn $Page $t 62
    $left = $cols.Left
    $right = $cols.Right
    $titleFont = New-Object System.Drawing.Font('Segoe UI Semibold', 11)
    $smallFont = New-Object System.Drawing.Font('Segoe UI', 9)

    [void](Add-PageTitle $left $t 'Cleanup')
    $sub = Add-Hint $left $t 'Safe free-space cleanup. Preview sizes first.'
    $sub.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 12)

    $what = New-FigmaCard $t
    $what.Controls.Add((New-CardLabel $t 'What this cleans' $t.Text $titleFont 8))
    $what.Controls.Add((New-CardLabel $t 'Browser caches cover all profiles. Launcher caches need confirmation. The Windows Update download-cache wipe is opt-in.' $t.Muted $smallFont 8))
    $daysRow = New-Object System.Windows.Forms.Panel
    $daysRow.Height = 36
    $daysRow.BackColor = $t.Panel
    $daysRow.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
    $daysLbl = New-Object System.Windows.Forms.Label
    $daysLbl.Text = 'Temp older than (days)'
    $daysLbl.ForeColor = $t.Text
    $daysLbl.BackColor = $t.Panel
    $daysLbl.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $daysLbl.TextAlign = 'MiddleLeft'
    $daysNum = New-Object System.Windows.Forms.NumericUpDown
    $daysNum.Minimum = 0
    $daysNum.Maximum = 30
    $daysNum.Value = 2
    $daysNum.Width = 72
    $daysNum.BackColor = $t.PanelAlt
    $daysNum.ForeColor = $t.Text
    $daysNum.BorderStyle = 'FixedSingle'
    $daysRow.Controls.Add($daysLbl)
    $daysRow.Controls.Add($daysNum)
    $daysRow.Add_Resize({
        param($s, $e)
        $span = $s.ClientSize.Width
        $daysNum.SetBounds(($span - 72), 4, 72, 26)
        $daysLbl.SetBounds(0, 4, [Math]::Max(40, $span - 84), 26)
    }.GetNewClosure())
    $what.Controls.Add($daysRow)
    $chkCleanShader = New-StackCheck 'GPU shader caches' $true
    $chkSteam = New-StackCheck 'Steam downloading cache' $false
    $chkEpic = New-StackCheck 'Epic cache / logs / Data / EMS / staging' $false
    $chkRiot = New-StackCheck 'Riot Client cache/logs' $false
    $chkWuCache = New-StackCheck 'Windows Update download cache (stops wuauserv briefly)' $false
    foreach ($chk in @($chkCleanShader, $chkSteam, $chkEpic, $chkRiot, $chkWuCache)) {
        $chk.BackColor = $t.Panel
        $chk.Margin = New-Object System.Windows.Forms.Padding(0, 2, 0, 4)
        $what.Controls.Add($chk)
    }
    $left.Controls.Add($what)

    $lblCleanupLive = Add-LiveStatus $right $t 'Ready - preview sizes or run cleanup.'
    $lblCleanupLive.ForeColor = $t.Success
    $lblCleanupLive.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 12)
    $run = New-FigmaCard $t
    $run.Controls.Add((New-CardLabel $t 'Run' $t.Text $titleFont 8))
    $btnPreview = Add-CardButton $run (New-PremiumButton 'Preview sizes' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(280, 40)) 'Ghost')
    $btnCleanup = Add-CardButton $run (New-PremiumButton 'Run Cleanup' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(280, 44)) 'Primary')
    $right.Controls.Add($run)

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
    $cols = New-TwoColumn $Page $t 62
    $left = $cols.Left
    $right = $cols.Right
    $titleFont = New-Object System.Drawing.Font('Segoe UI Semibold', 11)
    $smallFont = New-Object System.Drawing.Font('Segoe UI', 9)

    [void](Add-PageTitle $left $t 'Updates')
    $sub = Add-Hint $left $t 'Windows Update and winget, only when you ask.'
    $sub.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 12)

    $about = New-FigmaCard $t
    $about.Controls.Add((New-CardLabel $t 'What a run does' $t.Text $titleFont 8))
    $about.Controls.Add((New-CardLabel $t 'Installs Windows Update, then asks which winget apps to update.' $t.Muted $smallFont 4))
    $about.Controls.Add((New-CardLabel $t 'Leave every app checked for one silent pass. Uncheck any, and only the checked apps are installed. Unity editors are in that list too.' $t.Muted $smallFont 4))
    $about.Controls.Add((New-CardLabel $t 'Self-updaters (Roblox, Discord, Steam, Epic) are skipped. Apps whose version winget cannot read are named and left alone.' $t.Muted $smallFont 0))
    $left.Controls.Add($about)

    $lblUpdatesLive = Add-LiveStatus $right $t 'Ready - Windows Update and winget when you need them.'
    $lblUpdatesLive.ForeColor = $t.Success
    $lblUpdatesLive.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 12)
    $actions = New-FigmaCard $t
    $actions.Controls.Add((New-CardLabel $t 'Run updates' $t.Text $titleFont 8))
    $chkUpdRestore = New-StackCheck 'Create restore point first' $true
    $chkUpdWU = New-StackCheck 'Windows Update' $true
    $chkUpdWinget = New-StackCheck 'winget upgrades' $true
    foreach ($chk in @($chkUpdRestore, $chkUpdWU, $chkUpdWinget)) {
        $chk.BackColor = $t.Panel
        $chk.Margin = New-Object System.Windows.Forms.Padding(0, 2, 0, 4)
        $actions.Controls.Add($chk)
    }
    $btnUpdates = Add-CardButton $actions (New-PremiumButton 'Run Updates' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(280, 44)) 'Primary')
    $btnAmd = Add-CardButton $actions (New-PremiumButton 'Open AMD Adrenalin' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(280, 36)) 'Ghost')
    $btnNv = Add-CardButton $actions (New-PremiumButton 'Open NVIDIA App' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(280, 36)) 'Ghost')
    $right.Controls.Add($actions)

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

function New-FigmaCard($Theme) {
    $card = New-Object System.Windows.Forms.FlowLayoutPanel
    $card.FlowDirection = 'TopDown'
    $card.WrapContents = $false
    $card.AutoScroll = $false
    $card.Height = 280
    $card.BackColor = $Theme.Panel
    $card.Padding = New-Object System.Windows.Forms.Padding(16, 14, 16, 14)
    $card.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 14)
    Add-PanelBorder $card $Theme.Border -Radius 10
    $card.Add_Resize({
        param($s, $e)
        $inner = $s.ClientSize.Width - $s.Padding.Horizontal
        if ($inner -lt 48) { return }
        foreach ($child in @($s.Controls)) {
            if ($child.Width -ne $inner) { $child.Width = $inner }
            if ([string]$child.Tag -eq 'wrap') {
                $child.MaximumSize = New-Object System.Drawing.Size($inner, 0)
            }
        }
    })
    return $card
}

function New-CardLabel($Theme, [string]$Text, $Color, $Font, [int]$Bottom = 6) {
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $Text
    $lbl.ForeColor = $Color
    $lbl.Font = $Font
    $lbl.AutoSize = $true
    $lbl.Tag = 'wrap'
    $lbl.BackColor = $Theme.Panel
    $lbl.Margin = New-Object System.Windows.Forms.Padding(0, 2, 0, $Bottom)
    $lbl.UseMnemonic = $false
    # Measure the wrapped height here. A deferred relayout re-entered DoEvents
    # forever when the layout itself touched the label again.
    $layoutFn = $Script:StackLayoutFn
    $gate = $Script:CardLayoutGate
    $warnFn = $Script:LayoutWarnFn
    $warnGate = $Script:StackLayoutWarnGate
    $lbl.Add_TextChanged({
        param($sender, $e)
        if ($gate.Depth -gt 0) { return }
        $box = $sender
        if ($box.IsDisposed) { return }
        $p = $box.Parent
        while ($p -and [string]$p.Tag -ne 'stack') { $p = $p.Parent }
        if (-not $p) { return }
        $gate.Depth = 1
        try {
            $width = 0
            try { $width = $box.MaximumSize.Width } catch { }
            if ($width -lt 48) { $width = $box.Width }
            if ($width -lt 48) { $width = 320 }
            $flags = [System.Windows.Forms.TextFormatFlags]::WordBreak -bor [System.Windows.Forms.TextFormatFlags]::TextBoxControl
            $proposed = New-Object System.Drawing.Size($width, 4000)
            $measured = [System.Windows.Forms.TextRenderer]::MeasureText([string]$box.Text, $box.Font, $proposed, $flags)
            $h = $measured.Height + 4
            if ($h -lt 20) { $h = 20 }
            $box.AutoSize = $false
            if ($box.Height -ne $h) { $box.Height = $h }
            try { & $layoutFn $p } catch {
                if ($warnGate -and -not $warnGate.Sent) {
                    $warnGate.Sent = $true
                    if ($warnFn) { try { & $warnFn ("Page layout: {0}" -f $_.Exception.Message) } catch { } }
                }
            }
        } finally {
            $gate.Depth = 0
        }
    }.GetNewClosure())
    return $lbl
}

function Add-CardButton($Card, $Button) {
    $Button.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
    $Button.Dock = 'None'
    $Card.Controls.Add($Button)
    return $Button
}

function New-SpecRow($Theme, [string]$Caption) {
    $row = New-Object System.Windows.Forms.Panel
    $row.Height = 36
    $row.Margin = New-Object System.Windows.Forms.Padding(0)
    $row.BackColor = $Theme.Panel
    $name = New-Object System.Windows.Forms.Label
    $name.Text = $Caption
    $name.ForeColor = $Theme.Muted
    $name.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
    $name.TextAlign = 'MiddleLeft'
    $name.BackColor = $Theme.Panel
    $val = New-Object System.Windows.Forms.Label
    $val.Text = '-'
    $val.ForeColor = $Theme.Text
    $val.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9.5)
    $val.TextAlign = 'MiddleRight'
    $val.AutoEllipsis = $true
    $val.BackColor = $Theme.Panel
    $row.Controls.Add($name)
    $row.Controls.Add($val)
    $row.Add_Resize({
        param($s, $e)
        $span = $s.ClientSize.Width
        if ($span -lt 80) { return }
        $valW = [Math]::Min(280, [Math]::Max(100, [int]($span * 0.62)))
        $valLeft = $span - $valW
        $val.SetBounds($valLeft, 4, $valW, 26)
        $name.SetBounds(0, 4, [Math]::Max(40, $valLeft - 8), 26)
    }.GetNewClosure())
    $row.Add_Paint({
        param($sender, $e)
        try {
            $pen = New-Object System.Drawing.Pen $Script:Theme.Border, 1
            $e.Graphics.DrawLine($pen, 0, ($sender.Height - 1), $sender.Width, ($sender.Height - 1))
            $pen.Dispose()
        } catch { }
    })
    return @{ Panel = $row; Value = $val }
}

function Add-GuiGamingPage {
    param($Page, $Theme)
    $t = $Theme
    $cols = New-TwoColumn $Page $t 62
    $left = $cols.Left
    $right = $cols.Right
    $titleFont = New-Object System.Drawing.Font('Segoe UI Semibold', 11)
    $bodyFont = New-Object System.Drawing.Font('Segoe UI', 9.5)
    $smallFont = New-Object System.Drawing.Font('Segoe UI', 9)

    [void](Add-PageTitle $left $t 'Gaming')
    $sub = Add-Hint $left $t 'Config and setup for how the PC feels in games'
    $sub.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 12)

    $scoreCard = New-FigmaCard $t
    $scoreCard.Controls.Add((New-CardLabel $t 'Gaming Optimization' $t.Muted $smallFont 8))
    $hero = New-Object System.Windows.Forms.Panel
    $hero.Height = 108
    $hero.BackColor = $t.Panel
    $hero.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 4)
    $optScoreVal = New-Object System.Windows.Forms.Label
    $optScoreVal.Text = '--'
    $optScoreVal.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 26)
    $optScoreVal.ForeColor = $t.Text
    $optScoreVal.BackColor = $t.Panel
    $optScoreVal.AutoSize = $false
    $slash = New-Object System.Windows.Forms.Label
    $slash.Text = '/ 100'
    $slash.Font = $bodyFont
    $slash.ForeColor = $t.Muted
    $slash.BackColor = $t.Panel
    $slash.AutoSize = $false
    $optLimiterVal = New-Object System.Windows.Forms.Label
    $optLimiterVal.Text = 'Scanning...'
    $optLimiterVal.Font = $smallFont
    $optLimiterVal.ForeColor = $t.Muted
    $optLimiterVal.BackColor = $t.Panel
    $optLimiterVal.AutoSize = $false
    $badge = New-Object System.Windows.Forms.Panel
    $badge.Size = New-Object System.Drawing.Size(52, 52)
    $badge.BackColor = $t.Accent
    $optGradeLetter = New-Object System.Windows.Forms.Label
    $optGradeLetter.Text = '-'
    $optGradeLetter.Dock = 'Fill'
    $optGradeLetter.TextAlign = 'MiddleCenter'
    $optGradeLetter.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 16)
    $optGradeLetter.ForeColor = $t.Bg
    $optGradeLetter.BackColor = $t.Accent
    $badge.Controls.Add($optGradeLetter)
    $optGradeVal = New-Object System.Windows.Forms.Label
    $optGradeVal.Text = ''
    $optGradeVal.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
    $optGradeVal.ForeColor = $t.Accent
    $optGradeVal.BackColor = $t.Panel
    $optGradeVal.TextAlign = 'MiddleCenter'
    $optGradeVal.AutoSize = $false
    $hero.Controls.Add($optScoreVal)
    $hero.Controls.Add($slash)
    $hero.Controls.Add($optLimiterVal)
    $hero.Controls.Add($badge)
    $hero.Controls.Add($optGradeVal)
    $hero.Add_Resize({
        param($s, $e)
        $w = $s.ClientSize.Width
        $optScoreVal.SetBounds(0, 0, 110, 42)
        $slash.SetBounds(108, 16, 70, 22)
        $gradeW = 124
        $limitW = [Math]::Max(40, $w - $gradeW - 8)
        $optLimiterVal.SetBounds(0, 46, $limitW, 36)
        $badge.SetBounds(($w - 52), 0, 52, 52)
        $optGradeVal.SetBounds(($w - $gradeW), 54, $gradeW, 22)
    }.GetNewClosure())
    $scoreCard.Controls.Add($hero)
    $left.Controls.Add($scoreCard)

    $statusCard = New-FigmaCard $t
    $statusCard.Controls.Add((New-CardLabel $t 'Live status' $t.Text $titleFont 8))
    $rowGm = New-GameStatusRow 'E7FC' 'Game Mode'
    $rowDvr = New-GameStatusRow 'E722' 'Xbox Game DVR'
    $rowRelive = New-GameStatusRow 'E7F4' 'AMD ReLive'
    $rowPower = New-GameStatusRow 'E945' 'Power Plan'
    $rowDiscord = New-GameStatusRow 'E8BD' 'Discord HW accel'
    foreach ($row in @($rowGm.Panel, $rowDvr.Panel, $rowRelive.Panel, $rowPower.Panel, $rowDiscord.Panel)) {
        $row.Dock = 'None'
        $row.BackColor = $t.PanelAlt
        $row.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
        $statusCard.Controls.Add($row)
    }
    $left.Controls.Add($statusCard)

    $startupCard = New-FigmaCard $t
    $startupCard.Controls.Add((New-CardLabel $t 'Starts with Windows' $t.Text $titleFont 8))
    $gameStartupVal = New-CardLabel $t 'Reading startup apps...' $t.Muted $smallFont 0
    $startupCard.Controls.Add($gameStartupVal)
    $left.Controls.Add($startupCard)

    $fixesCard = New-FigmaCard $t
    $fixesCard.Controls.Add((New-CardLabel $t 'Top fixes' $t.Text $titleFont 8))
    $optFixesVal = New-CardLabel $t 'Scanning...' $t.Muted $smallFont 0
    $fixesCard.Controls.Add($optFixesVal)
    $left.Controls.Add($fixesCard)

    $optStatusPill = Add-LiveStatus $right $t 'Score --'
    $optStatusPill.ForeColor = $t.Success
    $optStatusPill.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 12)

    $actions = New-FigmaCard $t
    $actions.Controls.Add((New-CardLabel $t 'Actions' $t.Text $titleFont 8))
    $btnGamingOpt = Add-CardButton $actions (New-PremiumButton 'Apply gaming optimize' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(280, 44)) 'Primary')
    $btnApplyOptFixes = Add-CardButton $actions (New-PremiumButton 'Apply recommended fixes' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(280, 36)) 'Ghost')
    $btnFixPower = Add-CardButton $actions (New-PremiumButton 'Fix power plan (Ultimate)' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(280, 36)) 'Ghost')
    $btnRestorePower = Add-CardButton $actions (New-PremiumButton 'Restore previous power plan' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(280, 36)) 'Ghost')
    $btnDiscordOff = Add-CardButton $actions (New-PremiumButton 'Discord HW accel OFF' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(280, 36)) 'Ghost')
    $btnOpenStartup = Add-CardButton $actions (New-PremiumButton 'Open Startup apps' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(280, 36)) 'Ghost')
    $btnScanScore = Add-CardButton $actions (New-PremiumButton 'Scan optimization score' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(280, 36)) 'Ghost')
    $btnRefreshGame = Add-CardButton $actions (New-PremiumButton 'Refresh status' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(280, 36)) 'Ghost')
    $hint = New-CardLabel $t 'This number mixes hardware you already own with settings you can change. Top fixes are the part you can change. Fullscreen and an FPS cap near the refresh rate help 1% lows.' $t.Muted $smallFont 0
    $actions.Controls.Add($hint)
    $right.Controls.Add($actions)

    return [ordered]@{
        BtnApplyOptFixes = $btnApplyOptFixes
        BtnDiscordOff = $btnDiscordOff
        BtnFixPower = $btnFixPower
        BtnRestorePower = $btnRestorePower
        BtnGamingOpt = $btnGamingOpt
        BtnOpenStartup = $btnOpenStartup
        BtnRefreshGame = $btnRefreshGame
        GameStartupVal = $gameStartupVal
        BtnScanScore = $btnScanScore
        DiscordVal = $rowDiscord.Value
        GameDvrVal = $rowDvr.Value
        GameModeVal = $rowGm.Value
        OptFixesVal = $optFixesVal
        OptGradeLetter = $optGradeLetter
        OptGradeVal = $optGradeVal
        OptLimiterVal = $optLimiterVal
        OptScoreVal = $optScoreVal
        OptStatusPill = $optStatusPill
        PowerVal = $rowPower.Value
        ReLiveVal = $rowRelive.Value
    }
}

function New-StepRow($Theme, [string]$Title, [string]$Detail, [string]$Time) {
    $row = New-Object System.Windows.Forms.Panel
    $row.Height = 52
    $row.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
    $row.BackColor = $Theme.PanelAlt
    $mark = New-Object System.Windows.Forms.Label
    $mark.Text = [char]0x2713
    $mark.TextAlign = 'MiddleCenter'
    $mark.Font = New-Object System.Drawing.Font('Segoe UI', 8)
    $mark.ForeColor = $Theme.Bg
    $mark.BackColor = $Theme.Accent
    $mark.SetBounds(10, 16, 18, 18)
    $titleLbl = New-Object System.Windows.Forms.Label
    $titleLbl.Text = $Title
    $titleLbl.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9.5)
    $titleLbl.ForeColor = $Theme.Text
    $titleLbl.BackColor = $Theme.PanelAlt
    $detailLbl = New-Object System.Windows.Forms.Label
    $detailLbl.Text = $Detail
    $detailLbl.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
    $detailLbl.ForeColor = $Theme.Muted
    $detailLbl.BackColor = $Theme.PanelAlt
    $timeLbl = New-Object System.Windows.Forms.Label
    $timeLbl.Text = $Time
    $timeLbl.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5)
    $timeLbl.ForeColor = $Theme.Muted
    $timeLbl.BackColor = $Theme.PanelAlt
    $timeLbl.TextAlign = 'MiddleRight'
    $row.Controls.Add($mark)
    $row.Controls.Add($titleLbl)
    $row.Controls.Add($detailLbl)
    $row.Controls.Add($timeLbl)
    $row.Add_Resize({
        param($s, $e)
        $span = $s.ClientSize.Width
        $timeW = 72
        $timeLbl.SetBounds(($span - $timeW - 8), 16, $timeW, 20)
        $textW = [Math]::Max(40, $span - $timeW - 48)
        $titleLbl.SetBounds(36, 6, $textW, 20)
        $detailLbl.SetBounds(36, 26, $textW, 18)
    }.GetNewClosure())
    return $row
}

function Add-GuiRepairPage {
    param($Page, $Theme)
    $t = $Theme
    $cols = New-TwoColumn $Page $t 62
    $left = $cols.Left
    $right = $cols.Right
    $titleFont = New-Object System.Drawing.Font('Segoe UI Semibold', 11)
    $smallFont = New-Object System.Drawing.Font('Segoe UI', 9)

    [void](Add-PageTitle $left $t 'Repair')
    $sub = Add-Hint $left $t 'Only when Windows feels broken'
    $sub.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 12)

    $warn = New-FigmaCard $t
    $warn.Controls.Add((New-CardLabel $t 'Slow and destructive if Windows is healthy' $t.Warn $titleFont 4))
    $warn.Controls.Add((New-CardLabel $t 'DISM and SFC can take 10-30 minutes or longer. Run this only when Windows feels broken. The kit asks you to confirm, and counts success only when the exit code is 0.' $t.Muted $smallFont 0))
    $warn.Add_Paint({
        param($sender, $e)
        try {
            $br = New-Object System.Drawing.SolidBrush $Script:Theme.Warn
            $e.Graphics.FillRectangle($br, 0, 8, 3, ($sender.Height - 16))
            $br.Dispose()
        } catch { }
    })
    $left.Controls.Add($warn)

    $steps = New-FigmaCard $t
    $steps.Controls.Add((New-CardLabel $t 'What this run does' $t.Text $titleFont 8))
    $steps.Controls.Add((New-StepRow $t 'Restore point' 'Created first, so you can roll back' '1 min'))
    $steps.Controls.Add((New-StepRow $t 'DISM RestoreHealth' 'Repairs the component store' '10-20 min'))
    $steps.Controls.Add((New-StepRow $t 'SFC /scannow' 'Checks protected system files' '5-15 min'))
    $left.Controls.Add($steps)

    $before = New-FigmaCard $t
    $before.Controls.Add((New-CardLabel $t 'Before you start' $t.Text $titleFont 6))
    $before.Controls.Add((New-CardLabel $t 'Close games and launchers so files are not in use.' $t.Muted $smallFont 2))
    $before.Controls.Add((New-CardLabel $t 'Keep the PC plugged in. DISM and SFC can take 10-30 minutes.' $t.Muted $smallFont 2))
    $before.Controls.Add((New-CardLabel $t 'If a restart is pending when the run finishes, the kit says so.' $t.Muted $smallFont 0))
    $left.Controls.Add($before)

    $lblRepairLive = Add-LiveStatus $right $t 'No repair running'
    $lblRepairLive.ForeColor = $t.Success
    $lblRepairLive.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 12)

    $actions = New-FigmaCard $t
    $actions.Controls.Add((New-CardLabel $t 'Run repair' $t.Text $titleFont 8))
    $chkRepRestore = New-StackCheck 'Create restore point first' $true
    $chkRepRestore.BackColor = $t.Panel
    $chkRepRestore.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 10)
    $actions.Controls.Add($chkRepRestore)
    $btnRepair = Add-CardButton $actions (New-PremiumButton 'Run DISM + SFC' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(280, 44)) 'Danger')
    $btnRestoreOnly = Add-CardButton $actions (New-PremiumButton 'Restore point only' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(280, 36)) 'Ghost')
    $actions.Controls.Add((New-CardLabel $t 'A restore point is also available on its own if you only want a checkpoint.' $t.Muted $smallFont 0))
    $right.Controls.Add($actions)

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
    $cols = New-TwoColumn $Page $t 62
    $left = $cols.Left
    $right = $cols.Right
    $titleFont = New-Object System.Drawing.Font('Segoe UI Semibold', 11)
    $bodyFont = New-Object System.Drawing.Font('Segoe UI', 9.5)
    $smallFont = New-Object System.Drawing.Font('Segoe UI', 9)

    [void](Add-PageTitle $left $t 'Device')
    $sub = Add-Hint $left $t 'Hardware this PC is running right now'
    $sub.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 12)

    $strip = New-FigmaCard $t
    $hero = New-Object System.Windows.Forms.Panel
    $hero.Height = 72
    $hero.BackColor = $t.Panel
    $hero.Margin = New-Object System.Windows.Forms.Padding(0)
    $badge = New-Object System.Windows.Forms.Panel
    $badge.Size = New-Object System.Drawing.Size(48, 48)
    $badge.BackColor = $t.Accent
    $devGradeLetter = New-Object System.Windows.Forms.Label
    $devGradeLetter.Text = '-'
    $devGradeLetter.Dock = 'Fill'
    $devGradeLetter.TextAlign = 'MiddleCenter'
    $devGradeLetter.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 16)
    $devGradeLetter.ForeColor = $t.Bg
    $devGradeLetter.BackColor = $t.Accent
    $badge.Controls.Add($devGradeLetter)
    $devScoreLine = New-Object System.Windows.Forms.Label
    $devScoreLine.Text = '-- / 100'
    $devScoreLine.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 14)
    $devScoreLine.ForeColor = $t.Text
    $devScoreLine.BackColor = $t.Panel
    $devScoreLine.AutoSize = $false
    $devChip = New-Object System.Windows.Forms.Label
    $devChip.Text = 'Scanning hardware...'
    $devChip.Font = $bodyFont
    $devChip.ForeColor = $t.Muted
    $devChip.BackColor = $t.Panel
    $devChip.AutoSize = $false
    $devChip.AutoEllipsis = $true
    $hero.Controls.Add($badge)
    $hero.Controls.Add($devScoreLine)
    $hero.Controls.Add($devChip)
    $hero.Add_Resize({
        param($s, $e)
        $w = $s.ClientSize.Width
        $badge.SetBounds(0, 4, 48, 48)
        $textW = [Math]::Max(40, $w - 64)
        $devScoreLine.SetBounds(60, 6, $textW, 28)
        $devChip.SetBounds(60, 36, $textW, 22)
    }.GetNewClosure())
    $strip.Controls.Add($hero)
    $left.Controls.Add($strip)

    $specs = New-FigmaCard $t
    $specs.Controls.Add((New-CardLabel $t 'This PC' $t.Text $titleFont 8))
    $rowCpu = New-SpecRow $t 'CPU'
    $rowGpu = New-SpecRow $t 'GPU'
    $rowRam = New-SpecRow $t 'Memory'
    $rowChannels = New-SpecRow $t 'Channels'
    $rowDisk = New-SpecRow $t 'Disk'
    $rowTrim = New-SpecRow $t 'TRIM'
    $rowFree = New-SpecRow $t 'Free on C:'
    $rowPower = New-SpecRow $t 'Power plan'
    $rowReboot = New-SpecRow $t 'Reboot pending'
    foreach ($spec in @($rowCpu, $rowGpu, $rowRam, $rowChannels, $rowDisk, $rowTrim, $rowFree, $rowPower, $rowReboot)) {
        $specs.Controls.Add($spec.Panel)
    }
    $left.Controls.Add($specs)

    $ramCard = New-FigmaCard $t
    $ramCard.Controls.Add((New-CardLabel $t 'RAM tip' $t.Text $titleFont 6))
    $devRamTip = New-CardLabel $t 'Scanning...' $t.Muted $smallFont 0
    $ramCard.Controls.Add($devRamTip)
    $left.Controls.Add($ramCard)

    $devRebootPill = Add-LiveStatus $right $t 'No reboot pending'
    $devRebootPill.ForeColor = $t.Success
    $devRebootPill.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 12)

    $actions = New-FigmaCard $t
    $actions.Controls.Add((New-CardLabel $t 'Actions' $t.Text $titleFont 8))
    $btnCopyRamTip = Add-CardButton $actions (New-PremiumButton 'Copy RAM tip' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(280, 44)) 'Primary')
    $btnOpenStorage = Add-CardButton $actions (New-PremiumButton 'Open Storage settings' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(280, 36)) 'Ghost')
    $btnRefreshDevice = Add-CardButton $actions (New-PremiumButton 'Refresh' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(280, 36)) 'Ghost')
    $btnCheckUpdate = Add-CardButton $actions (New-PremiumButton 'Check / install app update' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(280, 36)) 'Ghost')
    $btnRestartNow = Add-CardButton $actions (New-PremiumButton 'Restart PC now' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(280, 36)) 'Ghost')
    $btnRestartNow.ForeColor = [System.Drawing.Color]::FromArgb(248, 113, 113)
    $actions.Controls.Add((New-CardLabel $t 'The optimization score lives on Gaming. Power plan and Game Mode fixes are there too.' $t.Muted $smallFont 0))
    $right.Controls.Add($actions)

    return [ordered]@{
        BtnCheckUpdate = $btnCheckUpdate
        BtnCopyRamTip = $btnCopyRamTip
        BtnOpenStorage = $btnOpenStorage
        BtnRefreshDevice = $btnRefreshDevice
        BtnRestartNow = $btnRestartNow
        DevChannels = $rowChannels.Value
        DevChip = $devChip
        DevCpu = $rowCpu.Value
        DevDisk = $rowDisk.Value
        DevFree = $rowFree.Value
        DevGpu = $rowGpu.Value
        DevGradeLetter = $devGradeLetter
        DevPower = $rowPower.Value
        DevRam = $rowRam.Value
        DevRamTip = $devRamTip
        DevReboot = $rowReboot.Value
        DevRebootPill = $devRebootPill
        DevScoreLine = $devScoreLine
        DevTrim = $rowTrim.Value
    }
}

function Add-GuiSecurityPage {
    param($Page, $Theme)
    $t = $Theme
    $cols = New-TwoColumn $Page $t 62
    $left = $cols.Left
    $right = $cols.Right
    $titleFont = New-Object System.Drawing.Font('Segoe UI Semibold', 11)
    $smallFont = New-Object System.Drawing.Font('Segoe UI', 9)

    [void](Add-PageTitle $left $t 'Security')
    $sub = Add-Hint $left $t 'Protection status for this PC. Scans run in Windows Security or Malwarebytes, not in this kit.'
    $sub.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 12)

    $strip = New-FigmaCard $t
    $secVerdict = New-BodyLabel 'Reading...' $t.Text (New-Object System.Drawing.Font('Segoe UI Semibold', 22))
    Set-LabelChrome $secVerdict $t.Panel
    $secSummary = New-CardLabel $t 'Checking Defender, firewall, and Malwarebytes.' $t.Muted $smallFont 0
    $strip.Controls.Add($secVerdict)
    $strip.Controls.Add($secSummary)
    $left.Controls.Add($strip)

    $specs = New-FigmaCard $t
    $specs.Controls.Add((New-CardLabel $t 'Protection' $t.Text $titleFont 8))
    $rowRealtime = New-SpecRow $t 'Real-time protection'
    $rowSignatures = New-SpecRow $t 'Signatures'
    $rowQuick = New-SpecRow $t 'Last quick scan'
    $rowFull = New-SpecRow $t 'Last full scan'
    $rowThreats = New-SpecRow $t 'Threats'
    $rowFirewall = New-SpecRow $t 'Firewall'
    $rowMb = New-SpecRow $t 'Malwarebytes'
    foreach ($spec in @($rowRealtime, $rowSignatures, $rowQuick, $rowFull, $rowThreats, $rowFirewall, $rowMb)) {
        $specs.Controls.Add($spec.Panel)
    }
    $left.Controls.Add($specs)

    $secPill = Add-LiveStatus $right $t 'Reading protection...'
    $secPill.ForeColor = $t.Muted
    $secPill.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 12)

    $actions = New-FigmaCard $t
    $actions.Controls.Add((New-CardLabel $t 'Actions' $t.Text $titleFont 8))
    $btnOpenMb = Add-CardButton $actions (New-PremiumButton 'Open Malwarebytes' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(280, 44)) 'Primary')
    $btnOpenDefender = Add-CardButton $actions (New-PremiumButton 'Open Windows Security' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(280, 36)) 'Ghost')
    $btnRefreshSecurity = Add-CardButton $actions (New-PremiumButton 'Refresh' (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(280, 36)) 'Ghost')
    $actions.Controls.Add((New-CardLabel $t 'This page does not scan, update signatures, or change protection settings. Malwarebytes not being installed does not mark the PC unprotected.' $t.Muted $smallFont 0))
    $right.Controls.Add($actions)

    return [ordered]@{
        BtnOpenMalwarebytes = $btnOpenMb
        BtnOpenWindowsSecurity = $btnOpenDefender
        BtnRefreshSecurity = $btnRefreshSecurity
        SecFirewall = $rowFirewall.Value
        SecFullScan = $rowFull.Value
        SecMalwarebytes = $rowMb.Value
        SecPill = $secPill
        SecQuickScan = $rowQuick.Value
        SecRealtime = $rowRealtime.Value
        SecSignatures = $rowSignatures.Value
        SecSummary = $secSummary
        SecThreats = $rowThreats.Value
        SecVerdict = $secVerdict
    }
}
