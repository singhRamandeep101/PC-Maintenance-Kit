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
    # One slate family plus one cyan accent. Muted text stays light enough to read
    # on Panel; it used to be a blue-gray that disappeared into the navy cards.
    # Palette from the PC Maintenance Figma file: slate cards, cyan accent, green status.
    return @{
        Bg          = [System.Drawing.Color]::FromArgb(15, 15, 27)
        Header      = [System.Drawing.Color]::FromArgb(20, 20, 36)
        Panel       = [System.Drawing.Color]::FromArgb(26, 26, 46)
        PanelAlt    = [System.Drawing.Color]::FromArgb(20, 20, 36)
        Border      = [System.Drawing.Color]::FromArgb(37, 37, 66)
        GhostBorder = [System.Drawing.Color]::FromArgb(62, 62, 104)
        Accent      = [System.Drawing.Color]::FromArgb(0, 180, 216)
        Accent2     = [System.Drawing.Color]::FromArgb(0, 119, 182)
        Cta         = [System.Drawing.Color]::FromArgb(0, 180, 216)
        CtaHover    = [System.Drawing.Color]::FromArgb(0, 200, 230)
        Success     = [System.Drawing.Color]::FromArgb(34, 197, 94)
        Warn        = [System.Drawing.Color]::FromArgb(245, 158, 11)
        Danger      = [System.Drawing.Color]::FromArgb(239, 68, 68)
        Text        = [System.Drawing.Color]::FromArgb(255, 255, 255)
        Muted       = [System.Drawing.Color]::FromArgb(165, 165, 197)
        LogBg       = [System.Drawing.Color]::FromArgb(12, 12, 22)
        BtnGhost    = [System.Drawing.Color]::FromArgb(20, 20, 36)
        IconBox     = [System.Drawing.Color]::FromArgb(28, 28, 48)
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

function New-IconWell {
    # Circle, not a square. The glyph is soft, so a sharp box around it looks broken.
    param(
        [string]$Glyph,
        [int]$Size = 46,
        [single]$GlyphPt = 14,
        $GlyphColor,
        $Fill,
        $Back
    )
    $well = New-Object System.Windows.Forms.Panel
    $well.Size = New-Object System.Drawing.Size($Size, $Size)
    $well.BackColor = $Back
    Enable-DoubleBuffer $well
    $glyphHex = $Glyph
    $glyphPt = $GlyphPt
    $fillColor = $Fill
    $ink = $GlyphColor
    $well.Add_Paint({
        param($sender, $e)
        try {
            $g = $e.Graphics
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $d = [Math]::Min($sender.Width, $sender.Height) - 2
            if ($d -lt 8) { return }
            $x = [int](($sender.Width - $d) / 2)
            $y = [int](($sender.Height - $d) / 2)
            $brush = New-Object System.Drawing.SolidBrush $fillColor
            $g.FillEllipse($brush, $x, $y, $d, $d)
            $brush.Dispose()
            $font = New-Object System.Drawing.Font('Segoe MDL2 Assets', $glyphPt)
            $rect = New-Object System.Drawing.Rectangle(0, 1, $sender.Width, $sender.Height)
            $flags = [System.Windows.Forms.TextFormatFlags]::HorizontalCenter -bor [System.Windows.Forms.TextFormatFlags]::VerticalCenter
            [System.Windows.Forms.TextRenderer]::DrawText($g, (Get-Mdl2Char $glyphHex), $font, $rect, $ink, $flags)
            $font.Dispose()
        } catch { }
    }.GetNewClosure())
    return $well
}

function Add-PanelBorder {
    param($Panel, $Color = $null, [int]$Width = 1, [int]$Radius = 12)
    if (-not $Color) { $Color = $Script:Theme.Border }
    $Panel.Tag = @{ Color = $Color; Radius = $Radius }
    # Do not clip the panel to a rounded Region. That clip hides label text and
    # cuts controls off after a resize. The border is painted; the card stays rectangular.
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
            $b.ForeColor = [System.Drawing.Color]::White
            $b.FlatAppearance.MouseOverBackColor = $t.CtaHover
            $b.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
        }
        'Ghost' {
            $b.BackColor = $t.BtnGhost
            $b.ForeColor = $t.Text
            $b.FlatAppearance.MouseOverBackColor = $t.PanelAlt
        }
        'Danger' {
            $b.BackColor = $t.Danger
            $b.ForeColor = [System.Drawing.Color]::White
            $b.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(220, 60, 60)
        }
        'Muted' {
            $b.BackColor = $t.PanelAlt
            $b.ForeColor = $t.Text
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
                $edge = $Script:Theme.GhostBorder
                if (-not $edge) { $edge = $accent }
                $pen2 = New-Object System.Drawing.Pen $edge, 1
                $g.DrawPath($pen2, $path2)
                $pen2.Dispose()
                $path2.Dispose()
        } catch { }
    })
    }
    # WinForms paints disabled Flat buttons with system gray, which vanishes on these panels.
    $b.Add_Paint({
        param($sender, $e)
        if ($sender.Enabled) { return }
        try {
            $flags = [System.Windows.Forms.TextFormatFlags]::HorizontalCenter -bor [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::EndEllipsis
            $rect = New-Object System.Drawing.Rectangle(6, 0, [Math]::Max(1, $sender.Width - 12), $sender.Height)
            [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, [string]$sender.Text, $sender.Font, $rect, $Script:Theme.Muted, $flags)
        } catch { }
    })
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
    $c.BackColor = $t.Bg
    $c.UseVisualStyleBackColor = $false
    $c.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $c.FlatStyle = "Flat"
    try {
        $c.FlatAppearance.BorderColor = $t.Border
        $c.FlatAppearance.CheckedBackColor = $t.PanelAlt
        $c.FlatAppearance.MouseOverBackColor = $t.PanelAlt
    } catch { }
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
    $card.Height = 104
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

    $iconBox = New-IconWell -Glyph $Glyph -Size 48 -GlyphPt 15 -GlyphColor $t.Accent -Fill $t.IconBox -Back $t.Panel
    $iconBox.Location = New-Object System.Drawing.Point(16, 26)
    $inner.Controls.Add($iconBox)

    $titleLbl = New-Object System.Windows.Forms.Label
    $titleLbl.Text = $Title.ToUpperInvariant()
    $titleLbl.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $titleLbl.ForeColor = $t.Muted
    $titleLbl.AutoSize = $false
    $titleLbl.AutoEllipsis = $true
    $titleLbl.BackColor = [System.Drawing.Color]::Transparent
    $titleLbl.Location = New-Object System.Drawing.Point(76, 12)
    $titleLbl.Size = New-Object System.Drawing.Size(180, 16)
    $inner.Controls.Add($titleLbl)

    $mainLbl = New-Object System.Windows.Forms.Label
    $mainLbl.Text = "-"
    $mainLbl.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 11)
    $mainLbl.ForeColor = $t.Text
    $mainLbl.Location = New-Object System.Drawing.Point(76, 28)
    $mainLbl.Size = New-Object System.Drawing.Size(180, 56)
    $mainLbl.Anchor = "None"
    $mainLbl.AutoEllipsis = $true
    $mainLbl.BackColor = [System.Drawing.Color]::Transparent
    $inner.Controls.Add($mainLbl)

    $statLbl = New-Object System.Windows.Forms.Label
    $statLbl.Text = ""
    $statLbl.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5)
    $statLbl.ForeColor = $t.Accent
    $statLbl.TextAlign = "MiddleRight"
    $statLbl.Location = New-Object System.Drawing.Point(260, 34)
    $statLbl.Size = New-Object System.Drawing.Size(90, 32)
    $statLbl.Anchor = "None"
    $statLbl.AutoEllipsis = $true
    $statLbl.BackColor = [System.Drawing.Color]::Transparent
    $inner.Controls.Add($statLbl)
    $inner.Add_Resize({
        param($sender, $e)
        $statW = [Math]::Min(160, [Math]::Max(72, [int]($sender.ClientSize.Width * 0.28)))
        $statLeft = [Math]::Max(150, $sender.ClientSize.Width - $statW - 12)
        $statLbl.SetBounds($statLeft, 34, [Math]::Max(48, $sender.ClientSize.Width - $statLeft - 10), 32)
        $textW = [Math]::Max(40, $statLeft - 88)
        $titleLbl.SetBounds(76, 12, $textW, 16)
        $mainLbl.SetBounds(76, 28, $textW, 56)
    }.GetNewClosure())

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
    $row.Height = 50
    $row.Dock = "Top"
    $row.BackColor = $t.Panel
    Enable-DoubleBuffer $row

    $iconBox = New-IconWell -Glyph $Glyph -Size 36 -GlyphPt 12 -GlyphColor $t.Accent -Fill $t.IconBox -Back $t.Panel
    $iconBox.Location = New-Object System.Drawing.Point(8, 7)
    $row.Controls.Add($iconBox)

    $titleLbl = New-Object System.Windows.Forms.Label
    $titleLbl.Text = $Title
    $titleLbl.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
    $titleLbl.ForeColor = $t.Text
    $titleLbl.AutoSize = $false
    $titleLbl.AutoEllipsis = $true
    $titleLbl.BackColor = [System.Drawing.Color]::Transparent
    $titleLbl.Location = New-Object System.Drawing.Point(52, 13)
    $titleLbl.Size = New-Object System.Drawing.Size(120, 24)
    $row.Controls.Add($titleLbl)

    $valLbl = New-Object System.Windows.Forms.Label
    $valLbl.Text = "-"
    $valLbl.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
    $valLbl.ForeColor = $t.Muted
    $valLbl.TextAlign = "MiddleRight"
    $valLbl.Location = New-Object System.Drawing.Point(180, 13)
    $valLbl.Size = New-Object System.Drawing.Size(80, 24)
    $valLbl.Padding = New-Object System.Windows.Forms.Padding(16, 0, 2, 0)
    $valLbl.AutoEllipsis = $true
    $valLbl.Anchor = "None"
    $valLbl.BackColor = [System.Drawing.Color]::Transparent
    $layoutRow = {
        param($sender, $e)
        $span = $sender.ClientSize.Width
        if ($span -lt 40) { return }
        $valW = [Math]::Min(220, [Math]::Max(88, [int]($span * 0.48)))
        $valLeft = $span - $valW - 8
        if ($valLeft -lt 100) { $valLeft = 100 }
        if (($valLeft + $valW) -gt ($span - 4)) { $valW = [Math]::Max(40, $span - $valLeft - 8) }
        $valLbl.SetBounds($valLeft, 13, $valW, 24)
        $titleLbl.SetBounds(52, 13, [Math]::Max(24, $valLeft - 60), 24)
    }.GetNewClosure()
    $row.Add_Resize($layoutRow)
    $row.Add_Layout($layoutRow)
    & $layoutRow $row $null
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

