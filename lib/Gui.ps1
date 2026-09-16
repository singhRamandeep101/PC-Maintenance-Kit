#Requires -Version 5.1
$Script:GuiBusy = $false
$Script:LastJobText = "Ready"
$Script:LastProgressPct = 0
$Script:Theme = $null
$Script:ContentPanels = @{}
$Script:NavButtons = @{}

function Enable-DoubleBuffer($Control) {
    try {
        $prop = $Control.GetType().GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'Instance,NonPublic')
        if ($prop) { $prop.SetValue($Control, $true, $null) }
    } catch { }
}

function Get-GuiTheme {
    return @{
        Bg        = [System.Drawing.Color]::FromArgb(7, 10, 18)
        Header    = [System.Drawing.Color]::FromArgb(11, 17, 30)
        Panel     = [System.Drawing.Color]::FromArgb(13, 20, 36)
        PanelAlt  = [System.Drawing.Color]::FromArgb(19, 29, 50)
        Border    = [System.Drawing.Color]::FromArgb(37, 53, 86)
        Accent    = [System.Drawing.Color]::FromArgb(34, 211, 238)
        Accent2   = [System.Drawing.Color]::FromArgb(167, 139, 250)
        Cta       = [System.Drawing.Color]::FromArgb(139, 92, 246)
        CtaHover  = [System.Drawing.Color]::FromArgb(155, 113, 255)
        Success   = [System.Drawing.Color]::FromArgb(52, 211, 153)
        Warn      = [System.Drawing.Color]::FromArgb(251, 191, 36)
        Danger    = [System.Drawing.Color]::FromArgb(251, 113, 133)
        Text      = [System.Drawing.Color]::FromArgb(230, 237, 248)
        Muted     = [System.Drawing.Color]::FromArgb(140, 163, 199)
        LogBg     = [System.Drawing.Color]::FromArgb(4, 6, 12)
        BtnGhost  = [System.Drawing.Color]::FromArgb(17, 27, 47)
        IconBox   = [System.Drawing.Color]::FromArgb(16, 27, 48)
    }
}

function Get-Mdl2Char([string]$Hex) {
    $clean = ($Hex -replace '^0x', '').Trim()
    return [char][Convert]::ToInt32($clean, 16)
}

if (-not ('PCMK.Native' -as [type])) {
    Add-Type -Namespace PCMK -Name Native -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("dwmapi.dll")]
public static extern int DwmSetWindowAttribute(System.IntPtr hwnd, int attr, ref int val, int size);
'@ -EA SilentlyContinue
}

function Enable-DarkTitleBar {
    param($Form)
    try {
        foreach ($attr in @(20, 19)) {
            $one = 1
            $hr = [PCMK.Native]::DwmSetWindowAttribute($Form.Handle, $attr, [ref]$one, 4)
            if ($hr -eq 0) { break }
        }
    } catch { }
}

function Set-RoundRegion {
    param($Ctrl, [int]$Radius)
    if (-not $Ctrl -or $Radius -le 0) { return }
    try {
        $w = [Math]::Max(2, $Ctrl.Width)
        $h = [Math]::Max(2, $Ctrl.Height)
        $d = [Math]::Min(($Radius * 2), [Math]::Min($w, $h))
        $path = New-Object System.Drawing.Drawing2D.GraphicsPath
        [void]$path.AddArc(0, 0, $d, $d, 180, 90)
        [void]$path.AddArc(($w - $d - 1), 0, $d, $d, 270, 90)
        [void]$path.AddArc(($w - $d - 1), ($h - $d - 1), $d, $d, 0, 90)
        [void]$path.AddArc(0, ($h - $d - 1), $d, $d, 90, 90)
        $path.CloseFigure()
        $old = $Ctrl.Region
        $Ctrl.Region = New-Object System.Windows.Forms.Region $path
        if ($old) { $old.Dispose() }
        $path.Dispose()
    } catch { }
}

function Add-RoundRegionTracking {
    param($Ctrl, [int]$Radius)
    Set-RoundRegion $Ctrl $Radius
    $Ctrl.Add_Resize({ param($s, $e) Set-RoundRegion $s $Radius }.GetNewClosure())
}

function New-GlyphLabel {
    param([string]$Hex, [single]$SizePt, $Color)
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = Get-Mdl2Char $Hex
    $lbl.Font = New-Object System.Drawing.Font("Segoe MDL2 Assets", $SizePt)
    $lbl.ForeColor = $Color
    $lbl.BackColor = [System.Drawing.Color]::Transparent
    $lbl.TextAlign = "MiddleCenter"
    $lbl.Dock = "Fill"
    $lbl.Enabled = $false
    return $lbl
}

function Add-PanelBorder {
    param($Panel, $Color = $null, [int]$Width = 1, [int]$Radius = 12)
    if (-not $Color) { $Color = $Script:Theme.Border }
    $Panel.Tag = @{ Color = $Color; Radius = $Radius }
    Add-RoundRegionTracking $Panel $Radius
    $Panel.Add_Paint({
        param($sender, $e)
        try {
            $meta = $sender.Tag
            if ($meta -is [System.Drawing.Color]) { $meta = @{ Color = $meta; Radius = 0 } }
            $c = if ($meta.Color) { $meta.Color } else { $Script:Theme.Border }
            $g = $e.Graphics
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $w = $sender.Width
            $h = $sender.Height
            $r = if ($meta.Radius) { [int]$meta.Radius } else { 0 }
            if ($r -gt 0) {
                $rect = New-Object System.Drawing.Rectangle(0, 0, ($w - 1), ($h - 1))
                $path = New-Object System.Drawing.Drawing2D.GraphicsPath
                $d = [Math]::Min($r * 2, [Math]::Min($rect.Width, $rect.Height))
                [void]$path.AddArc($rect.X, $rect.Y, $d, $d, 180, 90)
                [void]$path.AddArc((($rect.X + $rect.Width) - $d), $rect.Y, $d, $d, 270, 90)
                [void]$path.AddArc((($rect.X + $rect.Width) - $d), (($rect.Y + $rect.Height) - $d), $d, $d, 0, 90)
                [void]$path.AddArc($rect.X, (($rect.Y + $rect.Height) - $d), $d, $d, 90, 90)
                $path.CloseFigure()
                $pen = New-Object System.Drawing.Pen $c, $Width
                $g.DrawPath($pen, $path)
                $pen.Dispose()
                $path.Dispose()
            } else {
                $pen = New-Object System.Drawing.Pen $c, $Width
                $rect2 = New-Object System.Drawing.Rectangle(0, 0, ($w - 1), ($h - 1))
                $g.DrawRectangle($pen, $rect2)
                $pen.Dispose()
            }
        } catch { }
    })
}

function Update-GuiStatusBar {
    param([string]$JobText = "")
    if ($JobText) { $Script:LastJobText = $JobText }
    $bar = $null
    if ($Script:GuiControls -and $Script:GuiControls.StatusBar) {
        $bar = $Script:GuiControls.StatusBar
    }
    if (-not $bar) { return }
    $free = "-"
    try { $free = "{0} GB" -f (Get-CFreeGB) } catch { }
    $admin = "User"
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p = [Security.Principal.WindowsPrincipal]::new($id)
        if ($p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { $admin = "Admin" }
    } catch { }
    $state = if ($Script:GuiBusy) { "Busy" } else { "Ready" }
    $job = if ($Script:LastJobText) { $Script:LastJobText } else { "Ready" }
    $bar.Text = ("{0}  |  {1}  |  C: free {2}  |  {3}" -f $state, $admin, $free, $job)
}

function New-PremiumButton {
    param(
        [string]$Text,
        [System.Drawing.Point]$Location,
        [System.Drawing.Size]$Size,
        [string]$Style = "Primary"
    )
    $t = $Script:Theme
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text
    $b.Location = $Location
    $b.Size = $Size
    $b.FlatStyle = "Flat"
    $b.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5)
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $b.FlatAppearance.BorderSize = 0
    switch ($Style) {
        'Cta' {
            $b.BackColor = $t.Cta
            $b.ForeColor = [System.Drawing.Color]::White
            $b.FlatAppearance.MouseOverBackColor = $t.CtaHover
            $b.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 11)
        }
        'Primary' {
            $b.BackColor = $t.Accent
            $b.ForeColor = [System.Drawing.Color]::FromArgb(6, 14, 24)
            $b.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(103, 232, 249)
            $b.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
        }
        'Ghost' {
            $b.BackColor = $t.BtnGhost
            $b.ForeColor = $t.Accent
            $b.FlatAppearance.MouseOverBackColor = $t.PanelAlt
        }
        'Danger' {
            $b.BackColor = [System.Drawing.Color]::FromArgb(90, 26, 42)
            $b.ForeColor = $t.Danger
            $b.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(120, 34, 54)
        }
        'Muted' {
            $b.BackColor = $t.PanelAlt
            $b.ForeColor = $t.Muted
            $b.FlatAppearance.MouseOverBackColor = $t.Border
        }
        default {
            $b.BackColor = $t.PanelAlt
            $b.ForeColor = $t.Text
        }
    }
    if ($Style -eq 'Ghost') {
        $accent = $t.Accent
        $b.Add_Paint({
            param($sender, $e)
            try {
                $g = $e.Graphics
                $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
                $w = $sender.Width
                $h = $sender.Height
                $r2 = 9 * 2
                if ($r2 -gt $w) { $r2 = $w }
                if ($r2 -gt $h) { $r2 = $h }
                $path2 = New-Object System.Drawing.Drawing2D.GraphicsPath
                [void]$path2.AddArc(0, 0, $r2, $r2, 180, 90)
                [void]$path2.AddArc(($w - $r2 - 1), 0, $r2, $r2, 270, 90)
                [void]$path2.AddArc(($w - $r2 - 1), ($h - $r2 - 1), $r2, $r2, 0, 90)
                [void]$path2.AddArc(0, ($h - $r2 - 1), $r2, $r2, 90, 90)
                $path2.CloseFigure()
                $pen2 = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(120, $accent.R, $accent.G, $accent.B)), 1
                $g.DrawPath($pen2, $path2)
                $pen2.Dispose()
                $path2.Dispose()
        } catch { }
    })
    }
    Add-RoundRegionTracking $b 9
    return $b
}

function New-PremiumCheck {
    param([string]$Text, [System.Drawing.Point]$Location, [bool]$Checked = $true)
    $t = $Script:Theme
    $c = New-Object System.Windows.Forms.CheckBox
    $c.Text = $Text
    $c.Location = $Location
    $c.AutoSize = $true
    $c.Checked = $Checked
    $c.ForeColor = $t.Text
    $c.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $c.FlatStyle = "Flat"
    return $c
}