function Test-GuiProbeStale {
    param($Utc, [int]$Seconds = 10)
    if ($null -eq $Utc) { return $true }
    try {
        if (([datetime]$Utc) -eq [datetime]::MinValue) { return $true }
        return (([datetime]::UtcNow - ([datetime]$Utc)).TotalSeconds -ge $Seconds)
    } catch {
        return $true
    }
}

function Update-GuiPageOnVisit([string]$Name) {
    # Opening Home, Gaming, or Security reads again once the last result is
    # older than 10 seconds. Hardware probes keep their own longer cache.
    if ($Script:GuiBusy) { return }
    if ($Name -eq 'Security') {
        if (Test-GuiProbeStale $Script:SecurityHealthCacheUtc) {
            Update-GuiSecurityPanel -Refresh
        }
        return
    }
    if ($Name -ne 'Home' -and $Name -ne 'Gaming') { return }
    if (-not (Test-GuiProbeStale $Script:OptimizationScoreCacheUtc)) { return }
    $Script:OptimizationScoreCache = $null
    $Script:OptimizationScoreCacheUtc = [datetime]::MinValue
    $Script:SecurityHealthCache = $null
    $Script:SecurityHealthCacheUtc = [datetime]::MinValue
    $Script:AutoServiceCache = $null
    $Script:AutoServiceCacheUtc = [datetime]::MinValue
    $Script:LogonTaskCache = $null
    $Script:LogonTaskCacheUtc = [datetime]::MinValue
    if ($Name -eq 'Home') {
        Update-GuiOptimizationScore
        Update-GuiSecurityHomeLine
    } else {
        Update-GuiGamingStatus
    }
}

function Set-ActiveNav([string]$Name, [switch]$FromUser) {
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
    if ($FromUser) { Update-GuiPageOnVisit $Name }
}

function Set-GuiBusy([bool]$Busy) {
    $Script:GuiBusy = $Busy
    $runBtns = @(
        'BtnWeekly','BtnCleanup','BtnPreview','BtnUpdates','BtnRepair','BtnGamingOpt','BtnRefreshDevice',
        'BtnFixPower','BtnRestorePower','BtnCopyRamTip','BtnRestartNow','BtnOpenStorage',
        'BtnDiscordOff','BtnRefreshGame','BtnRefreshHome','BtnAmd','BtnNv','BtnRestoreOnly',
        'BtnCheckUpdate','BtnCli','BtnQuit','BtnScanScore','BtnApplyOptFixes','BtnFixMyPc',
        'BtnPresetGamer','BtnPresetQuiet','BtnPresetFull','ChkScheduleWeekly','ChkScheduleUpdates','ChkScheduleGaming',
        'BtnOpenMalwarebytes','BtnOpenWindowsSecurity','BtnRefreshSecurity','BtnOpenStartup'
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
        $Script:LiveStatusTarget = $null
        if (Get-Command Set-PageLiveStatus -EA SilentlyContinue) {
            try { Set-PageLiveStatus -Idle } catch { }
        }
    }
    if (Get-Command Update-MalwarebytesLaunchButton -EA SilentlyContinue) {
        try { Update-MalwarebytesLaunchButton } catch { }
    }
    Update-GuiStatusBar
}

function Set-PageLiveStatus {
    param(
        [string]$Text = "",
        [switch]$Idle
    )
    if (-not $Script:GuiControls) { return }
    $map = [ordered]@{
        Cleanup = @{ Ctrl = 'LblCleanupLive'; Idle = 'Ready - preview sizes or run cleanup.' }
        Updates = @{ Ctrl = 'LblUpdatesLive'; Idle = 'Ready - Windows Update and winget when you need them.' }
        Repair  = @{ Ctrl = 'LblRepairLive'; Idle = 'No repair running' }
    }
    $target = $Script:LiveStatusTarget
    foreach ($page in @($map.Keys)) {
        $info = $map[$page]
        $lbl = $Script:GuiControls.($info.Ctrl)
        if (-not $lbl) { continue }
        if ($Idle) {
            $lbl.Text = $info.Idle
            continue
        }
        if ($target -and $page -eq $target) {
            $lbl.Text = $Text
        }
    }
}

function Resolve-LiveStatusTarget([string]$Title) {
    if ([string]::IsNullOrWhiteSpace($Title)) { return $null }
    switch -Regex ($Title) {
        '(?i)cleanup|preview' { return 'Cleanup' }
        '(?i)^updates$|windows update|winget' { return 'Updates' }
        '(?i)repair|dism|sfc|restore point' { return 'Repair' }
        default { return $null }
    }
}

function Resolve-GuiRefreshMode([string]$Title) {
    if ([string]::IsNullOrWhiteSpace($Title)) { return 'Light' }
    switch -Regex ($Title) {
        '(?i)^(AMD|NVIDIA)$|Checking for updates|Update check|Device report|Optimization score|Fix my PC|Gaming optimize|Recommended fixes|Security health' { return 'None' }
        '(?i)cleanup|preview|weekly|repair|^updates$|restore|power|discord' { return 'Space' }
        default { return 'Light' }
    }
}

function Invoke-GuiPanelsRefresh {
    param(
        [ValidateSet('None','Light','Hardware','Space')]$Mode = 'Light',
        [string]$DoneText = ""
    )
    if ($Mode -eq 'None') {
        if ($DoneText) {
            Set-UiStatusText $DoneText
            Update-GuiStatusBar -JobText $DoneText
        }
        return
    }
    if ($Mode -eq 'Hardware') {
        if (Get-Command Clear-HardwareProbeCaches -EA SilentlyContinue) {
            Clear-HardwareProbeCaches
        } else {
            $Script:DeviceSummaryCache = $null
            $Script:OptimizationScoreCache = $null
            $Script:SecurityHealthCache = $null
            $Script:SecurityHealthCacheUtc = [datetime]::MinValue
            $Script:AutoServiceCache = $null
            $Script:AutoServiceCacheUtc = [datetime]::MinValue
            $Script:LogonTaskCache = $null
            $Script:LogonTaskCacheUtc = [datetime]::MinValue
        }
        # Score refresh pulls a fresh device summary once; then bind all panels from cache.
        try { $null = Get-GamingOptimizationScore -Refresh } catch {
            Write-Warn ("Could not refresh the score: {0}" -f $_.Exception.Message)
            try { $null = Get-DeviceSummary -Refresh } catch {
                Write-Warn ("Could not read this PC: {0}" -f $_.Exception.Message)
            }
        }
        Pump-Ui
    } elseif ($Mode -eq 'Space') {
        # Free space, reboot, and power plan only. Do not reload CPU/GPU/disk.
        if ($Script:DeviceSummaryCache) {
            try { $Script:DeviceSummaryCache.FreeGb = Get-CFreeGB -Refresh } catch {
                Write-Warn ("Could not read free space: {0}" -f $_.Exception.Message)
            }
            try { $Script:DeviceSummaryCache.RebootPending = Test-RebootPending -Refresh } catch {
                Write-Warn ("Could not read restart status: {0}" -f $_.Exception.Message)
            }
            try { $Script:DeviceSummaryCache.PowerPlan = Get-ActivePowerPlanName -Refresh } catch {
                Write-Warn ("Could not read the power plan: {0}" -f $_.Exception.Message)
            }
        }
        $Script:OptimizationScoreCache = $null
        try { $null = Get-GamingOptimizationScore } catch {
            Write-Warn ("Could not refresh the score: {0}" -f $_.Exception.Message)
        }
        Pump-Ui
    }
    try { Update-GuiHomeSummary } catch {
        Write-Warn ("Could not refresh Home: {0}" -f $_.Exception.Message)
    }
    Pump-Ui
    try { Update-GuiDevicePanel } catch {
        Write-Warn ("Could not refresh Device: {0}" -f $_.Exception.Message)
    }
    Pump-Ui
    try { Update-GuiSecurityPanel } catch {
        Write-Warn ("Could not refresh Security: {0}" -f $_.Exception.Message)
    }
    Pump-Ui
    try { Update-GuiGamingStatus -SkipScore } catch {
        Write-Warn ("Could not refresh Gaming: {0}" -f $_.Exception.Message)
    }
    if ($DoneText) {
        Set-UiStatusText $DoneText
        Update-GuiStatusBar -JobText $DoneText
    }
}

function Start-GuiDeferredRefresh {
    param(
        [string]$DoneText = "Done",
        [ValidateSet('None','Light','Hardware','Space')]$Mode = 'Hardware'
    )
    # Paint "Done" immediately, then refresh panels on the next UI tick so the
    # window does not sit frozen after a long job while CIM/score re-scan.
    if ($Mode -eq 'None') {
        if ($DoneText) {
            Set-UiStatusText $DoneText
            Update-GuiStatusBar -JobText $DoneText
        }
        return
    }
    $form = Get-UiControl Form
    if (-not $form -or $form.IsDisposed) {
        Invoke-GuiPanelsRefresh -Mode $Mode -DoneText $DoneText
        return
    }
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 40
    $timer.Add_Tick({
        param($sender, $e)
        try {
            $sender.Stop()
            $sender.Dispose()
        } catch { }
        try {
            Set-UiStatusText "Refreshing panels..."
            Update-GuiStatusBar -JobText "Refreshing panels..."
            Pump-Ui
            Invoke-GuiPanelsRefresh -Mode $Mode -DoneText $DoneText
        } catch {
            try {
                Set-UiStatusText $DoneText
                Update-GuiStatusBar -JobText $DoneText
            } catch { }
        }
    }.GetNewClosure())
    $timer.Start()
}