function New-CardPanel {
    param(
        [string]$Title = "",
        [System.Windows.Forms.DockStyle]$Dock = [System.Windows.Forms.DockStyle]::None
    )
    $t = $Script:Theme
    $p = New-Object System.Windows.Forms.Panel
    $p.BackColor = $t.Panel
    if ($Dock -ne [System.Windows.Forms.DockStyle]::None) {
        $p.Dock = $Dock
    }
    Add-PanelBorder $p $t.Border -Radius 12
    if ($Title) {
        $tick = New-Object System.Windows.Forms.Panel
        $tick.Location = New-Object System.Drawing.Point(16, 13)
        $tick.Size = New-Object System.Drawing.Size(4, 18)
        $tick.BackColor = $t.Accent
        Enable-DoubleBuffer $tick
        $tick.Add_Paint({
            param($sender, $e)
            try {
                $g = $e.Graphics
                $rectT = New-Object System.Drawing.Rectangle(0, 0, $sender.Width, $sender.Height)
                $brT = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rectT, $Script:Theme.Accent, $Script:Theme.Accent2, 90
                $g.FillRectangle($brT, $rectT)
                $brT.Dispose()
            } catch { }
        })
        $p.Controls.Add($tick)
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = $Title
        $lbl.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 11)
        $lbl.ForeColor = $t.Text
        $lbl.AutoSize = $true
        $lbl.BackColor = [System.Drawing.Color]::Transparent
        $lbl.Location = New-Object System.Drawing.Point(30, 12)
        $p.Controls.Add($lbl)
    }
    return $p
}

function New-MetricCard {
    param(
        [string]$Glyph,
        [string]$Title
    )
    $t = $Script:Theme
    $card = New-Object System.Windows.Forms.Panel
    $card.Height = 86
    $card.Dock = "Top"
    $card.Padding = New-Object System.Windows.Forms.Padding(0, 0, 0, 10)
    $card.BackColor = $t.Bg
    Enable-DoubleBuffer $card

    $inner = New-Object System.Windows.Forms.Panel
    $inner.Dock = "Fill"
    $inner.BackColor = $t.Panel
    Add-PanelBorder $inner $t.Border -Radius 12
    Enable-DoubleBuffer $inner

    # Left neon energy strip (cyan -> violet)
    $inner.Add_Paint({
        param($sender, $e)
        try {
            $g = $e.Graphics
            $rectS = New-Object System.Drawing.Rectangle(1, 10, 3, ($sender.Height - 20))
            if ($rectS.Height -gt 2) {
                $brS = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rectS, $Script:Theme.Accent, $Script:Theme.Accent2, 90
                $g.FillRectangle($brS, $rectS)
                $brS.Dispose()
            }
        } catch { }
    })
    $card.Controls.Add($inner)

    $iconBox = New-Object System.Windows.Forms.Panel
    $iconBox.Location = New-Object System.Drawing.Point(18, 20)
    $iconBox.Size = New-Object System.Drawing.Size(46, 46)
    $iconBox.BackColor = $t.IconBox
    $iconBox.Padding = New-Object System.Windows.Forms.Padding(2)
    Add-PanelBorder $iconBox ([System.Drawing.Color]::FromArgb(70, $t.Accent.R, $t.Accent.G, $t.Accent.B)) -Radius 10
    $iconGlyph = New-GlyphLabel $Glyph 13 $t.Accent
    $iconBox.Controls.Add($iconGlyph)
    $inner.Controls.Add($iconBox)

    $titleLbl = New-Object System.Windows.Forms.Label
    $titleLbl.Text = $Title.ToUpperInvariant()
    $titleLbl.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $titleLbl.ForeColor = $t.Muted
    $titleLbl.AutoSize = $true
    $titleLbl.BackColor = [System.Drawing.Color]::Transparent
    $titleLbl.Location = New-Object System.Drawing.Point(80, 14)
    $inner.Controls.Add($titleLbl)

    $mainLbl = New-Object System.Windows.Forms.Label
    $mainLbl.Text = "-"
    $mainLbl.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 11)
    $mainLbl.ForeColor = $t.Text
    $mainLbl.Location = New-Object System.Drawing.Point(78, 32)
    $mainLbl.Size = New-Object System.Drawing.Size(280, 42)
    $mainLbl.Anchor = "Top,Left,Right"
    $mainLbl.BackColor = [System.Drawing.Color]::Transparent
    $inner.Controls.Add($mainLbl)

    $statLbl = New-Object System.Windows.Forms.Label
    $statLbl.Text = ""
    $statLbl.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5)
    $statLbl.ForeColor = $t.Accent
    $statLbl.TextAlign = "MiddleRight"
    $statLbl.Location = New-Object System.Drawing.Point(360, 26)
    $statLbl.Size = New-Object System.Drawing.Size(170, 30)
    $statLbl.Anchor = "Top,Right"
    $statLbl.BackColor = [System.Drawing.Color]::Transparent
    $inner.Controls.Add($statLbl)

    return [pscustomobject]@{
        Panel = $card
        Main  = $mainLbl
        Stat  = $statLbl
    }
}

function New-GameStatusRow {
    param(
        [string]$Glyph,
        [string]$Title
    )
    $t = $Script:Theme
    $row = New-Object System.Windows.Forms.Panel
    $row.Height = 52
    $row.Dock = "Top"
    $row.BackColor = $t.Panel
    Enable-DoubleBuffer $row

    $iconBox = New-Object System.Windows.Forms.Panel
    $iconBox.Location = New-Object System.Drawing.Point(10, 9)
    $iconBox.Size = New-Object System.Drawing.Size(34, 34)
    $iconBox.BackColor = $t.IconBox
    $iconBox.Padding = New-Object System.Windows.Forms.Padding(2)
    Add-PanelBorder $iconBox ([System.Drawing.Color]::FromArgb(70, $t.Accent2.R, $t.Accent2.G, $t.Accent2.B)) -Radius 9
    $iconGlyph = New-GlyphLabel $Glyph 11 $t.Accent2
    $iconBox.Controls.Add($iconGlyph)
    $row.Controls.Add($iconBox)

    $titleLbl = New-Object System.Windows.Forms.Label
    $titleLbl.Text = $Title
    $titleLbl.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
    $titleLbl.ForeColor = $t.Text
    $titleLbl.AutoSize = $true
    $titleLbl.BackColor = [System.Drawing.Color]::Transparent
    $titleLbl.Location = New-Object System.Drawing.Point(58, 16)
    $row.Controls.Add($titleLbl)

    $valLbl = New-Object System.Windows.Forms.Label
    $valLbl.Text = "-"
    $valLbl.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
    $valLbl.ForeColor = $t.Muted
    $valLbl.TextAlign = "MiddleRight"
    $valLbl.Location = New-Object System.Drawing.Point(300, 14)
    $valLbl.Size = New-Object System.Drawing.Size(230, 24)
    $valLbl.Anchor = "Top,Right"
    $valLbl.BackColor = [System.Drawing.Color]::Transparent
    $row.Add_Resize({
        param($sender, $e)
        $valLbl.Left = [Math]::Max(170, $sender.ClientSize.Width - 242)
    }.GetNewClosure())
    # LED dot rendered from live ForeColor so status color changes update it too
    $valLbl.Add_Paint({
        param($sender, $e)
        try {
            $g = $e.Graphics
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $c = $sender.ForeColor
            $brL = New-Object System.Drawing.SolidBrush $c
            $g.FillEllipse($brL, 2, 8, 8, 8)
            $brL.Dispose()
            $glow = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(60, $c.R, $c.G, $c.B)), 3
            $g.DrawEllipse($glow, 1, 7, 10, 10)
            $glow.Dispose()
        } catch { }
    })
    $row.Controls.Add($valLbl)

    $row.Add_Paint({
        param($sender, $e)
        try {
            $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(140, $Script:Theme.Border.R, $Script:Theme.Border.G, $Script:Theme.Border.B)), 1
            $e.Graphics.DrawLine($pen, 58, ($sender.Height - 1), ($sender.Width - 12), ($sender.Height - 1))
            $pen.Dispose()
        } catch { }
    })

    return [pscustomobject]@{
        Panel = $row
        Value = $valLbl
    }
}

function Set-ActiveNav([string]$Name) {
    $t = $Script:Theme
    foreach ($key in $Script:NavButtons.Keys) {
        $btn = $Script:NavButtons[$key]
        $isActive = ($key -eq $Name)
        $btn.ForeColor = if ($isActive) { $t.Accent } else { $t.Muted }
        $btn.BackColor = if ($isActive) { $t.PanelAlt } else { $t.Header }
        $btn.Tag = if ($isActive) { "active" } else { "idle" }
        $btn.Invalidate()
    }
    foreach ($key in $Script:ContentPanels.Keys) {
        $Script:ContentPanels[$key].Visible = ($key -eq $Name)
    }
}

function Set-GuiBusy([bool]$Busy) {
    $Script:GuiBusy = $Busy
    $runBtns = @(
        'BtnWeekly','BtnCleanup','BtnPreview','BtnUpdates','BtnRepair','BtnGamingOpt','BtnRefreshDevice',
        'BtnFixPower','BtnCopyRamTip','BtnRestartNow','BtnOpenStorage',
        'BtnDiscordOff','BtnRefreshGame','BtnRefreshHome','BtnAmd','BtnNv','BtnRestoreOnly',
        'BtnCheckUpdate','BtnCli','BtnQuit','BtnScanScore','BtnApplyOptFixes','BtnFixMyPc',
        'BtnPresetGamer','BtnPresetQuiet','BtnPresetFull','ChkScheduleWeekly'
    )
    foreach ($n in $runBtns) {
        $b = $Script:GuiControls.$n
        if ($b) { $b.Enabled = -not $Busy }
    }
    foreach ($key in $Script:NavButtons.Keys) {
        $Script:NavButtons[$key].Enabled = -not $Busy
    }
    $stop = $null
    if ($Script:GuiControls -and $Script:GuiControls.BtnStop) {
        $stop = $Script:GuiControls.BtnStop
    }
    if ($stop) {
        $stop.Enabled = $Busy
        $stop.Visible = $true
    }
    if (-not $Busy) {
        $Script:LastJobText = "Ready"
        $Script:DeviceSummaryCache = $null
        $Script:OptimizationScoreCache = $null
    }
    Update-GuiStatusBar
}

function Confirm-OptionalCleanupCaches {
    $needConfirm = $Script:GuiControls.ChkSteam.Checked -or $Script:GuiControls.ChkEpic.Checked -or $Script:GuiControls.ChkRiot.Checked -or $Script:GuiControls.ChkWuCache.Checked
    if (-not $needConfirm) { return $true }
    $parts = [System.Collections.Generic.List[string]]::new()
    if ($Script:GuiControls.ChkSteam.Checked) { [void]$parts.Add("Steam downloading cache only (does not uninstall games)") }
    if ($Script:GuiControls.ChkEpic.Checked) {
        [void]$parts.Add("Epic webcache, logs, Saved\Data, ProgramData EMS, and .egstore staging folders")
    }
    if ($Script:GuiControls.ChkRiot.Checked) { [void]$parts.Add("Riot Client cache/logs") }
    if ($Script:GuiControls.ChkWuCache.Checked) {
        [void]$parts.Add("Windows Update download cache (briefly stops wuauserv/BITS)")
    }
    $detail = ($parts | ForEach-Object { "* $_" }) -join "`n"
    $r = Show-UiMessageBox `
        -Text ("Clear selected optional caches?`n`n{0}`n`nThis does not uninstall games." -f $detail) `
        -Caption "Confirm cleanup" `
        -Buttons ([System.Windows.Forms.MessageBoxButtons]::YesNo) `
        -Icon ([System.Windows.Forms.MessageBoxIcon]::Question)
    return ($r -eq [System.Windows.Forms.DialogResult]::Yes)
}