function Confirm-OptionalCleanupCaches {
    $needConfirm = $Script:GuiControls.ChkSteam.Checked -or $Script:GuiControls.ChkEpic.Checked -or $Script:GuiControls.ChkRiot.Checked -or $Script:GuiControls.ChkWuCache.Checked
    if (-not $needConfirm) { return $true }
    $parts = [System.Collections.Generic.List[string]]::new()
    if ($Script:GuiControls.ChkSteam.Checked) { [void]$parts.Add("Steam downloading cache only (does not uninstall games)") }
    if ($Script:GuiControls.ChkEpic.Checked) {
        [void]$parts.Add("Epic webcache, logs, ProgramData EMS, and .egstore staging folders")
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

function Get-GuiCleanupPreviewFingerprint {
    return ("{0}|{1}|{2}|{3}|{4}|{5}" -f `
        [int]$Script:GuiControls.DaysNum.Value, `
        [bool]$Script:GuiControls.ChkCleanShader.Checked, `
        [bool]$Script:GuiControls.ChkSteam.Checked, `
        [bool]$Script:GuiControls.ChkEpic.Checked, `
        [bool]$Script:GuiControls.ChkRiot.Checked, `
        [bool]$Script:GuiControls.ChkWuCache.Checked)
}

function Get-GuiCleanupPreview {
    $fp = Get-GuiCleanupPreviewFingerprint
    if ($Script:CleanupPreviewCache -and
        $Script:CleanupPreviewCache.Fingerprint -eq $fp -and
        (([datetime]::UtcNow - $Script:CleanupPreviewCache.Utc).TotalSeconds -lt 90)) {
        Write-Info "Reusing recent cleanup preview (same options)"
        return $Script:CleanupPreviewCache.Preview
    }
    $preview = Get-CleanupPreview `
        -TempOlderThanDays ([int]$Script:GuiControls.DaysNum.Value) `
        -Shaders ([bool]$Script:GuiControls.ChkCleanShader.Checked) `
        -Steam ([bool]$Script:GuiControls.ChkSteam.Checked) `
        -Epic ([bool]$Script:GuiControls.ChkEpic.Checked) `
        -Riot ([bool]$Script:GuiControls.ChkRiot.Checked) `
        -WuCache ([bool]$Script:GuiControls.ChkWuCache.Checked)
    $Script:CleanupPreviewCache = @{
        Fingerprint = $fp
        Utc         = [datetime]::UtcNow
        Preview     = $preview
    }
    return $preview
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
    $Script:StartFree = Get-CFreeGB -Refresh
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
    } finally {
        $Script:CleanupPreviewCache = $null
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
                if (Get-Command Set-PageLiveStatus -EA SilentlyContinue) {
                    try { Set-PageLiveStatus -Text ([string]$item.Text) } catch { }
                }
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
    $Script:LiveStatusTarget = Resolve-LiveStatusTarget $Title
    $refreshMode = Resolve-GuiRefreshMode $Title
    Set-GuiBusy $true
    Set-UiProgressValue 0
    Set-UiStatusText $Title
    Update-GuiStatusBar -JobText $Title
    # Paint Stop/disabled buttons before long work (DoEvents keeps Cancel responsive later)
    Pump-Ui

    $doneText = $null
    try {
        & $Action
        if (-not (Test-CancelRequested)) {
            $doneText = ("Done - {0}" -f (Get-Elapsed))
            Set-UiStatusText $doneText
            Update-GuiStatusBar -JobText $doneText
        } else {
            $doneText = "Cancelled"
            Set-UiStatusText $doneText
            Update-GuiStatusBar -JobText $doneText
        }
        Save-GuiSettings $Script:GuiControls
    } catch {
        if ($_.Exception.Message -match 'Cancelled') {
            Write-Warn "Cancelled by user"
            $doneText = "Cancelled"
            Set-UiStatusText $doneText
        } else {
            Write-Fail $_.Exception.Message
            $doneText = "Failed"
            Set-UiStatusText $doneText
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
            if ($doneText) {
                Start-GuiDeferredRefresh -DoneText $doneText -Mode $refreshMode
            }
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
        $info = Get-RebootPendingInfo
        if ($info.Pending) {
            $reason = if ($info.Reasons -and $info.Reasons.Count -gt 0) { $info.Reasons[0] } else { 'pending' }
            $badge.Text = ("Reboot: {0}" -f $reason)
            $badge.ForeColor = $t.Warn
        } else {
            $badge.Text = "No restart pending"
            $badge.ForeColor = $t.Success
        }
        try {
            if ($Script:MainForm -and -not $Script:MainForm.IsDisposed) {
                foreach ($c in $Script:MainForm.Controls) {
                    if ($c.Tag -and $c.Tag.Reboot) { $c.Invalidate(); break }
                }
            }
        } catch { }
    }

    # Keep the Home score card in sync without forcing a CIM refresh every time
    Update-GuiOptimizationScore -Refresh:$Refresh
    try { Update-GuiSecurityHomeLine } catch { }
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

function Get-ScoreLetter([string]$Grade) {
    switch ($Grade) {
        'Excellent' { return 'A' }
        'Good' { return 'B' }
        'Needs work' { return 'C' }
        default { return 'D' }
    }
}

function Update-GuiSecurityHomeLine {
    param($Health)
    if (-not $Script:GuiControls -or -not $Script:GuiControls.HomeSecurityVal) { return }
    if (-not $Health) {
        if (-not (Get-Command Get-SecurityHealth -EA SilentlyContinue)) { return }
        try { $Health = Get-SecurityHealth } catch { return }
    }
    $line = ("Security: {0}" -f $Health.Verdict)
    $Script:GuiControls.HomeSecurityVal.Text = $line
    if ($Script:Theme) {
        if ($Health.Verdict -eq 'Protected') {
            $Script:GuiControls.HomeSecurityVal.ForeColor = $Script:Theme.Success
        } elseif ($Health.Verdict -eq 'Needs attention') {
            $Script:GuiControls.HomeSecurityVal.ForeColor = $Script:Theme.Warn
        } else {
            $Script:GuiControls.HomeSecurityVal.ForeColor = $Script:Theme.Muted
        }
    }
}

function Update-MalwarebytesLaunchButton {
    if (-not $Script:GuiControls) { return }
    $btn = $Script:GuiControls.BtnOpenMalwarebytes
    if (-not $btn) { return }
    if ($Script:GuiBusy) {
        $btn.Enabled = $false
        return
    }
    $path = $null
    try {
        if (Get-Command Get-SecurityHealth -EA SilentlyContinue) {
            $path = (Get-SecurityHealth).Malwarebytes.Path
        }
    } catch { }
    $btn.Enabled = [bool]($path -and (Test-Path -LiteralPath $path))
}

function Set-SecurityRowColor($Ctrl, [string]$State) {
    if (-not $Ctrl -or -not $Script:Theme) { return }
    $t = $Script:Theme
    if ($State -eq 'On' -or $State -eq 'Current' -or $State -eq 'None' -or $State -eq 'Protected') {
        $Ctrl.ForeColor = $t.Success
    } elseif ($State -eq 'Off' -or $State -eq 'Out of date' -or $State -eq 'Needs attention') {
        $Ctrl.ForeColor = $t.Warn
    } elseif ($State -eq 'Unknown' -or $State -eq 'Not installed' -or $State -eq 'Muted') {
        $Ctrl.ForeColor = $t.Muted
    } else {
        $Ctrl.ForeColor = $t.Text
    }
}

function Update-GuiSecurityPanel {
    param([switch]$Refresh)
    if (-not $Script:GuiControls) { return }
    if (-not (Get-Command Get-SecurityHealth -EA SilentlyContinue)) { return }
    $health = $null
    try { $health = Get-SecurityHealth -Refresh:$Refresh } catch { return }
    if (-not $health) { return }

    Set-GuiLabelText SecVerdict $health.Verdict
    Set-SecurityRowColor $Script:GuiControls.SecVerdict $health.Verdict
    $summary = 'Real-time protection is on. Scans stay in Windows Security or Malwarebytes.'
    if ($health.Verdict -ne 'Protected' -and $health.Reasons -and @($health.Reasons).Count -gt 0) {
        $summary = [string]@($health.Reasons)[0]
    }
    Set-GuiLabelText SecSummary $summary
    if ($health.Verdict -eq 'Needs attention') {
        Set-SecurityRowColor $Script:GuiControls.SecSummary 'Needs attention'
    } else {
        Set-SecurityRowColor $Script:GuiControls.SecSummary 'Muted'
    }

    $sigText = $health.Defender.Signatures
    if (Get-Command Format-SignatureHealthText -EA SilentlyContinue) {
        $sigText = Format-SignatureHealthText $health.Defender
    }
    Set-GuiLabelText SecRealtime $health.Defender.RealTime
    Set-SecurityRowColor $Script:GuiControls.SecRealtime $health.Defender.RealTime
    Set-GuiLabelText SecSignatures $sigText
    Set-SecurityRowColor $Script:GuiControls.SecSignatures $health.Defender.Signatures
    Set-GuiLabelText SecQuickScan $health.Defender.LastQuickScan
    Set-GuiLabelText SecFullScan $health.Defender.LastFullScan
    Set-GuiLabelText SecThreats $health.Defender.Threats
    $threatState = 'Unknown'
    if ($null -ne $health.Defender.ThreatCount) {
        if ($health.Defender.ThreatCount -gt 0) { $threatState = 'Needs attention' } else { $threatState = 'None' }
    }
    Set-SecurityRowColor $Script:GuiControls.SecThreats $threatState
    Set-GuiLabelText SecFirewall $health.Firewall.Detail
    Set-SecurityRowColor $Script:GuiControls.SecFirewall $health.Firewall.Status
    Set-GuiLabelText SecMalwarebytes $health.Malwarebytes.Detail
    $mbState = 'Not installed'
    if ($health.Malwarebytes.Installed) { $mbState = 'Installed' }
    Set-SecurityRowColor $Script:GuiControls.SecMalwarebytes $mbState

    $pill = [string]$health.Verdict
    if ($health.Verdict -eq 'Needs attention' -and $health.Reasons -and @($health.Reasons).Count -gt 0) {
        $pill = ("{0} - {1}" -f $health.Verdict, [string]@($health.Reasons)[0])
    }
    Set-GuiLabelText SecPill $pill
    Set-SecurityRowColor $Script:GuiControls.SecPill $health.Verdict
    Update-GuiSecurityHomeLine -Health $health
    Update-MalwarebytesLaunchButton
}

function Set-GuiLabelText($Name, [string]$Text) {
    if (-not $Script:GuiControls) { return }
    $ctrl = $Script:GuiControls.$Name
    if ($ctrl) { $ctrl.Text = $Text }
}

function Update-GuiDevicePanel {
    $box = $Script:GuiControls.DeviceSummary
    try {
        if ($box) { $box.Text = Format-DeviceSummaryText }
    } catch {
        if ($box) { $box.Text = "Unavailable" }
    }
    try {
        $s = Get-DeviceSummary
    } catch {
        return
    }
    $reboot = if ($s.RebootPending) { 'Yes' } else { 'No' }
    $rebootPill = if ($s.RebootPending) { 'Restart recommended' } else { 'No reboot pending' }
    $disk = [string]$s.DiskName
    if ($s.DiskHealth -and $s.DiskHealth -ne 'Unknown') { $disk = "$disk  [$($s.DiskHealth)]" }
    $trim = [string]$s.TrimInfo
    if ($trim -match 'SSD') { $trim = 'SSD detected' }
    elseif ($trim -match 'HDD') { $trim = 'HDD' }
    $cpuShort = ([string]$s.Cpu -replace 'Intel(\(R\))?|Core\(TM\)|CPU|Processor|NVIDIA|GeForce', '')
    $cpuShort = ($cpuShort -replace '\s+', ' ').Trim()
    $gpuShort = ([string]$s.Gpu -replace 'NVIDIA|GeForce', '')
    $gpuShort = ($gpuShort -replace '\s+', ' ').Trim()
    if ($cpuShort.Length -gt 24) { $cpuShort = $cpuShort.Substring(0, 24).Trim() }
    if ($gpuShort.Length -gt 24) { $gpuShort = $gpuShort.Substring(0, 24).Trim() }
    Set-GuiLabelText DevCpu $s.Cpu
    Set-GuiLabelText DevGpu $s.Gpu
    Set-GuiLabelText DevRam ("{0:N1} GB ({1} sticks)" -f $s.RamGb, $s.RamSticks)
    Set-GuiLabelText DevChannels $s.RamChannels
    Set-GuiLabelText DevDisk $disk
    Set-GuiLabelText DevTrim $trim
    Set-GuiLabelText DevFree ("{0:N0} GB" -f $s.FreeGb)
    Set-GuiLabelText DevPower $s.PowerPlan
    Set-GuiLabelText DevReboot $reboot
    Set-GuiLabelText DevRebootPill $rebootPill
    $rebootPillCtrl = $Script:GuiControls.DevRebootPill
    if ($rebootPillCtrl) {
        $rebootPillCtrl.ForeColor = if ($s.RebootPending) { $Script:Theme.Warn } else { $Script:Theme.Success }
    }
    $dot = [char]0x00B7
    Set-GuiLabelText DevChip ("{0}  {1}  {2}" -f $cpuShort, $dot, $gpuShort)
    try { Set-GuiLabelText DevRamTip (Get-RamUpgradeTip) } catch { }
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
            if ($gr) {
                if ($pair.Score -eq 'OptScoreVal') { $gr.Text = "" } else { $gr.Text = "Score unavailable" }
                $gr.ForeColor = $t.Muted
            }
            if ($lm) { $lm.Text = "" }
            if ($fx) { $fx.Text = "" }
        }
        Set-GuiLabelText OptGradeLetter '-'
        Set-GuiLabelText DevGradeLetter '-'
        Set-GuiLabelText OptStatusPill 'Score unavailable'
        Set-GuiLabelText DevScoreLine 'Score unavailable'
    }

    try {
        $score = Get-GamingOptimizationScore -Refresh:$Refresh
    } catch {
        Set-ScoreUnavailable
        return
    }

    $scoreColor = if ($score.Score -ge 70) { $t.Accent } elseif ($score.Score -ge 50) { $t.Warn } else { $t.Danger }
    $ready = $score.HardwareReadiness.Label
    $limiterText = ("Limiter: {0}  |  Hardware you own: {1}. Top fixes are the part you can change." -f $score.BiggestLimiter, $ready)
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
    if ($score.ScoreNote) {
        $fixText = ([string]$score.ScoreNote) + "`r`n" + $fixText
    }
    $gradeLabel = [string]$score.Grade
    if ($null -ne $score.WeightedScore -and [int]$score.WeightedScore -ne [int]$score.Score) {
        $gradeLabel = ("{0}  (weighted {1})" -f $score.Grade, [int]$score.WeightedScore)
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
            if ($pair.Score -eq 'OptScoreVal') { $sc.ForeColor = $t.Text } else { $sc.ForeColor = $scoreColor }
        }
        if ($gr) {
            if ($pair.Score -eq 'OptScoreVal') {
                $gr.Text = $gradeLabel
                $gr.ForeColor = $t.Accent
            } else {
                $gr.Text = ("/100  {0}" -f $gradeLabel)
                $gr.ForeColor = $t.Text
            }
        }
        if ($lm) {
            if ($pair.Score -eq 'OptScoreVal') {
                $lm.Text = if ($score.BiggestLimiter) { [string]$score.BiggestLimiter } else { 'Setup looks tuned for gaming.' }
            } else {
                $lm.Text = $limiterText
            }
            $lm.ForeColor = $t.Muted
        }
        if ($fx) {
            $fx.Text = $fixText
            $fx.ForeColor = $t.Muted
        }
    }
    $letter = Get-ScoreLetter $score.Grade
    Set-GuiLabelText OptGradeLetter $letter
    Set-GuiLabelText DevGradeLetter $letter
    $dot = [char]0x00B7
    Set-GuiLabelText OptStatusPill ("Score {0}  {1}  {2}" -f $score.Score, $dot, $gradeLabel)
    Set-GuiLabelText DevScoreLine ("{0} / 100  {1}  {2}" -f $score.Score, $dot, $gradeLabel)
}

function Update-GuiGamingStatus {
    param([switch]$SkipScore, [switch]$RefreshScore)
    $t = $Script:Theme
    $gm = Get-GameModeEnabled
    $dvr = Get-GameDvrEnabled
    $relive = Get-AmdReLiveEnabled
    $power = Get-ActivePowerPlanName
    $discord = Get-DiscordHardwareAcceleration

    function Set-StatusVal($ctrl, $text, $good) {
        if (-not $ctrl) { return }
        $ctrl.Text = $text
        $ctrl.ForeColor = if ($good) { $t.Success } else { $t.Text }
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

    try {
        $startupApps = @(Get-StartupApps)
        $startupText = Format-StartupAppList $startupApps
        $startupOn = @($startupApps | Where-Object { $_.Enabled }).Count
        $holdText = ''
        try { $holdText = Format-StartupServiceHoldList (Get-StartupServiceHolds -Apps $startupApps) } catch { $holdText = '' }
        if ($holdText) { $startupText = $startupText + "`r`n" + $holdText }
        $logonText = ''
        try { $logonText = Format-LogonTaskList (Get-ExtraLogonTaskNames -Apps $startupApps) } catch { $logonText = '' }
        if ($logonText) { $startupText = $startupText + "`r`n" + $logonText }
        Set-GuiLabelText GameStartupVal $startupText
        if ($Script:GuiControls.GameStartupVal) {
            if ($holdText -or $startupOn -gt 5) {
                if ($startupOn -gt 12) { $Script:GuiControls.GameStartupVal.ForeColor = $t.Danger }
                else { $Script:GuiControls.GameStartupVal.ForeColor = $t.Warn }
            } else {
                $Script:GuiControls.GameStartupVal.ForeColor = $t.Success
            }
        }
    } catch {
        Set-GuiLabelText GameStartupVal 'Could not read startup apps'
    }

    if (-not $SkipScore) {
        Update-GuiOptimizationScore -Refresh:$RefreshScore
    }
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

# Page builders (Home/Cleanup/Updates/Gaming/Repair/Security/Device)
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
    $form.MinimumSize = New-Object System.Drawing.Size(1000, 740)
    $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $form.AutoScaleDimensions = New-Object System.Drawing.SizeF(96.0, 96.0)
    # MinimumSize is not scaled with the rest of the form. On a 150% display the
    # layout grows, then a resize below that scaled size piles controls on top of each other.
    $form.Add_Load({
        param($sender, $e)
        $dpi = 96
        try { $dpi = [int]$sender.DeviceDpi } catch { $dpi = 96 }
        if ($dpi -lt 96) { $dpi = 96 }
        $scale = $dpi / 96.0
        $minW = [int](1000 * $scale)
        $minH = [int](740 * $scale)
        $sender.MinimumSize = New-Object System.Drawing.Size($minW, $minH)
        if ($sender.ClientSize.Width -lt $minW -or $sender.ClientSize.Height -lt $minH) {
            $sender.Size = New-Object System.Drawing.Size([Math]::Max($sender.Width, $minW), [Math]::Max($sender.Height, $minH))
        }
    })
    Enable-DoubleBuffer $form


    # ---- HEADER (Dock Top) ----
    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Top"
    $header.Height = 58
    $header.BackColor = $t.Header
    Enable-DoubleBuffer $header
    $form.Controls.Add($header)

    $header.Tag = @{ Theme = $t }
    $header.Padding = New-Object System.Windows.Forms.Padding(16, 8, 12, 8)

    $chipHost = New-Object System.Windows.Forms.Panel
    $chipHost.Dock = 'Right'
    $chipHost.Width = 260
    $chipHost.BackColor = $t.Header
    $header.Controls.Add($chipHost)

    $freeLbl = New-Object System.Windows.Forms.Label
    $freeLbl.Text = "C: free -"
    $freeLbl.ForeColor = $t.Accent
    $freeLbl.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5)
    $freeLbl.Dock = 'Top'
    $freeLbl.Height = 22
    $freeLbl.TextAlign = 'MiddleRight'
    $freeLbl.AutoEllipsis = $true
    $freeLbl.BackColor = $t.Header
    $chipHost.Controls.Add($freeLbl)

    $rebootBadge = New-Object System.Windows.Forms.Label
    $rebootBadge.Text = "..."
    $rebootBadge.ForeColor = $t.Text
    $rebootBadge.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5)
    $rebootBadge.Dock = 'Top'
    $rebootBadge.Height = 22
    $rebootBadge.TextAlign = 'MiddleRight'
    $rebootBadge.AutoEllipsis = $true
    $rebootBadge.BackColor = $t.Header
    $chipHost.Controls.Add($rebootBadge)
    # Dock Top is reversed: add reboot first so free sits on top.
    $chipHost.Controls.SetChildIndex($freeLbl, 0)

    $header.Tag = @{ Free = $freeLbl; Reboot = $rebootBadge; Theme = $t }

    $Script:NavGlyphs = @{
        Home    = 'E80F'
        Cleanup = 'E74D'
        Updates = 'E895'
        Gaming  = 'E7FC'
        Repair  = 'E90F'
        Security = 'E72E'
        Device  = 'E7F4'
    }

    $brandHost = New-Object System.Windows.Forms.Panel
    $brandHost.Dock = 'Fill'
    $brandHost.BackColor = $t.Header
    $header.Controls.Add($brandHost)

    $brand = New-Object System.Windows.Forms.Label
    $brand.Text = "PC Maintenance Kit"
    $brand.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 14)
    $brand.ForeColor = $t.Text
    $brand.AutoSize = $false
    $brand.AutoEllipsis = $true
    $brand.Dock = 'Top'
    $brand.Height = 26
    $brand.TextAlign = 'MiddleLeft'
    $brand.BackColor = $t.Header
    $ver = New-Object System.Windows.Forms.Label
    $ver.Text = "v$($Script:AppVersion)  |  Gamer toolkit"
    $ver.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $ver.ForeColor = $t.Muted
    $ver.AutoSize = $false
    $ver.AutoEllipsis = $true
    $ver.Dock = 'Top'
    $ver.Height = 18
    $ver.TextAlign = 'MiddleLeft'
    $ver.BackColor = $t.Header
    $brandHost.Controls.Add($ver)
    $brandHost.Controls.Add($brand)


    $navRail = New-Object System.Windows.Forms.Panel
    $navRail.Dock = 'Left'
    $navRail.Width = 176
    $navRail.BackColor = $t.Header
    $navRail.Padding = New-Object System.Windows.Forms.Padding(8, 12, 8, 8)

    $navNames = @('Device','Security','Repair','Gaming','Updates','Cleanup','Home')
    foreach ($name in $navNames) {
        $nb = New-Object System.Windows.Forms.Button
        $nb.Text = $name
        $nb.Dock = 'Top'
        $nb.Height = 40
        $nb.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)
        $nb.FlatStyle = "Flat"
        $nb.FlatAppearance.BorderSize = 0
        $nb.BackColor = $t.Header
        $nb.ForeColor = $t.Muted
        $nb.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5)
        $nb.Cursor = [System.Windows.Forms.Cursors]::Hand
        $nb.Tag = "idle"
        $nb.TextAlign = "MiddleLeft"
        $nb.Padding = New-Object System.Windows.Forms.Padding(42, 0, 8, 0)
        $nb.Add_Click({
            param($sender, $e)
            Set-ActiveNav ([string]$sender.Text) -FromUser
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
                    $well = New-Object System.Drawing.SolidBrush $Script:Theme.IconBox
                    $g.FillEllipse($well, 8, [int](($sender.Height - 26) / 2), 26, 26)
                    $well.Dispose()
                    $fontG = New-Object System.Drawing.Font("Segoe MDL2 Assets", 10.5)
                    [System.Windows.Forms.TextRenderer]::DrawText($g, (Get-Mdl2Char $glyphCode), $fontG, (New-Object System.Drawing.Rectangle(8, 0, 26, $sender.Height)), $sender.ForeColor, ([System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::HorizontalCenter))
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
        $nb.Add_Paint({
            param($sender, $e)
            if ($sender.Enabled) { return }
            try {
                $flags = [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::EndEllipsis
                $rect = New-Object System.Drawing.Rectangle(42, 0, [Math]::Max(1, $sender.Width - 50), $sender.Height)
                [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, [string]$sender.Text, $sender.Font, $rect, $Script:Theme.Muted, $flags)
            } catch { }
        })
        $nb.AutoEllipsis = $true
        $navRail.Controls.Add($nb)
        $Script:NavButtons[$name] = $nb
    }


    # ---- FOOTER HOST (Dock Bottom) ----
    $footerHost = New-Object System.Windows.Forms.Panel
    $footerHost.Dock = "Bottom"
    $footerHost.Height = 176
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
    $logTitle.AutoSize = $false
    $logTitle.AutoEllipsis = $true
    $logTitle.Dock = 'Fill'
    $logTitle.TextAlign = 'MiddleLeft'
    $logTitle.Padding = New-Object System.Windows.Forms.Padding(16, 0, 8, 0)
    $logTop.Controls.Add($logTitle)

    $btnClearLog = New-Object System.Windows.Forms.LinkLabel
    $btnClearLog.Text = "Clear"
    $btnClearLog.LinkColor = $t.Accent
    $btnClearLog.ActiveLinkColor = $t.Text
    $btnClearLog.VisitedLinkColor = $t.Accent
    $btnClearLog.AutoSize = $true
    $btnClearLog.Margin = New-Object System.Windows.Forms.Padding(12, 4, 0, 0)
    $btnClearLog.BackColor = $t.Panel
    $btnToggleLog = New-Object System.Windows.Forms.LinkLabel
    $btnToggleLog.Text = "Hide log"
    $btnToggleLog.LinkColor = $t.Text
    $btnToggleLog.ActiveLinkColor = $t.Accent
    $btnToggleLog.VisitedLinkColor = $t.Text
    $btnToggleLog.AutoSize = $true
    $btnToggleLog.Margin = New-Object System.Windows.Forms.Padding(12, 4, 0, 0)
    $btnToggleLog.BackColor = $t.Panel
    # Right-to-left so Clear sits on the far right and Hide log stays beside it, off the title.
    $logLinks = New-Object System.Windows.Forms.FlowLayoutPanel
    $logLinks.Dock = 'Right'
    $logLinks.Width = 168
    $logLinks.FlowDirection = 'RightToLeft'
    $logLinks.WrapContents = $false
    $logLinks.BackColor = $t.Panel
    $logLinks.Padding = New-Object System.Windows.Forms.Padding(0, 2, 10, 0)
    $logLinks.Controls.Add($btnClearLog)
    $logLinks.Controls.Add($btnToggleLog)
    $logTop.Controls.Add($logLinks)

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
    # Cyan energy fill. No Region clip, so a resize cannot chop the bar down to nothing.
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
    $progLbl.Text = "Status"
    $progLbl.ForeColor = $t.Muted
    $progLbl.AutoSize = $false
    $progLbl.Width = 64
    $progLbl.Dock = 'Left'
    $progLbl.TextAlign = 'MiddleLeft'
    $progLbl.AutoEllipsis = $true
    $progLbl.BackColor = $t.Panel
    $statusRow.Controls.Add($progLbl)

    $statusBar = New-Object System.Windows.Forms.Label
    $statusBar.Text = "Ready"
    $statusBar.ForeColor = $t.Text
    $statusBar.Width = 280
    $statusBar.Dock = 'Right'
    $statusBar.TextAlign = 'MiddleRight'
    $statusBar.AutoEllipsis = $true
    $statusBar.BackColor = $t.Panel
    $statusRow.Controls.Add($statusBar)

    $status = New-Object System.Windows.Forms.Label
    $status.Text = "Ready"
    $status.ForeColor = $t.Text
    $status.Dock = 'Fill'
    $status.TextAlign = 'MiddleLeft'
    $status.AutoEllipsis = $true
    $status.BackColor = $t.Panel
    $statusRow.Controls.Add($status)
    $statusRow.Controls.SetChildIndex($status, 0)

    $log = New-Object System.Windows.Forms.RichTextBox
    $log.Dock = "Fill"
    $log.BackColor = $t.LogBg
    $log.ForeColor = $t.Text
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
    $hostPanel.Padding = New-Object System.Windows.Forms.Padding(0)
    $form.Controls.Add($hostPanel)

    # Last added is docked first: header, then footer, then the nav rail, then the page fills what's left.
    $form.Controls.Clear()
    $form.Controls.Add($hostPanel)
    $form.Controls.Add($navRail)
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
    $pageSec = New-Content "Security"
    $pageDev = New-Content "Device"

    $homeParts = Add-GuiHomePage -Page $pageHome -Theme $t
    $cleanParts = Add-GuiCleanupPage -Page $pageClean -Theme $t
    $updParts = Add-GuiUpdatesPage -Page $pageUpd -Theme $t
    $gameParts = Add-GuiGamingPage -Page $pageGame -Theme $t
    $repairParts = Add-GuiRepairPage -Page $pageRepair -Theme $t
    $secParts = Add-GuiSecurityPage -Page $pageSec -Theme $t
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
    Merge-GuiParts $merged $secParts
    Merge-GuiParts $merged $devParts

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
        HomeSecurityVal = $merged.HomeSecurityVal
        GameModeVal     = $merged.GameModeVal
        GameDvrVal      = $merged.GameDvrVal
        ReLiveVal       = $merged.ReLiveVal
        PowerVal        = $merged.PowerVal
        DiscordVal      = $merged.DiscordVal
        GameStartupVal  = $merged.GameStartupVal
        BtnOpenStartup  = $merged.BtnOpenStartup
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
        BtnRestorePower = $merged.BtnRestorePower
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
        ChkScheduleUpdates = $merged.ChkScheduleUpdates
        ChkScheduleGaming = $merged.ChkScheduleGaming
        LblScheduleStatus = $merged.LblScheduleStatus
        LblLastScheduledRun = $merged.LblLastScheduledRun
        LblCleanupLive  = $merged.LblCleanupLive
        LblUpdatesLive  = $merged.LblUpdatesLive
        LblRepairLive   = $merged.LblRepairLive
        OptGradeLetter  = $merged.OptGradeLetter
        OptStatusPill   = $merged.OptStatusPill
        DevGradeLetter  = $merged.DevGradeLetter
        DevScoreLine    = $merged.DevScoreLine
        DevCpu          = $merged.DevCpu
        DevGpu          = $merged.DevGpu
        DevRam          = $merged.DevRam
        DevChannels     = $merged.DevChannels
        DevDisk         = $merged.DevDisk
        DevTrim         = $merged.DevTrim
        DevFree         = $merged.DevFree
        DevPower        = $merged.DevPower
        DevReboot       = $merged.DevReboot
        DevRebootPill   = $merged.DevRebootPill
        DevChip         = $merged.DevChip
        DevRamTip       = $merged.DevRamTip
        BtnOpenMalwarebytes = $merged.BtnOpenMalwarebytes
        BtnOpenWindowsSecurity = $merged.BtnOpenWindowsSecurity
        BtnRefreshSecurity = $merged.BtnRefreshSecurity
        SecFirewall     = $merged.SecFirewall
        SecFullScan     = $merged.SecFullScan
        SecMalwarebytes = $merged.SecMalwarebytes
        SecPill         = $merged.SecPill
        SecQuickScan    = $merged.SecQuickScan
        SecRealtime     = $merged.SecRealtime
        SecSignatures   = $merged.SecSignatures
        SecSummary      = $merged.SecSummary
        SecThreats      = $merged.SecThreats
        SecVerdict      = $merged.SecVerdict
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
    # Paint the window first; heavy CIM/score scans run after Shown so launch
    # does not stare at a blank desktop while PowerShell works invisibly.
    if ($Script:GuiControls.CpuMain) { $Script:GuiControls.CpuMain.Text = "Scanning..." }
    if ($Script:GuiControls.GpuMain) { $Script:GuiControls.GpuMain.Text = "Scanning..." }
    if ($Script:GuiControls.RamMain) { $Script:GuiControls.RamMain.Text = "Scanning..." }
    if ($Script:GuiControls.HomeScoreVal) { $Script:GuiControls.HomeScoreVal.Text = ".." }
    if ($Script:GuiControls.HomeGradeVal) { $Script:GuiControls.HomeGradeVal.Text = "Reading hardware..." }
    if ($Script:GuiControls.HomeSecurityVal) { $Script:GuiControls.HomeSecurityVal.Text = "Security: Reading..." }
    if ($Script:GuiControls.Free) { $Script:GuiControls.Free.Text = "C: free ..." }
    if ($Script:GuiControls.RebootBadge) { $Script:GuiControls.RebootBadge.Text = "..." }
    if ($Script:GuiControls.DeviceSummary) { $Script:GuiControls.DeviceSummary.Text = "Scanning hardware..." }
    Update-GuiStatusBar -JobText "Starting..."
    Append-UiLog ("PC Maintenance Kit v{0} starting..." -f $Script:AppVersion) "Cyan"

    $uiTimer = New-Object System.Windows.Forms.Timer
    $uiTimer.Interval = 200
    $uiTimer.Add_Tick({
        Drain-UiEventQueue
        if ($Script:GuiBusy) { Pump-Ui }
    })
    $uiTimer.Start()
    $form.Add_Shown({
        Enable-DarkTitleBar $form
        $boot = New-Object System.Windows.Forms.Timer
        $boot.Interval = 30
        $boot.Add_Tick({
            param($sender, $e)
            try { $sender.Stop(); $sender.Dispose() } catch { }
            try {
                $Script:BootScanBusy = $true
                Set-GuiBusy $true
                Set-UiStatusText "Reading hardware..."
                Update-GuiStatusBar -JobText "Reading hardware..."
                Append-UiLog "Scanning device, security, score, and gaming status..." "Cyan"
                Pump-Ui
                Invoke-GuiPanelsRefresh -Mode Hardware -DoneText "Ready"
                Update-GuiCareScheduleStatus
                Append-UiLog ("Ready - v{0}" -f $Script:AppVersion) "Green"
            } catch {
                try {
                    Set-UiStatusText "Ready"
                    Update-GuiStatusBar -JobText "Ready"
                    Append-UiLog ("Startup scan partial: {0}" -f $_.Exception.Message) "Yellow"
                } catch { }
            } finally {
                $Script:BootScanBusy = $false
                Set-GuiBusy $false
            }
        })
        $boot.Start()
    })
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
            $updBoot = New-Object System.Windows.Forms.Timer
            $updBoot.Interval = 600
            $updBoot.Add_Tick({
                param($sender, $e)
                if ($Script:GuiBusy -or $Script:BootScanBusy) {
                    # Boot scan / other work still running — retry soon instead of dropping the check.
                    $sender.Interval = 800
                    return
                }
                try { $sender.Stop(); $sender.Dispose() } catch { }
                try {
                    Invoke-GuiAction -Title "Checking for updates" -Action {
                        $check = Test-AppUpdateAvailable -Silent
                        if ($check -and $check.Status -eq 'UpdateAvailable') {
                            Show-UpdateAvailableDialog $check.Release
                        }
                    }
                } catch { }
            }.GetNewClosure())
            $updBoot.Start()
        })
    }

    $Script:LogExpanded = $true
    $btnToggleLog.Add_Click({
        if ($Script:LogExpanded) {
            $logWrap.Visible = $false
            $footerHost.Height = 112
            $btnToggleLog.Text = "Show log"
            $Script:LogExpanded = $false
        } else {
            $logWrap.Visible = $true
            $footerHost.Height = 176
            $btnToggleLog.Text = "Hide log"
            $Script:LogExpanded = $true
        }
    }.GetNewClosure())

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
    $btnRestorePower = $c.BtnRestorePower
    $btnDiscordOff = $c.BtnDiscordOff
    $btnRefreshGame = $c.BtnRefreshGame
    $btnOpenStartup = $c.BtnOpenStartup
    $btnRepair = $c.BtnRepair
    $btnRestoreOnly = $c.BtnRestoreOnly
    $btnRefreshDevice = $c.BtnRefreshDevice
    $btnCheckUpdate = $c.BtnCheckUpdate
    $btnCopyRamTip = $c.BtnCopyRamTip
    $btnOpenStorage = $c.BtnOpenStorage
    $btnRestartNow = $c.BtnRestartNow
    $btnOpenMalwarebytes = $c.BtnOpenMalwarebytes
    $btnOpenWindowsSecurity = $c.BtnOpenWindowsSecurity
    $btnRefreshSecurity = $c.BtnRefreshSecurity

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
            $Script:StartFree = Get-CFreeGB -Refresh
            $Script:TotalSteps = 2
            $Script:CurrentStep = 0
            $before = Get-GamingOptimizationScore -Refresh
            Append-UiLog ("Score before: {0}/100 ({1})" -f $before.Score, $before.Grade) "Cyan"
            $after = Invoke-RecommendedOptimizationFixes -OpenTips -BeforeScore $before
            Update-GuiHomeSummary
            Update-GuiGamingStatus -SkipScore
            Update-GuiDevicePanel
            Update-GuiOptimizationScore
            Append-UiLog ("Score after: {0}/100 ({1})  -  was {2}" -f $after.Score, $after.Grade, $before.Score) "Green"
            Show-RunSummaryDialog -Title "Fix my PC summary"
        }
    })

    $btnRefreshHome.Add_Click({
        if ($Script:GuiBusy) { return }
        Set-GuiBusy $true
        try {
            Invoke-GuiPanelsRefresh -Mode Hardware
            Update-GuiCareScheduleStatus
        } finally {
            Set-GuiBusy $false
        }
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
                    $updateNote = "Windows Update and winget stay off for this task unless you also turn on 'Weekly task may install updates'."
                    if ($Script:GuiControls.ChkScheduleUpdates -and $Script:GuiControls.ChkScheduleUpdates.Checked -and ($Script:GuiControls.ChkHomeWU.Checked -or $Script:GuiControls.ChkHomeWinget.Checked)) {
                        $updateNote = "Weekly task may install updates is on, and Windows Update or winget is checked. This task will install those while you are signed in, with nobody watching the screen."
                    }
                    $gameNote = "Shader cleanup and gaming settings stay off unless you also turn on 'Weekly task may clear shaders and apply gaming settings'."
                    if ($Script:GuiControls.ChkScheduleGaming -and $Script:GuiControls.ChkScheduleGaming.Checked -and ($Script:GuiControls.ChkHomeShader.Checked -or $Script:GuiControls.ChkHomeGaming.Checked)) {
                        $gameNote = "Weekly task may clear shaders and apply gaming settings is on. This task will do that while you are signed in."
                    }
                    $r = Show-UiMessageBox `
                        -Text ("Schedule Weekly Full every Sunday at 6 PM?`n`nCleans temps and browser caches with your saved options.`nRuns with administrator rights, while you are signed in, so it can clean Windows temp.`n`n{0}`n`n{1}`n`nThe next time you open the app, Home shows what the last run did.`nYou can turn this off anytime." -f $updateNote, $gameNote) `
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
        if ($Script:GuiBusy) { return }
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
        if ($Script:GuiBusy) { return }
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
            if (Get-Command Clear-HardwareProbeCaches -EA SilentlyContinue) { Clear-HardwareProbeCaches }
            Invoke-GamingChecks
            $Script:StartFree = Get-CFreeGB -Refresh
            Update-GuiHomeSummary
            Update-GuiGamingStatus -RefreshScore
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
            $Script:StartFree = Get-CFreeGB -Refresh
            $Script:TotalSteps = 2
            $Script:CurrentStep = 0
            [void](Invoke-RecommendedOptimizationFixes -OpenTips)
            Update-GuiHomeSummary
            Update-GuiGamingStatus -SkipScore
            Update-GuiDevicePanel
            Update-GuiOptimizationScore
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

    $btnRestorePower.Add_Click({
        Invoke-GuiAction -Title "Restore power plan" -Action {
            $Script:Report.Clear()
            $Script:TotalSteps = 1
            $Script:CurrentStep = 0
            Write-Step "Power plan"
            if (Restore-PreviousPowerPlan) {
                $name = Get-ActivePowerPlanName -Refresh
                Write-Ok "Restored power plan: $name"
            } else {
                Write-Warn "No previous power plan is saved yet"
            }
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
        Set-GuiBusy $true
        try {
            Update-GuiGamingStatus -RefreshScore
        } finally {
            Set-GuiBusy $false
        }
        Update-GuiStatusBar -JobText "Gaming status refreshed"
    })

    $btnOpenStartup.Add_Click({
        if ($Script:GuiBusy) { return }
        if (Open-StartupSettings) {
            Append-UiLog "Opened Startup apps" "Gray"
            Update-GuiStatusBar -JobText "Startup apps opened"
        } else {
            [System.Windows.Forms.MessageBox]::Show(
                "Could not open Startup apps.",
                "PC Maintenance",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
        }
    })

    $btnRepair.Add_Click({
        if ($Script:GuiBusy) { return }
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
        if ($Script:GuiBusy) { return }
        Invoke-GuiAction -Title "Device report" -Action {
            Invoke-GuiPanelsRefresh -Mode Hardware
            $Script:Report.Clear()
            $Script:TotalSteps = 1
            $Script:CurrentStep = 0
            Invoke-DeviceHealthReport
        }
    })

    $btnRefreshSecurity.Add_Click({
        if ($Script:GuiBusy) { return }
        Invoke-GuiAction -Title "Security health" -Action {
            Update-GuiSecurityPanel -Refresh
            Append-UiLog "Security status refreshed" "Gray"
        }
    })

    $btnOpenWindowsSecurity.Add_Click({
        if ($Script:GuiBusy) { return }
        if (Open-WindowsSecurity) {
            Append-UiLog "Opened Windows Security" "Gray"
            Update-GuiStatusBar -JobText "Windows Security opened"
        } else {
            [System.Windows.Forms.MessageBox]::Show(
                "Could not open Windows Security.",
                "PC Maintenance",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
        }
    })

    $btnOpenMalwarebytes.Add_Click({
        if ($Script:GuiBusy) { return }
        if (Open-Malwarebytes) {
            Append-UiLog "Opened Malwarebytes" "Gray"
            Update-GuiStatusBar -JobText "Malwarebytes opened"
        } else {
            [System.Windows.Forms.MessageBox]::Show(
                "Malwarebytes is not installed, or its program could not be opened.",
                "PC Maintenance",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
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
    Write-Host "  [7] Security health"
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
        '7' {
            Write-Host ""
            Write-Host (Format-SecurityHealthText)
            Write-Host ""
            Write-Host "  Press Enter to close..."
            [void][System.Console]::ReadLine()
            return
        }
        'Q' { return }
        default {
            Write-Host "  Unknown option. Nothing was run." -ForegroundColor Yellow
            return
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