function Get-GuiCleanupPreview {
    return Get-CleanupPreview `
        -TempOlderThanDays ([int]$Script:GuiControls.DaysNum.Value) `
        -Shaders ([bool]$Script:GuiControls.ChkCleanShader.Checked) `
        -Steam ([bool]$Script:GuiControls.ChkSteam.Checked) `
        -Epic ([bool]$Script:GuiControls.ChkEpic.Checked) `
        -Riot ([bool]$Script:GuiControls.ChkRiot.Checked) `
        -WuCache ([bool]$Script:GuiControls.ChkWuCache.Checked)
}

function Invoke-GuiCleanupSteps {
    $logBox = Get-UiControl Log
    if ($logBox) { $logBox.Clear() }
    Reset-MaintenanceFlags
    $Script:DoWinUpdate = $false
    $Script:DoWinget = $false
    $Script:DoRepair = $false
    $Script:DoAmd = $false
    $Script:DoGamingOptimize = $false
    $Script:DoWuCacheWipe = [bool]$Script:GuiControls.ChkWuCache.Checked
    $Script:Report.Clear()
    $Script:RunStart = Get-Date
    $Script:StartFree = Get-CFreeGB
    $Script:TempOlderThanDays = [int]$Script:GuiControls.DaysNum.Value
    $Script:TotalSteps = 3
    if ($Script:GuiControls.ChkCleanShader.Checked) { $Script:TotalSteps++ }
    if ($Script:GuiControls.ChkSteam.Checked -or $Script:GuiControls.ChkEpic.Checked -or $Script:GuiControls.ChkRiot.Checked) { $Script:TotalSteps++ }
    $Script:CurrentStep = 0
    try {
        Invoke-TempCleanup
        Assert-NotCancelled
        Invoke-BrowserCacheCleanup
        Assert-NotCancelled
        Invoke-RecycleAndCleanMgr
        if ($Script:GuiControls.ChkCleanShader.Checked) { Assert-NotCancelled; Invoke-ShaderCacheCleanup }
        if ($Script:GuiControls.ChkSteam.Checked -or $Script:GuiControls.ChkEpic.Checked -or $Script:GuiControls.ChkRiot.Checked) {
            Assert-NotCancelled
            $doSteam = [bool]$Script:GuiControls.ChkSteam.Checked
            $doEpic  = [bool]$Script:GuiControls.ChkEpic.Checked
            $doRiot  = [bool]$Script:GuiControls.ChkRiot.Checked
            Invoke-LauncherCacheCleanup -Steam:$doSteam -Epic:$doEpic -Riot:$doRiot
        }
        Append-UiLog "Cleanup finished." "Green"
        Show-RunSummaryDialog -Title "Cleanup summary"
    } catch {
        if ($_.Exception.Message -match 'Cancelled') { Write-Warn "Cleanup cancelled" }
        else { throw }
    }
}

function Drain-UiEventQueue {
    if (-not $Script:UiShare -or -not $Script:UiShare.Queue) { return }
    $item = $null
    while ($Script:UiShare.Queue.TryDequeue([ref]$item)) {
        switch ($item.Type) {
            'Log' { 
                $box = Get-UiControl Log
                if (-not $box) { break }
                $color = Get-UiLogColor ([string]$item.Color)
                $stamp = Get-Date -Format "HH:mm:ss"
                $box.SelectionStart = $box.TextLength
                $box.SelectionLength = 0
                $box.SelectionColor = $color
                $box.AppendText("[$stamp] $($item.Msg)`r`n")
                $box.ScrollToCaret()
            }
            'Status' { 
                $lbl = Get-UiControl Status
                if ($lbl) { $lbl.Text = [string]$item.Text }
                Update-GuiStatusBar -JobText ([string]$item.Text)
            }
            'Progress' { 
                # apply locally without re-enqueue
                $pct = [math]::Max(0, [math]::Min(100, [int]$item.Value))
                $Script:LastProgressPct = $pct
                $fill = Get-UiControl ProgressFill
                $track = Get-UiControl ProgressTrack
                if ($fill -and $track) {
                    $w = [math]::Max(0, [int](($track.ClientSize.Width * $pct) / 100.0))
                    if ($fill.Width -ne $w) {
                        $fill.Width = $w
                        $fill.Invalidate()
                    }
                }
            }
        }
    }
}

function Invoke-GuiAction {
    param([scriptblock]$Action, [string]$Title = "Working")
    if ($Script:GuiBusy) { return }
    if (-not $Action -or $Action -isnot [scriptblock]) {
        throw "Invoke-GuiAction requires a scriptblock Action."
    }

    $Script:CancelRequested = $false
    if ($Script:UiShare) { $Script:UiShare['CancelRequested'] = $false }
    Clear-TrackedProcesses
    Set-GuiBusy $true
    Set-UiProgressValue 0
    Set-UiStatusText $Title
    Update-GuiStatusBar -JobText $Title
    # Paint Stop/disabled buttons before long work (DoEvents keeps Cancel responsive later)
    Pump-Ui

    try {
        & $Action
        if (-not (Test-CancelRequested)) {
            # Invalidate caches before UI refresh so score/device panels reflect just-applied fixes
            $Script:DeviceSummaryCache = $null
            $Script:OptimizationScoreCache = $null
            Update-GuiHomeSummary
            Update-GuiDevicePanel
            Update-GuiGamingStatus
            Set-UiStatusText ("Done - {0}" -f (Get-Elapsed))
            Update-GuiStatusBar -JobText ("Done - {0}" -f (Get-Elapsed))
        } else {
            Set-UiStatusText "Cancelled"
            Update-GuiStatusBar -JobText "Cancelled"
        }
        Save-GuiSettings $Script:GuiControls
    } catch {
        if ($_.Exception.Message -match 'Cancelled') {
            Write-Warn "Cancelled by user"
            Set-UiStatusText "Cancelled"
        } else {
            Write-Fail $_.Exception.Message
            Set-UiStatusText "Failed"
            [void](Show-UiMessageBox `
                -Text $_.Exception.Message `
                -Caption "PC Maintenance" `
                -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
                -Icon ([System.Windows.Forms.MessageBoxIcon]::Error))
        }
    } finally {
        Clear-TrackedProcesses
        if ($Script:ExitAfterUpdate) {
            try {
                if ($Script:MainForm -and -not $Script:MainForm.IsDisposed) {
                    $Script:MainForm.Close()
                }
            } catch { }
        } else {
            Set-GuiBusy $false
            Pump-Ui
        }
    }
}

function Update-GuiHomeSummary {
    param([switch]$Refresh)

    try {
        $s = Get-DeviceSummary
        if ($Script:GuiControls.CpuMain) {
            $Script:GuiControls.CpuMain.Text = $s.Cpu
            $Script:GuiControls.CpuStat.Text = "Ready"
        }
        if ($Script:GuiControls.GpuMain) {
            $Script:GuiControls.GpuMain.Text = $s.Gpu
            $Script:GuiControls.GpuStat.Text = "Ready"
        }
        if ($Script:GuiControls.RamMain) {
            $part = if ($s.RamPartNumber) { $s.RamPartNumber } else { "" }
            $line = "{0} GB  |  {1} stick(s)" -f $s.RamGb, $s.RamSticks
            if ($part) { $line = "$line`n$part" }
            $Script:GuiControls.RamMain.Text = $line
            $Script:GuiControls.RamStat.Text = $s.RamChannels
            $t = $Script:Theme
            if ($s.RamChannels -match 'Single') {
                $Script:GuiControls.RamStat.ForeColor = $t.Warn
            } else {
                $Script:GuiControls.RamStat.ForeColor = $t.Accent
            }
        }
    } catch { }

    try {
        if ($Script:GuiControls.Free) {
            $Script:GuiControls.Free.Text = ("C: free {0} GB" -f (Get-CFreeGB))
        }
    } catch { }

    $badge = $Script:GuiControls.RebootBadge
    if ($badge) {
        $t = $Script:Theme
        if (Test-RebootPending) {
            $badge.Text = "Restart pending"
            $badge.ForeColor = $t.Warn
        } else {
            $badge.Text = "No restart pending"
            $badge.ForeColor = $t.Success
        }
    }

    # Keep the Home score card in sync without forcing a CIM refresh every time
    Update-GuiOptimizationScore -Refresh:$Refresh
}

function Apply-GuiWeeklyFlags {
    # Single place for Home / Weekly Full flag wiring (replaces hand-rolled matrices)
    param($Controls)
    Reset-MaintenanceFlags
    $Script:DoCleanup = $true
    $Script:DoRestorePoint = [bool]$Controls.ChkHomeRestore.Checked
    $Script:DoShaderCleanup = [bool]$Controls.ChkHomeShader.Checked
    $Script:DoGamingOptimize = [bool]$Controls.ChkHomeGaming.Checked
    $Script:DoWinUpdate = [bool]$Controls.ChkHomeWU.Checked
    $Script:DoWinget = [bool]$Controls.ChkHomeWinget.Checked
    $Script:DoAmd = $false
    $Script:DoRepair = $false
    $Script:DoWuCacheWipe = $false
    if ($Controls.DaysNum) {
        $Script:TempOlderThanDays = [int]$Controls.DaysNum.Value
    }
}

function Apply-GuiUpdatesFlags {
    param($Controls)
    Reset-MaintenanceFlags
    $Script:DoCleanup = $false
    $Script:DoShaderCleanup = $false
    $Script:DoGamingOptimize = $false
    $Script:DoRepair = $false
    $Script:DoAmd = $false
    $Script:DoWuCacheWipe = $false
    $Script:DoRestorePoint = [bool]$Controls.ChkUpdRestore.Checked
    $Script:DoWinUpdate = [bool]$Controls.ChkUpdWU.Checked
    $Script:DoWinget = [bool]$Controls.ChkUpdWinget.Checked
}

function Apply-GuiRepairFlags {
    param($Controls)
    Reset-MaintenanceFlags
    $Script:DoCleanup = $false
    $Script:DoShaderCleanup = $false
    $Script:DoGamingOptimize = $false
    $Script:DoWinUpdate = $false
    $Script:DoWinget = $false
    $Script:DoAmd = $false
    $Script:DoWuCacheWipe = $false
    $Script:DoRepair = $true
    $Script:DoRestorePoint = [bool]$Controls.ChkRepRestore.Checked
}

function Update-GuiDevicePanel {
    $box = $Script:GuiControls.DeviceSummary
    if (-not $box) { return }
    try {
        $box.Text = Format-DeviceSummaryText
    } catch {
        $box.Text = "Unavailable"
    }
}

function Update-GuiOptimizationScore {
    param([switch]$Refresh)
    if (-not $Script:GuiControls) { return }
    $t = $Script:Theme

    function Set-ScoreUnavailable {
        foreach ($pair in @(
            @{ Score = 'OptScoreVal'; Grade = 'OptGradeVal'; Limiter = 'OptLimiterVal'; Fixes = 'OptFixesVal' },
            @{ Score = 'HomeScoreVal'; Grade = 'HomeGradeVal'; Limiter = 'HomeLimiterVal'; Fixes = 'HomeFixesVal' }
        )) {
            $sc = $Script:GuiControls.($pair.Score)
            $gr = $Script:GuiControls.($pair.Grade)
            $lm = $Script:GuiControls.($pair.Limiter)
            $fx = $Script:GuiControls.($pair.Fixes)
            if ($sc) { $sc.Text = "--"; $sc.ForeColor = $t.Muted }
            if ($gr) { $gr.Text = "Score unavailable"; $gr.ForeColor = $t.Muted }
            if ($lm) { $lm.Text = "" }
            if ($fx) { $fx.Text = "" }
        }
    }

    try {
        $score = Get-GamingOptimizationScore -Refresh:$Refresh
    } catch {
        Set-ScoreUnavailable
        return
    }

    $scoreColor = if ($score.Score -ge 70) { $t.Accent } elseif ($score.Score -ge 50) { $t.Warn } else { $t.Danger }
    $ready = $score.HardwareReadiness.Label
    $limiterText = ("Limiter: {0}  |  Hardware: {1}" -f $score.BiggestLimiter, $ready)
    $fixText = "No major fixes  -  setup looks tuned for gaming."
    if ($score.TopFixes -and $score.TopFixes.Count -gt 0) {
        $fixLines = New-Object System.Collections.Generic.List[string]
        $i = 1
        foreach ($f in $score.TopFixes) {
            $why = if ($f.FixHint) { $f.FixHint } else { $f.Detail }
            [void]$fixLines.Add(("{0}. {1}  -  {2}" -f $i, $f.Title, $why))
            $i++
        }
        $fixText = ($fixLines -join "`r`n")
    }

    foreach ($pair in @(
        @{ Score = 'OptScoreVal'; Grade = 'OptGradeVal'; Limiter = 'OptLimiterVal'; Fixes = 'OptFixesVal' },
        @{ Score = 'HomeScoreVal'; Grade = 'HomeGradeVal'; Limiter = 'HomeLimiterVal'; Fixes = 'HomeFixesVal' }
    )) {
        $sc = $Script:GuiControls.($pair.Score)
        $gr = $Script:GuiControls.($pair.Grade)
        $lm = $Script:GuiControls.($pair.Limiter)
        $fx = $Script:GuiControls.($pair.Fixes)
        if ($sc) {
            $sc.Text = ("{0}" -f $score.Score)
            $sc.ForeColor = $scoreColor
        }
        if ($gr) {
            $gr.Text = ("/100  {0}" -f $score.Grade)
            $gr.ForeColor = $t.Text
        }
        if ($lm) {
            $lm.Text = $limiterText
            $lm.ForeColor = $t.Muted
        }
        if ($fx) {
            $fx.Text = $fixText
            $fx.ForeColor = $t.Muted
        }
    }
}

function Update-GuiGamingStatus {
    $t = $Script:Theme
    $gm = Get-GameModeEnabled
    $dvr = Get-GameDvrEnabled
    $relive = Get-AmdReLiveEnabled
    $power = Get-ActivePowerPlanName
    $discord = Get-DiscordHardwareAcceleration

    function Set-StatusVal($ctrl, $text, $good) {
        if (-not $ctrl) { return }
        $ctrl.Text = $text
        $ctrl.ForeColor = if ($good) { $t.Accent } else { $t.Muted }
    }

    $gmText = if ($null -eq $gm) { "Unknown" } elseif ($gm -eq 1) { "On" } else { "Off" }
    $dvrText = if ($null -eq $dvr) { "Unknown" } elseif ($dvr -eq 0) { "Off" } else { "On" }
    $reliveText = if ($null -eq $relive) { "N/A" } elseif ($relive -eq 0) { "Off" } else { "On" }
    $discordText = if ($null -eq $discord) { "Not found" } elseif ($discord) { "On" } else { "Off" }

    Set-StatusVal $Script:GuiControls.GameModeVal $gmText ($gmText -eq "On")
    Set-StatusVal $Script:GuiControls.GameDvrVal $dvrText ($dvrText -eq "Off")
    Set-StatusVal $Script:GuiControls.ReLiveVal $reliveText ($reliveText -eq "Off" -or $reliveText -eq "N/A")
    Set-StatusVal $Script:GuiControls.PowerVal $power ($power -match 'Ultimate|High')
    Set-StatusVal $Script:GuiControls.DiscordVal $discordText ($discordText -eq "Off")

    Update-GuiOptimizationScore
}

function Enable-GuiDpiAwareness {
    if ($Script:DpiAwarenessEnabled) { return }
    try {
        if (-not ('PCMK.DpiNative' -as [type])) {
            Add-Type -Namespace PCMK -Name DpiNative -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool SetProcessDPIAware();
[System.Runtime.InteropServices.DllImport("user32.dll", SetLastError=true)]
public static extern bool SetProcessDpiAwarenessContext(System.IntPtr dpiContext);
'@ -EA Stop
        }
        # DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 = -4
        $ok = $false
        try { $ok = [PCMK.DpiNative]::SetProcessDpiAwarenessContext([IntPtr](-4)) } catch { $ok = $false }
        if (-not $ok) { [void][PCMK.DpiNative]::SetProcessDPIAware() }
        $Script:DpiAwarenessEnabled = $true
    } catch {
        try {
            if ('PCMK.DpiNative' -as [type]) { [void][PCMK.DpiNative]::SetProcessDPIAware() }
        } catch { }
    }
}

# Page builders (Home/Cleanup/Updates/Gaming/Repair/Device)
$__guiDir = $PSScriptRoot
if (-not $__guiDir) { $__guiDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
. (Join-Path $__guiDir 'GuiPages.ps1')

function Show-MaintenanceGui {
    Enable-GuiDpiAwareness
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    # Keep a mid-session crash inside the app instead of unwinding to the
    # entry-point catch, which reports the misleading "failed to start".
    try {
        [System.Windows.Forms.Application]::SetUnhandledExceptionMode(
            [System.Windows.Forms.UnhandledExceptionMode]::CatchException)
        [System.Windows.Forms.Application]::add_ThreadException({
            param($sender, $e)
            $msg = $e.Exception.Message
            try { Write-Fail $msg } catch { }
            try { Set-UiStatusText "Failed" } catch { }
            try { Set-GuiBusy $false } catch { }
            [void](Show-UiMessageBox `
                -Text ("Something went wrong:`n`n{0}`n`nThe app is still running." -f $msg) `
                -Caption "PC Maintenance" `
                -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
                -Icon ([System.Windows.Forms.MessageBoxIcon]::Error))
        })
    } catch { }


    $Script:Theme = Get-GuiTheme
    $t = $Script:Theme
    $Script:ContentPanels = @{}
    $Script:NavButtons = @{}
    $Script:LastProgressPct = 0

    $form = New-Object System.Windows.Forms.Form
    $Script:MainForm = $form
    $form.Text = "PC Maintenance Kit v$($Script:AppVersion)"
    $form.Size = New-Object System.Drawing.Size(1060, 780)
    $form.StartPosition = "CenterScreen"
    $form.BackColor = $t.Bg
    $form.ForeColor = $t.Text
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $form.MinimumSize = New-Object System.Drawing.Size(980, 720)
    $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $form.AutoScaleDimensions = New-Object System.Drawing.SizeF(96.0, 96.0)
    Enable-DoubleBuffer $form


    # ---- HEADER (Dock Top) ----
    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Top"
    $header.Height = 118
    $header.BackColor = $t.Header
    Enable-DoubleBuffer $header
    $form.Controls.Add($header)

    # Hidden state holders - text/colors rendered by header paint as neon chips
    $freeLbl = New-Object System.Windows.Forms.Label
    $freeLbl.Text = "C: free -"
    $freeLbl.ForeColor = $t.Accent
    $freeLbl.Visible = $false

    $rebootBadge = New-Object System.Windows.Forms.Label
    $rebootBadge.Text = "..."
    $rebootBadge.ForeColor = $t.Muted
    $rebootBadge.Visible = $false

    $header.Tag = @{ Free = $freeLbl; Reboot = $rebootBadge; Theme = $t }

    $Script:NavGlyphs = @{
        Home    = 'E80F'
        Cleanup = 'E74D'
        Updates = 'E895'
        Gaming  = 'E7FC'
        Repair  = 'E90F'
        Device  = 'E7F4'
    }

    $brandTile = New-Object System.Windows.Forms.Panel
    $brandTile.Location = New-Object System.Drawing.Point(24, 14)
    $brandTile.Size = New-Object System.Drawing.Size(46, 46)
    $brandTile.BackColor = $t.IconBox
    Add-PanelBorder $brandTile ([System.Drawing.Color]::FromArgb(90, $t.Accent.R, $t.Accent.G, $t.Accent.B)) -Radius 12
    $brandTile.Add_Paint({
        param($sender, $e)
        try {
            $g = $e.Graphics
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $fontB = New-Object System.Drawing.Font("Segoe MDL2 Assets", 15)
            [System.Windows.Forms.TextRenderer]::DrawText($g, (Get-Mdl2Char 'E90F'), $fontB, (New-Object System.Drawing.Rectangle(0, 0, $sender.Width, $sender.Height)), $Script:Theme.Accent, ([System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::HorizontalCenter))
            $fontB.Dispose()
        } catch { }
    })
    $header.Controls.Add($brandTile)

    $brand = New-Object System.Windows.Forms.Label
    $brand.Text = "PC MAINTENANCE KIT"
    $brand.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 14.5)
    $brand.ForeColor = $t.Text
    $brand.AutoSize = $true
    $brand.BackColor = [System.Drawing.Color]::Transparent
    $brand.Location = New-Object System.Drawing.Point(84, 13)
    $header.Controls.Add($brand)

    $ver = New-Object System.Windows.Forms.Label
    $ver.Text = "v$($Script:AppVersion)   |   GAMER TOOLKIT"
    $ver.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 8.5)
    $ver.ForeColor = $t.Muted
    $ver.AutoSize = $true
    $ver.BackColor = [System.Drawing.Color]::Transparent
    $ver.Location = New-Object System.Drawing.Point(86, 42)
    $header.Controls.Add($ver)

    $header.Add_Paint({
        param($sender, $e)
        try {
            $g = $e.Graphics
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $w = $sender.ClientSize.Width
            $h = $sender.ClientSize.Height
            $t = $sender.Tag.Theme
            $bgRect = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
            $brBg = New-Object System.Drawing.Drawing2D.LinearGradientBrush $bgRect, $t.Header, $t.Bg, [float]90
            $g.FillRectangle($brBg, $bgRect)
            $brBg.Dispose()

            # Neon glow orbs
            $orb1Rect = New-Object System.Drawing.Rectangle(-70, -110, 300, 300)
            $brO1 = New-Object System.Drawing.Drawing2D.LinearGradientBrush $orb1Rect, [System.Drawing.Color]::FromArgb(28, $t.Accent.R, $t.Accent.G, $t.Accent.B), [System.Drawing.Color]::FromArgb(0, $t.Accent.R, $t.Accent.G, $t.Accent.B), [float]45
            $g.FillEllipse($brO1, $orb1Rect)
            $brO1.Dispose()
            $orb2Rect = New-Object System.Drawing.Rectangle(($w - 230), -120, 320, 320)
            $brO2 = New-Object System.Drawing.Drawing2D.LinearGradientBrush $orb2Rect, [System.Drawing.Color]::FromArgb(30, $t.Accent2.R, $t.Accent2.G, $t.Accent2.B), [System.Drawing.Color]::FromArgb(0, $t.Accent2.R, $t.Accent2.G, $t.Accent2.B), [float]315
            $g.FillEllipse($brO2, $orb2Rect)
            $brO2.Dispose()

            # Bottom energy line (cyan -> violet fade)
            $lineRect = New-Object System.Drawing.Rectangle(0, ($h - 2), $w, 2)
            $brL = New-Object System.Drawing.Drawing2D.LinearGradientBrush $lineRect, $t.Accent, $t.Accent2, [float]0
            $g.FillRectangle($brL, $lineRect)
            $brL.Dispose()

            # Status chips (top-right)
            $chipFont = New-Object System.Drawing.Font("Segoe UI Semibold", 8.75)
            $chipFlags = [System.Windows.Forms.TextFormatFlags]::HorizontalCenter -bor [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::EndEllipsis

            foreach ($chip in @(@{ Src = $sender.Tag.Free; Y = 18; W = 148 }, @{ Src = $sender.Tag.Reboot; Y = 50; W = 172 })) {
                $src = $chip.Src
                if (-not $src -or -not $src.Text) { continue }
                $cw = $chip.W
                $cx = $w - 24 - $cw
                $cy = $chip.Y
                $rectC = New-Object System.Drawing.Rectangle($cx, $cy, $cw, 26)
                $pathC = New-Object System.Drawing.Drawing2D.GraphicsPath
                $dC = 24
                [void]$pathC.AddArc($rectC.X, $rectC.Y, $dC, $dC, 180, 90)
                [void]$pathC.AddArc((($rectC.X + $rectC.Width) - $dC), $rectC.Y, $dC, $dC, 270, 90)
                [void]$pathC.AddArc((($rectC.X + $rectC.Width) - $dC), (($rectC.Y + $rectC.Height) - $dC), $dC, $dC, 0, 90)
                [void]$pathC.AddArc($rectC.X, (($rectC.Y + $rectC.Height) - $dC), $dC, $dC, 90, 90)
                $pathC.CloseFigure()
                $cc = $src.ForeColor
                $fillC = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(22, $cc.R, $cc.G, $cc.B))
                $g.FillPath($fillC, $pathC)
                $fillC.Dispose()
                $penC = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(80, $cc.R, $cc.G, $cc.B)), 1
                $g.DrawPath($penC, $pathC)
                $penC.Dispose()
                $pathC.Dispose()
                $tbC = New-Object System.Drawing.Rectangle(($rectC.X + 6), $rectC.Y, ($rectC.Width - 12), $rectC.Height)
                [System.Windows.Forms.TextRenderer]::DrawText($g, $src.Text, $chipFont, $tbC, $cc, $chipFlags)
            }
            $chipFont.Dispose()
        } catch { }
    })

    $navNames = @('Home','Cleanup','Updates','Gaming','Repair','Device')
    $navX = 24
    foreach ($name in $navNames) {
        $nb = New-Object System.Windows.Forms.Button
        $nb.Text = $name
        $nb.Location = New-Object System.Drawing.Point($navX, 66)
        $nb.Size = New-Object System.Drawing.Size(108, 38)
        $nb.FlatStyle = "Flat"
        $nb.FlatAppearance.BorderSize = 0
        $nb.BackColor = $t.Header
        $nb.ForeColor = $t.Muted
        $nb.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5)
        $nb.Cursor = [System.Windows.Forms.Cursors]::Hand
        $nb.Tag = "idle"
        $nb.TextAlign = "MiddleLeft"
        $nb.Padding = New-Object System.Windows.Forms.Padding(34, 0, 0, 0)
        $nb.Add_Click({
            param($sender, $e)
            Set-ActiveNav ([string]$sender.Text)
        })
        $nb.Add_MouseEnter({
            param($sender, $e)
            if ($sender.Tag -ne "active") { $sender.BackColor = $Script:Theme.PanelAlt; $sender.Invalidate() }
        })
        $nb.Add_MouseLeave({
            param($sender, $e)
            if ($sender.Tag -ne "active") { $sender.BackColor = $Script:Theme.Header; $sender.Invalidate() }
        })
        $nb.Add_Paint({
            param($sender, $e)
            try {
                $g = $e.Graphics
                $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
                $glyphCode = $Script:NavGlyphs[[string]$sender.Text]
                if ($glyphCode) {
                    $fontG = New-Object System.Drawing.Font("Segoe MDL2 Assets", 10.5)
                    [System.Windows.Forms.TextRenderer]::DrawText($g, (Get-Mdl2Char $glyphCode), $fontG, (New-Object System.Drawing.Rectangle(11, 0, 22, $sender.Height)), $sender.ForeColor, ([System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::HorizontalCenter))
                    $fontG.Dispose()
                }
                if ($sender.Tag -eq "active") {
                    $rectU = New-Object System.Drawing.Rectangle(12, ($sender.Height - 6), ($sender.Width - 24), 3)
                    $brU = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rectU, $Script:Theme.Accent, $Script:Theme.Accent2, 0
                    $g.FillRectangle($brU, $rectU)
                    $brU.Dispose()
                }
            } catch { }
        })
        Add-RoundRegionTracking $nb 8
        $header.Controls.Add($nb)
        $Script:NavButtons[$name] = $nb
        $navX += 112
    }


    # ---- FOOTER HOST (Dock Bottom) ----
    $footerHost = New-Object System.Windows.Forms.Panel
    $footerHost.Dock = "Bottom"
    $footerHost.Height = 200
    $footerHost.BackColor = $t.Bg
    $footerHost.Padding = New-Object System.Windows.Forms.Padding(24, 8, 24, 16)
    $form.Controls.Add($footerHost)

    $logCard = New-Object System.Windows.Forms.Panel
    $logCard.Dock = "Fill"
    $logCard.BackColor = $t.Panel
    Add-PanelBorder $logCard ([System.Drawing.Color]::FromArgb(150, $t.Border.R, $t.Border.G, $t.Border.B)) -Radius 14
    $logCard.Padding = New-Object System.Windows.Forms.Padding(1)
    $footerHost.Controls.Add($logCard)

    $logTop = New-Object System.Windows.Forms.Panel
    $logTop.Dock = "Top"
    $logTop.Height = 34
    $logTop.BackColor = $t.Panel
    $logCard.Controls.Add($logTop)

    $logTitle = New-Object System.Windows.Forms.Label
    $logTitle.Text = "Activity"
    $logTitle.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
    $logTitle.ForeColor = $t.Accent
    $logTitle.AutoSize = $true
    $logTitle.Location = New-Object System.Drawing.Point(16, 10)
    $logTop.Controls.Add($logTitle)

    $btnClearLog = New-Object System.Windows.Forms.LinkLabel
    $btnClearLog.Text = "Clear"
    $btnClearLog.LinkColor = $t.Accent
    $btnClearLog.ActiveLinkColor = $t.Text
    $btnClearLog.AutoSize = $true
    $btnClearLog.Anchor = "Top,Right"
    $btnClearLog.Location = New-Object System.Drawing.Point(($logTop.Width - 90), 12)
    $logTop.Controls.Add($btnClearLog)
    $logTop.Add_Resize({
        param($sender, $e)
        $btnClearLog.Left = $sender.ClientSize.Width - 90
    })

    $logBottom = New-Object System.Windows.Forms.Panel
    $logBottom.Dock = "Bottom"
    $logBottom.Height = 56
    $logBottom.BackColor = $t.Panel
    $logCard.Controls.Add($logBottom)

    $btnCluster = New-Object System.Windows.Forms.Panel
    $btnCluster.Dock = "Right"
    $btnCluster.Width = 168
    $btnCluster.BackColor = $t.Panel
    $logBottom.Controls.Add($btnCluster)

    $btnStop = New-PremiumButton "Stop" (New-Object System.Drawing.Point(8, 12)) (New-Object System.Drawing.Size(52, 32)) "Danger"
    $btnStop.Enabled = $false
    $btnCli = New-PremiumButton "CLI" (New-Object System.Drawing.Point(64, 12)) (New-Object System.Drawing.Size(44, 32)) "Muted"
    $btnQuit = New-PremiumButton "Quit" (New-Object System.Drawing.Point(112, 12)) (New-Object System.Drawing.Size(46, 32)) "Danger"
    $btnCluster.Controls.AddRange(@($btnStop, $btnCli, $btnQuit))

    $progArea = New-Object System.Windows.Forms.Panel
    $progArea.Dock = "Fill"
    $progArea.BackColor = $t.Panel
    $progArea.Padding = New-Object System.Windows.Forms.Padding(16, 10, 12, 8)
    $logBottom.Controls.Add($progArea)

    $progressTrack = New-Object System.Windows.Forms.Panel
    $progressTrack.Dock = "Top"
    $progressTrack.Height = 12
    $progressTrack.BackColor = $t.IconBox
    Add-RoundRegionTracking $progressTrack 6
    $progArea.Controls.Add($progressTrack)

    $progressFill = New-Object System.Windows.Forms.Panel
    $progressFill.Location = New-Object System.Drawing.Point(0, 0)
    $progressFill.Size = New-Object System.Drawing.Size(0, 12)
    $progressFill.BackColor = $t.Accent
    # ResizeRedraw: grow/shrink must repaint the whole fill (not only the new strip)
    try {
        $setStyle = [System.Windows.Forms.Control].GetMethod('SetStyle', [System.Reflection.BindingFlags]'Instance,NonPublic')
        $paintFlags = [System.Windows.Forms.ControlStyles]::AllPaintingInWmPaint -bor
            [System.Windows.Forms.ControlStyles]::UserPaint -bor
            [System.Windows.Forms.ControlStyles]::OptimizedDoubleBuffer -bor
            [System.Windows.Forms.ControlStyles]::ResizeRedraw
        [void]$setStyle.Invoke($progressFill, @($paintFlags, $true))
    } catch { }
    Add-RoundRegionTracking $progressFill 6
    # Cyan -> violet energy gradient across the current fill width
    $progressFill.Add_Paint({
        param($sender, $e)
        try {
            if ($sender.Width -le 1) { return }
            $g = $e.Graphics
            $rectP = New-Object System.Drawing.Rectangle(0, 0, $sender.Width, $sender.Height)
            $brP = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rectP, $Script:Theme.Accent, $Script:Theme.Accent2, [float]0
            $brP.WrapMode = [System.Drawing.Drawing2D.WrapMode]::Clamp
            $g.FillRectangle($brP, $rectP)
            $brP.Dispose()
        } catch { }
    })
    $progressTrack.Controls.Add($progressFill)

    $statusRow = New-Object System.Windows.Forms.Panel
    $statusRow.Dock = "Fill"
    $statusRow.BackColor = $t.Panel
    $progArea.Controls.Add($statusRow)

    # Add progressTrack first then status - Dock order: add Fill first then Top so Top wins? 
    # Actually in WinForms, last docked control gets priority for remaining space differently.
    # Correct order: add Fill (statusRow) first, then Top (track) - track takes top, status fills rest.
    $progArea.Controls.Clear()
    $progArea.Controls.Add($statusRow)
    $progArea.Controls.Add($progressTrack)

    $progLbl = New-Object System.Windows.Forms.Label
    $progLbl.Text = "Overall Progress"
    $progLbl.ForeColor = $t.Muted
    $progLbl.AutoSize = $true
    $progLbl.Location = New-Object System.Drawing.Point(0, 4)
    $statusRow.Controls.Add($progLbl)

    $status = New-Object System.Windows.Forms.Label
    $status.Text = "Ready"
    $status.ForeColor = $t.Muted
    $status.Location = New-Object System.Drawing.Point(130, 4)
    $status.Size = New-Object System.Drawing.Size(280, 18)
    # Left-anchored only: Top,Left,Right grew it straight over the right-pinned status bar
    $status.Anchor = "Top,Left"
    $statusRow.Controls.Add($status)

    $statusBar = New-Object System.Windows.Forms.Label
    $statusBar.Text = "Ready"
    $statusBar.ForeColor = $t.Muted
    $statusBar.Location = New-Object System.Drawing.Point(420, 4)
    $statusBar.Size = New-Object System.Drawing.Size(200, 18)
    $statusBar.Anchor = "Top,Right"
    $statusRow.Controls.Add($statusBar)

    $log = New-Object System.Windows.Forms.RichTextBox
    $log.Dock = "Fill"
    $log.BackColor = $t.LogBg
    $log.ForeColor = $t.Accent
    $log.Font = New-Object System.Drawing.Font("Consolas", 9)
    $log.ReadOnly = $true
    $log.BorderStyle = "None"
    $log.Margin = New-Object System.Windows.Forms.Padding(16)
    # Padding via wrapper
    $logWrap = New-Object System.Windows.Forms.Panel
    $logWrap.Dock = "Fill"
    $logWrap.BackColor = $t.LogBg
    $logWrap.Padding = New-Object System.Windows.Forms.Padding(16, 4, 16, 4)
    $logCard.Controls.Add($logWrap)
    $log.Dock = "Fill"
    $logWrap.Controls.Add($log)

    # Dock order for logCard: add Fill (logWrap) first, then Bottom, then Top
    $logCard.Controls.Clear()
    $logCard.Controls.Add($logWrap)
    $logCard.Controls.Add($logBottom)
    $logCard.Controls.Add($logTop)
    $logWrap.Controls.Add($log)

    $progressTrack.Add_Resize({
        Set-UiProgressValue $Script:LastProgressPct
    })


    # ---- CONTENT HOST (Dock Fill) ----
    $hostPanel = New-Object System.Windows.Forms.Panel
    $hostPanel.Dock = "Fill"
    $hostPanel.BackColor = $t.Bg
    $hostPanel.Padding = New-Object System.Windows.Forms.Padding(24, 12, 24, 8)
    $form.Controls.Add($hostPanel)

    # Dock order: add Fill first, then Bottom, then Top
    $form.Controls.Clear()
    $form.Controls.Add($hostPanel)
    $form.Controls.Add($footerHost)
    $form.Controls.Add($header)

    function New-Content([string]$Name) {
        $p = New-Object System.Windows.Forms.Panel
        $p.Dock = "Fill"
        $p.BackColor = $t.Bg
        $p.Visible = $false
        $hostPanel.Controls.Add($p)
        $Script:ContentPanels[$Name] = $p
        return $p
    }

    $pageHome = New-Content "Home"
    $pageClean = New-Content "Cleanup"
    $pageUpd = New-Content "Updates"
    $pageGame = New-Content "Gaming"
    $pageRepair = New-Content "Repair"
    $pageDev = New-Content "Device"

    $homeParts = Add-GuiHomePage -Page $pageHome -Theme $t
    $cleanParts = Add-GuiCleanupPage -Page $pageClean -Theme $t
    $updParts = Add-GuiUpdatesPage -Page $pageUpd -Theme $t
    $gameParts = Add-GuiGamingPage -Page $pageGame -Theme $t
    $repairParts = Add-GuiRepairPage -Page $pageRepair -Theme $t
    $devParts = Add-GuiDevicePage -Page $pageDev -Theme $t

    function Merge-GuiParts($Target, $Parts) {
        foreach ($k in @($Parts.Keys)) { $Target[$k] = $Parts[$k] }
    }
    $merged = @{}
    Merge-GuiParts $merged $homeParts
    Merge-GuiParts $merged $cleanParts
    Merge-GuiParts $merged $updParts
    Merge-GuiParts $merged $gameParts
    Merge-GuiParts $merged $repairParts
    Merge-GuiParts $merged $devParts

    $Script:GuiControls = [pscustomobject]@{
}
    $Script:GuiControls = [pscustomobject]@{
        Form            = $form
        Free            = $freeLbl
        RebootBadge     = $rebootBadge
        StatusBar       = $statusBar
        CpuMain         = $merged.CpuMain
        CpuStat         = $merged.CpuStat
        GpuMain         = $merged.GpuMain
        GpuStat         = $merged.GpuStat
        RamMain         = $merged.RamMain
        RamStat         = $merged.RamStat
        DeviceSummary   = $merged.DeviceSummary
        OptScoreVal     = $merged.OptScoreVal
        OptGradeVal     = $merged.OptGradeVal
        OptLimiterVal   = $merged.OptLimiterVal
        OptFixesVal     = $merged.OptFixesVal
        HomeScoreVal    = $merged.HomeScoreVal
        HomeGradeVal    = $merged.HomeGradeVal
        HomeLimiterVal  = $merged.HomeLimiterVal
        HomeFixesVal    = $merged.HomeFixesVal
        GameModeVal     = $merged.GameModeVal
        GameDvrVal      = $merged.GameDvrVal
        ReLiveVal       = $merged.ReLiveVal
        PowerVal        = $merged.PowerVal
        DiscordVal      = $merged.DiscordVal
        ChkHomeRestore  = $merged.ChkHomeRestore
        ChkHomeShader   = $merged.ChkHomeShader
        ChkHomeGaming   = $merged.ChkHomeGaming
        ChkHomeWU       = $merged.ChkHomeWU
        ChkHomeWinget   = $merged.ChkHomeWinget
        DaysNum         = $merged.DaysNum
        ChkCleanShader  = $merged.ChkCleanShader
        ChkSteam        = $merged.ChkSteam
        ChkEpic         = $merged.ChkEpic
        ChkRiot         = $merged.ChkRiot
        ChkWuCache      = $merged.ChkWuCache
        ChkUpdRestore   = $merged.ChkUpdRestore
        ChkUpdWU        = $merged.ChkUpdWU
        ChkUpdWinget    = $merged.ChkUpdWinget
        ChkRepRestore   = $merged.ChkRepRestore
        BtnFixMyPc      = $merged.BtnFixMyPc
        BtnWeekly       = $merged.BtnWeekly
        BtnCleanup      = $merged.BtnCleanup
        BtnPreview      = $merged.BtnPreview
        BtnUpdates      = $merged.BtnUpdates
        BtnRepair       = $merged.BtnRepair
        BtnGamingOpt    = $merged.BtnGamingOpt
        BtnRefreshDevice = $merged.BtnRefreshDevice
        BtnFixPower     = $merged.BtnFixPower
        BtnCopyRamTip   = $merged.BtnCopyRamTip
        BtnRestartNow   = $merged.BtnRestartNow
        BtnOpenStorage  = $merged.BtnOpenStorage
        BtnDiscordOff   = $merged.BtnDiscordOff
        BtnRefreshGame  = $merged.BtnRefreshGame
        BtnScanScore    = $merged.BtnScanScore
        BtnApplyOptFixes = $merged.BtnApplyOptFixes
        BtnRefreshHome  = $merged.BtnRefreshHome
        BtnAmd          = $merged.BtnAmd
        BtnNv           = $merged.BtnNv
        BtnRestoreOnly  = $merged.BtnRestoreOnly
        BtnStop         = $btnStop
        BtnCheckUpdate  = $merged.BtnCheckUpdate
        BtnCli          = $btnCli
        BtnQuit         = $btnQuit
        BtnPresetGamer  = $merged.BtnPresetGamer
        BtnPresetQuiet  = $merged.BtnPresetQuiet
        BtnPresetFull   = $merged.BtnPresetFull
        ChkScheduleWeekly = $merged.ChkScheduleWeekly
        LblScheduleStatus = $merged.LblScheduleStatus
    }


    $Script:Ui = [pscustomobject]@{
        Form          = $form
        ProgressFill  = $progressFill
        ProgressTrack = $progressTrack
        Status        = $status
        Log           = $log
    }

    $Script:UiShare = [hashtable]::Synchronized(@{
        CancelRequested = $false
        Queue           = [System.Collections.Concurrent.ConcurrentQueue[hashtable]]::new()
    })

    $saved = Load-GuiSettings
    $Script:LoadedGuiSettings = $saved

    Apply-GuiSettings -Controls $Script:GuiControls -Settings $saved
    if ($saved.CarePreset -and $saved.CarePreset -match '^(Gamer|Quiet|Full)$') {
        # Reflect last chosen preset name only; checkbox values already restored above
    }
    Update-GuiCareScheduleStatus

    Set-ActiveNav "Home"
    Update-GuiHomeSummary
    Update-GuiDevicePanel
    Update-GuiGamingStatus
    Update-GuiStatusBar -JobText "Ready"
    Append-UiLog ("PC Maintenance Kit v{0} ready" -f $Script:AppVersion) "Cyan"

    $uiTimer = New-Object System.Windows.Forms.Timer
    $uiTimer.Interval = 100
    $uiTimer.Add_Tick({
        Drain-UiEventQueue
        if ($Script:GuiBusy) { Pump-Ui }
    })
    $uiTimer.Start()
    $form.Add_Shown({ Enable-DarkTitleBar $form })
    $form.Add_FormClosing({
        param($sender, $e)
        if ($Script:ExitAfterUpdate) { return }
        if ($Script:GuiBusy) {
            $e.Cancel = $true
            Request-MaintenanceCancel
            Append-UiLog "Close blocked while busy - Stop requested..." "Yellow"
            Update-GuiStatusBar -JobText "Cancelling..."
        }
    })
    $form.Add_FormClosed({
        try { $uiTimer.Stop(); $uiTimer.Dispose() } catch { }
        try { Save-GuiSettings $Script:GuiControls } catch { }
    })

    if ($saved.CheckUpdatesOnStart) {
        $form.Add_Shown({
            try {
                Invoke-GuiAction -Title "Checking for updates" -Action {
                    $check = Test-AppUpdateAvailable -Silent
                    if ($check -and $check.Status -eq 'UpdateAvailable') {
                        Show-UpdateAvailableDialog $check.Release
                    }
                }
            } catch { }
        })
    }

    $btnClearLog.Add_Click({
        $box = Get-UiControl Log
        if ($box) { $box.Clear() }
    })

    $btnStop.Add_Click({
        Request-MaintenanceCancel
        Append-UiLog "Stop requested..." "Yellow"
        Update-GuiStatusBar -JobText "Cancelling..."
    })

    # Page controls live in GuiControls (builders returned); alias locals for handler wiring
    $c = $Script:GuiControls
    $btnWeekly = $c.BtnWeekly
    $btnFixMyPc = $c.BtnFixMyPc
    $btnRefreshHome = $c.BtnRefreshHome
    $btnPresetGamer = $c.BtnPresetGamer
    $btnPresetQuiet = $c.BtnPresetQuiet
    $btnPresetFull = $c.BtnPresetFull
    $btnPreview = $c.BtnPreview
    $btnCleanup = $c.BtnCleanup
    $btnUpdates = $c.BtnUpdates
    $btnAmd = $c.BtnAmd
    $btnNv = $c.BtnNv
    $btnGamingOpt = $c.BtnGamingOpt
    $btnApplyOptFixes = $c.BtnApplyOptFixes
    $btnScanScore = $c.BtnScanScore
    $btnFixPower = $c.BtnFixPower
    $btnDiscordOff = $c.BtnDiscordOff
    $btnRefreshGame = $c.BtnRefreshGame
    $btnRepair = $c.BtnRepair
    $btnRestoreOnly = $c.BtnRestoreOnly
    $btnRefreshDevice = $c.BtnRefreshDevice
    $btnCheckUpdate = $c.BtnCheckUpdate
    $btnCopyRamTip = $c.BtnCopyRamTip
    $btnOpenStorage = $c.BtnOpenStorage
    $btnRestartNow = $c.BtnRestartNow

    $btnWeekly.Add_Click({
        if ($Script:GuiBusy) { return }
        Save-GuiSettings $Script:GuiControls
        $bits = [System.Collections.Generic.List[string]]::new()
        [void]$bits.Add("Clean temp, browser caches (all profiles), and empty Recycle Bin")
        if ($Script:GuiControls.ChkHomeShader.Checked) { [void]$bits.Add("Clear GPU shader caches") }
        if ($Script:GuiControls.ChkHomeGaming.Checked) { [void]$bits.Add("Apply gaming optimizations") }
        if ($Script:GuiControls.ChkHomeRestore.Checked) { [void]$bits.Add("Create a restore point") }
        if ($Script:GuiControls.ChkHomeWU.Checked) { [void]$bits.Add("Install Windows Updates") }
        if ($Script:GuiControls.ChkHomeWinget.Checked) { [void]$bits.Add("Upgrade winget packages") }
        $summary = ($bits | ForEach-Object { "* $_" }) -join "`n"
        $r = Show-UiMessageBox `
            -Text ("Run Weekly Full?`n`n{0}`n`nWindows Update download-cache wipe stays off unless you enable it on the Cleanup tab." -f $summary) `
            -Caption "Confirm Weekly Full" `
            -Buttons ([System.Windows.Forms.MessageBoxButtons]::YesNo) `
            -Icon ([System.Windows.Forms.MessageBoxIcon]::Question)
        if ($r -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        Invoke-GuiAction -Title "Weekly Full" -Action {
            $logBox = Get-UiControl Log
            if ($logBox) { $logBox.Clear() }
            Append-UiLog "Weekly Full starting..." "Cyan"
            Apply-GuiWeeklyFlags -Controls $Script:GuiControls
            [void](Invoke-MaintenanceRun)
        }
    })

    $btnFixMyPc.Add_Click({
        if ($Script:GuiBusy) { return }
        $r = Show-UiMessageBox `
            -Text "Apply recommended gaming fixes now?`n`nSafe auto-tweaks (Game Mode, DVR, power plan) run first. Manual tips (Storage, RAM, display) open when needed.`n`nYou'll see the score before and after." `
            -Caption "Fix my PC for gaming" `
            -Buttons ([System.Windows.Forms.MessageBoxButtons]::YesNo) `
            -Icon ([System.Windows.Forms.MessageBoxIcon]::Question)
        if ($r -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        Invoke-GuiAction -Title "Fix my PC for gaming" -Action {
            $logBox = Get-UiControl Log
            if ($logBox) { $logBox.Clear() }
            $Script:Report.Clear()
            $Script:RunStart = Get-Date
            $Script:TotalSteps = 2
            $Script:CurrentStep = 0
            $before = Get-GamingOptimizationScore -Refresh
            Append-UiLog ("Score before: {0}/100 ({1})" -f $before.Score, $before.Grade) "Cyan"
            $after = Invoke-RecommendedOptimizationFixes -OpenTips
            Update-GuiGamingStatus
            Update-GuiDevicePanel
            Update-GuiOptimizationScore -Refresh
            Append-UiLog ("Score after: {0}/100 ({1})  -  was {2}" -f $after.Score, $after.Grade, $before.Score) "Green"
            Show-RunSummaryDialog -Title "Fix my PC summary"
        }
    })

    $btnRefreshHome.Add_Click({
        if ($Script:GuiBusy) { return }
        Update-GuiHomeSummary -Refresh
        Update-GuiGamingStatus
        Update-GuiCareScheduleStatus
        Update-GuiStatusBar -JobText "Home refreshed"
    })

    $btnPresetGamer.Add_Click({
        if ($Script:GuiBusy) { return }
        Apply-CarePreset -Name Gamer -Controls $Script:GuiControls
        Save-GuiSettings $Script:GuiControls
        Update-GuiStatusBar -JobText "Preset: Gamer"
        Append-UiLog "Applied Gamer preset (WU/winget off)" "Cyan"
    })
    $btnPresetQuiet.Add_Click({
        if ($Script:GuiBusy) { return }
        Apply-CarePreset -Name Quiet -Controls $Script:GuiControls
        Save-GuiSettings $Script:GuiControls
        Update-GuiStatusBar -JobText "Preset: Quiet"
        Append-UiLog "Applied Quiet preset (cleanup-focused)" "Cyan"
    })
    $btnPresetFull.Add_Click({
        if ($Script:GuiBusy) { return }
        Apply-CarePreset -Name Full -Controls $Script:GuiControls
        Save-GuiSettings $Script:GuiControls
        Update-GuiStatusBar -JobText "Preset: Full"
        Append-UiLog "Applied Full preset (includes Windows Update + winget)" "Yellow"
    })

    $chkScheduleWeekly = $Script:GuiControls.ChkScheduleWeekly
    if ($chkScheduleWeekly) {
        $chkScheduleWeekly.Add_Click({
            if ($Script:GuiBusy) { return }
            $on = [bool]$Script:GuiControls.ChkScheduleWeekly.Checked
            try {
                if ($on) {
                    $r = Show-UiMessageBox `
                        -Text "Schedule Weekly Full every Sunday at 6 PM?`n`nUses your current Home checkboxes (save them first).`nRuns elevated while you are signed in.`n`nYou can turn this off anytime." `
                        -Caption "Schedule Weekly Full" `
                        -Buttons ([System.Windows.Forms.MessageBoxButtons]::YesNo) `
                        -Icon ([System.Windows.Forms.MessageBoxIcon]::Question)
                    if ($r -ne [System.Windows.Forms.DialogResult]::Yes) {
                        $Script:GuiControls.ChkScheduleWeekly.Checked = $false
                        return
                    }
                    Save-GuiSettings $Script:GuiControls
                    $entry = Join-Path $Script:AppRoot 'PC-Maintenance.ps1'
                    [void](Enable-WeeklyCareSchedule -ScriptPath $entry)
                    Append-UiLog "Weekly Full scheduled for Sundays at 6 PM" "Green"
                } else {
                    [void](Disable-WeeklyCareSchedule)
                    Append-UiLog "Weekly Full schedule removed" "Yellow"
                }
            } catch {
                $Script:GuiControls.ChkScheduleWeekly.Checked = (-not $on)
                [void](Show-UiMessageBox `
                    -Text $_.Exception.Message `
                    -Caption "Schedule" `
                    -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
                    -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning))
            }
            Update-GuiCareScheduleStatus
            Save-GuiSettings $Script:GuiControls
        })
    }

    $btnPreview.Add_Click({
        if ($Script:GuiBusy) { return }
        Save-GuiSettings $Script:GuiControls
        Invoke-GuiAction -Title "Preview cleanup" -Action {
            Append-UiLog "Measuring cleanup sizes..." "Cyan"
            $preview = Get-GuiCleanupPreview
            Append-UiLog ("Preview total ~ {0} across {1} path(s)" -f $preview.TotalText, @($preview.Rows).Count) "Cyan"
            $prevResult = Show-CleanupPreviewDialog -Preview $preview
            if ($prevResult -eq [System.Windows.Forms.DialogResult]::Yes) {
                # Confirm optional caches only when the user chooses to run cleanup
                if (-not (Confirm-OptionalCleanupCaches)) {
                    Append-UiLog "Cleanup cancelled at confirmation." "Yellow"
                    return
                }
                Append-UiLog "Running cleanup from preview..." "Cyan"
                Invoke-GuiCleanupSteps
            } else {
                Append-UiLog "Preview closed without running cleanup." "Gray"
            }
        }
    })

    $btnCleanup.Add_Click({
        Save-GuiSettings $Script:GuiControls
        if (-not (Confirm-OptionalCleanupCaches)) { return }

        Invoke-GuiAction -Title "Cleanup" -Action {
            Append-UiLog "Building cleanup preview..." "Gray"
            $preview = Get-GuiCleanupPreview
            $prevResult = Show-CleanupPreviewDialog -Preview $preview
            if ($prevResult -ne [System.Windows.Forms.DialogResult]::Yes) {
                Append-UiLog "Cleanup cancelled at preview." "Yellow"
                return
            }
            Invoke-GuiCleanupSteps
        }
    })

    $btnUpdates.Add_Click({
        Save-GuiSettings $Script:GuiControls
        Invoke-GuiAction -Title "Updates" -Action {
            $logBox = Get-UiControl Log
            if ($logBox) { $logBox.Clear() }
            Apply-GuiUpdatesFlags -Controls $Script:GuiControls
            if (-not $Script:DoWinUpdate -and -not $Script:DoWinget) {
                Write-Warn "Nothing selected"
                return
            }
            [void](Invoke-MaintenanceRun)
        }
    })

    $btnAmd.Add_Click({
        Invoke-GuiAction -Title "AMD" -Action {
            $Script:Report.Clear()
            $Script:TotalSteps = 1
            $Script:CurrentStep = 0
            Invoke-AmdOpen
        }
    })

    $btnNv.Add_Click({
        Invoke-GuiAction -Title "NVIDIA" -Action {
            $Script:Report.Clear()
            $Script:TotalSteps = 1
            $Script:CurrentStep = 0
            Write-Step "NVIDIA"
            [void](Invoke-NvidiaAppOpen)
        }
    })

    $btnGamingOpt.Add_Click({
        Invoke-GuiAction -Title "Gaming optimize" -Action {
            $logBox = Get-UiControl Log
            if ($logBox) { $logBox.Clear() }
            $Script:Report.Clear()
            $Script:RunStart = Get-Date
            $Script:TotalSteps = 2
            $Script:CurrentStep = 0
            Invoke-GamingOptimize
            Invoke-GamingChecks
            Update-GuiGamingStatus
            Update-GuiDevicePanel
            Show-RunSummaryDialog -Title "Gaming optimize summary"
        }
    })

    $btnApplyOptFixes.Add_Click({
        Invoke-GuiAction -Title "Recommended fixes" -Action {
            $logBox = Get-UiControl Log
            if ($logBox) { $logBox.Clear() }
            $Script:Report.Clear()
            $Script:RunStart = Get-Date
            $Script:TotalSteps = 2
            $Script:CurrentStep = 0
            [void](Invoke-RecommendedOptimizationFixes -OpenTips)
            Update-GuiGamingStatus
            Update-GuiDevicePanel
            Update-GuiOptimizationScore -Refresh
            Show-RunSummaryDialog -Title "Optimization fixes summary"
        }
    })

    $btnScanScore.Add_Click({
        Invoke-GuiAction -Title "Optimization score" -Action {
            $Script:Report.Clear()
            $Script:TotalSteps = 1
            $Script:CurrentStep = 0
            Invoke-OptimizationScoreReport
            Update-GuiOptimizationScore -Refresh
            Update-GuiDevicePanel
            Update-GuiStatusBar -JobText "Optimization score scanned"
        }
    })

    $btnFixPower.Add_Click({
        Invoke-GuiAction -Title "Fix power plan" -Action {
            $Script:Report.Clear()
            $Script:TotalSteps = 1
            $Script:CurrentStep = 0
            Write-Step "Power plan"
            $ok = Enable-UltimatePerformancePlan
            $name = Get-ActivePowerPlanName
            if ($ok) { Write-Ok "Active plan: $name" } else { Write-Ok "Set best available plan: $name" }
            Update-GuiDevicePanel
            Update-GuiGamingStatus
        }
    })

    $btnDiscordOff.Add_Click({
        if ($Script:GuiBusy) { return }
        try {
            Set-DiscordHardwareAcceleration $false
            [void](Show-UiMessageBox `
                -Text "Discord hardwareAcceleration set to false.`nFully quit and reopen Discord." `
                -Caption "PC Maintenance" `
                -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
                -Icon ([System.Windows.Forms.MessageBoxIcon]::Information))
            Update-GuiGamingStatus
        } catch {
            [void](Show-UiMessageBox `
                -Text $_.Exception.Message `
                -Caption "PC Maintenance" `
                -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
                -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning))
        }
    })

    $btnRefreshGame.Add_Click({
        if ($Script:GuiBusy) { return }
        Update-GuiGamingStatus
        Update-GuiOptimizationScore -Refresh
        Update-GuiStatusBar -JobText "Gaming status refreshed"
    })

    $btnRepair.Add_Click({
        Save-GuiSettings $Script:GuiControls
        if (-not (Confirm-RepairAction -ModeName Repair -Gui)) { return }
        Invoke-GuiAction -Title "Repair" -Action {
            $logBox = Get-UiControl Log
            if ($logBox) { $logBox.Clear() }
            Apply-GuiRepairFlags -Controls $Script:GuiControls
            [void](Invoke-MaintenanceRun)
        }
    })

    $btnRestoreOnly.Add_Click({
        Invoke-GuiAction -Title "Restore point" -Action {
            $Script:Report.Clear()
            $Script:RunStart = Get-Date
            $Script:TotalSteps = 1
            $Script:CurrentStep = 0
            New-MaintenanceRestorePoint
        }
    })

    $btnRefreshDevice.Add_Click({
        Update-GuiDevicePanel
        Update-GuiHomeSummary
        Update-GuiStatusBar -JobText "Device refreshed"
        Invoke-GuiAction -Title "Device report" -Action {
            $Script:Report.Clear()
            $Script:TotalSteps = 1
            $Script:CurrentStep = 0
            Invoke-DeviceHealthReport
        }
    })

    $btnCheckUpdate.Add_Click({
        Invoke-GuiAction -Title "Update check" -Action {
            Append-UiLog "Checking GitHub releases..." "Cyan"
            $check = Test-AppUpdateAvailable
            if ($check.Status -eq 'UpdateAvailable') {
                Append-UiLog ("Update available: {0}" -f $check.Release.Tag) "Yellow"
                Show-UpdateAvailableDialog $check.Release
            } elseif ($check.Status -eq 'UpToDate') {
                Append-UiLog ("Up to date (v{0})" -f $Script:AppVersion) "Green"
                [void](Show-UiMessageBox `
                    -Text ("You are on v{0}.`nGitHub latest release: {1}`nYou are up to date." -f $Script:AppVersion, $check.Release.Tag) `
                    -Caption "PC Maintenance Kit" `
                    -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
                    -Icon ([System.Windows.Forms.MessageBoxIcon]::Information))
            } elseif ($check.Status -eq 'NewerThanRelease') {
                Append-UiLog ("Local v{0} is newer than GitHub {1}" -f $Script:AppVersion, $check.Release.Tag) "Cyan"
                [void](Show-UiMessageBox `
                    -Text ("You are on v{0}.`nGitHub latest release: {1}`n`nThis PC is ahead of the published release (dev/local build).`nNo update is needed." -f $Script:AppVersion, $check.Release.Tag) `
                    -Caption "PC Maintenance Kit" `
                    -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
                    -Icon ([System.Windows.Forms.MessageBoxIcon]::Information))
            } else {
                Append-UiLog "No GitHub release published yet (or offline)" "Yellow"
                [void](Show-UiMessageBox `
                    -Text ("Could not find a GitHub release to compare.`n`nThis PC: v{0}`nRepo: {1}`n`nPublish a Release on GitHub for update checks to work." -f $Script:AppVersion, $Script:GitHubRepo) `
                    -Caption "PC Maintenance Kit" `
                    -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
                    -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning))
            }
        }
    })

    $btnCopyRamTip.Add_Click({
        if ($Script:GuiBusy) { return }
        try {
            $tip = Copy-RamUpgradeTipToClipboard
            Append-UiLog "Copied to clipboard: $tip" "Cyan"
            Update-GuiStatusBar -JobText "RAM tip copied"
            [void](Show-UiMessageBox `
                -Text $tip `
                -Caption "RAM upgrade tip (copied)" `
                -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
                -Icon ([System.Windows.Forms.MessageBoxIcon]::Information))
        } catch {
            [void](Show-UiMessageBox `
                -Text $_.Exception.Message `
                -Caption "PC Maintenance" `
                -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
                -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning))
        }
    })

    $btnOpenStorage.Add_Click({
        if ($Script:GuiBusy) { return }
        if (Open-StorageSettings) {
            Append-UiLog "Opened Storage settings" "Gray"
            Update-GuiStatusBar -JobText "Storage settings opened"
        } else {
            [System.Windows.Forms.MessageBox]::Show(
                "Could not open Storage settings.",
                "PC Maintenance",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
        }
    })

    $btnRestartNow.Add_Click({
        # DoEvents delivers clicks during long jobs - never reboot mid-DISM/cleanup
        if ($Script:GuiBusy) { return }
        [void](Invoke-RestartComputerConfirmed)
    })

    $btnCli.Add_Click({
        if ($Script:GuiBusy) { return }
        try {
            Start-ElevatedCli
        } catch {
            [void](Show-UiMessageBox `
                -Text $_.Exception.Message `
                -Caption "PC Maintenance" `
                -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
                -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning))
        }
    })

    $btnQuit.Add_Click({
        if ($Script:GuiBusy) { return }
        Save-GuiSettings $Script:GuiControls
        $form.Close()
    })


    [void]$form.ShowDialog()
}

function Show-CliMenu {
    Clear-Host
    Write-Host ""
    Write-Host "  ========================================"
    Write-Host "     PC MAINTENANCE KIT v$($Script:AppVersion) (Gamer)"
    Write-Host "  ========================================"
    Write-Host ""
    Write-Host "  [1] Weekly Full (cleanup + gaming; WU/winget off)"
    Write-Host "  [2] Cleanup only"
    Write-Host "  [3] Updates only"
    Write-Host "  [4] Repair Windows (DISM + SFC)"
    Write-Host "  [5] Full + Repair + Updates"
    Write-Host "  [6] Gaming optimization score"
    Write-Host "  [Q] Quit"
    Write-Host "  ========================================"
    Write-Host ""

    $choice = Read-Host "  Choose option"
    switch ($choice.ToUpper()) {
        '1' { Apply-ModeFlags Full }
        '2' { Apply-ModeFlags CleanupOnly }
        '3' { Apply-ModeFlags UpdatesOnly }
        '4' {
            if (-not (Confirm-RepairAction -ModeName Repair)) {
                Write-Host "  Cancelled." -ForegroundColor Yellow
                Start-Sleep 1
                return
            }
            Apply-ModeFlags Repair
        }
        '5' {
            if (-not (Confirm-RepairAction -ModeName FullRepair)) {
                Write-Host "  Cancelled." -ForegroundColor Yellow
                Start-Sleep 1
                return
            }
            Apply-ModeFlags FullRepair
        }
        '6' {
            Write-Host ""
            [void](Invoke-OptimizationScoreReport)
            Write-Host ""
            Write-Host (Format-OptimizationScoreText)
            Write-Host ""
            Write-Host "  Press Enter to close..."
            [void][System.Console]::ReadLine()
            return
        }
        'Q' { return }
        default {
            Write-Host "  Invalid - using Weekly Full" -ForegroundColor Yellow
            Start-Sleep 1
            Apply-ModeFlags Full
        }
    }

    Write-Host ""
    Write-Host "  Starting..." -ForegroundColor DarkGray
    Start-Sleep -Seconds 1
    [void](Invoke-MaintenanceRun)
    Write-Host ""
    Write-Host "  Press Enter to close..."
    [void][System.Console]::ReadLine()
}
