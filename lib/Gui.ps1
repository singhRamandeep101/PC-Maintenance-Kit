$Script:GuiBusy = $false
$Script:LastJobText = "Ready"
$Script:LastProgressPct = 0
$Script:Theme = $null
$Script:ContentPanels = @{}
$Script:NavButtons = @{}
$Script:NavIcons = @{}

function Enable-DoubleBuffer($Control) {
    try {
        $prop = $Control.GetType().GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'Instance,NonPublic')
        if ($prop) { $prop.SetValue($Control, $true, $null) }
    } catch { }
}

function Get-GuiTheme {
    return @{
        Bg        = [System.Drawing.Color]::FromArgb(15, 23, 30)
        Header    = [System.Drawing.Color]::FromArgb(18, 28, 36)
        Panel     = [System.Drawing.Color]::FromArgb(22, 33, 43)
        PanelAlt  = [System.Drawing.Color]::FromArgb(30, 42, 54)
        Border    = [System.Drawing.Color]::FromArgb(40, 56, 70)
        Accent    = [System.Drawing.Color]::FromArgb(38, 198, 168)
        AccentDim = [System.Drawing.Color]::FromArgb(28, 140, 120)
        Cta       = [System.Drawing.Color]::FromArgb(46, 125, 50)
        CtaHover  = [System.Drawing.Color]::FromArgb(56, 142, 60)
        Success   = [System.Drawing.Color]::FromArgb(56, 200, 120)
        Warn      = [System.Drawing.Color]::FromArgb(210, 140, 60)
        Danger    = [System.Drawing.Color]::FromArgb(190, 70, 70)
        Text      = [System.Drawing.Color]::FromArgb(235, 240, 245)
        Muted     = [System.Drawing.Color]::FromArgb(130, 148, 162)
        LogBg     = [System.Drawing.Color]::FromArgb(8, 12, 16)
        BtnGhost  = [System.Drawing.Color]::FromArgb(28, 40, 52)
        IconBox   = [System.Drawing.Color]::FromArgb(18, 28, 36)
    }
}

function Get-Mdl2Char([string]$Hex) {
    $clean = ($Hex -replace '^0x', '').Trim()
    return [char][Convert]::ToInt32($clean, 16)
}

function Add-PanelBorder {
    param($Panel, $Color = $null, [int]$Width = 1)
    if ($Color) {
        $Panel.Tag = $Color
    }
    $Panel.Add_Paint({
        param($sender, $e)
        $c = if ($sender.Tag -is [System.Drawing.Color]) { $sender.Tag } else { $Script:Theme.Border }
        $pen = New-Object System.Drawing.Pen $c, $Width
        $rect = New-Object System.Drawing.Rectangle 0, 0, ($sender.Width - 1), ($sender.Height - 1)
        $e.Graphics.DrawRectangle($pen, $rect)
        $pen.Dispose()
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
            $b.ForeColor = [System.Drawing.Color]::FromArgb(10, 20, 24)
            $b.FlatAppearance.MouseOverBackColor = $t.AccentDim
        }
        'Ghost' {
            $b.BackColor = $t.BtnGhost
            $b.ForeColor = $t.Accent
            $b.FlatAppearance.BorderSize = 1
            $b.FlatAppearance.BorderColor = $t.Accent
            $b.FlatAppearance.MouseOverBackColor = $t.PanelAlt
        }
        'Danger' {
            $b.BackColor = $t.Danger
            $b.ForeColor = $t.Text
            $b.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(160, 50, 50)
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
    Add-PanelBorder $p $t.Border
    if ($Title) {
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = $Title
        $lbl.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 11)
        $lbl.ForeColor = $t.Text
        $lbl.AutoSize = $true
        $lbl.Location = New-Object System.Drawing.Point(16, 12)
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
    $card.Height = 82
    $card.Dock = "Top"
    $card.Padding = New-Object System.Windows.Forms.Padding(0, 0, 0, 10)
    $card.BackColor = $t.Bg
    Enable-DoubleBuffer $card

    $inner = New-Object System.Windows.Forms.Panel
    $inner.Dock = "Fill"
    $inner.BackColor = $t.Panel
    Add-PanelBorder $inner $t.Border
    Enable-DoubleBuffer $inner
    $card.Controls.Add($inner)

    $iconBox = New-Object System.Windows.Forms.Panel
    $iconBox.Location = New-Object System.Drawing.Point(14, 14)
    $iconBox.Size = New-Object System.Drawing.Size(44, 44)
    $iconBox.BackColor = $t.IconBox
    Add-PanelBorder $iconBox $t.Border
    $inner.Controls.Add($iconBox)

    $accentDot = New-Object System.Windows.Forms.Panel
    $accentDot.Size = New-Object System.Drawing.Size(14, 14)
    $accentDot.Location = New-Object System.Drawing.Point(15, 15)
    $accentDot.BackColor = $t.Accent
    $iconBox.Controls.Add($accentDot)

    $titleLbl = New-Object System.Windows.Forms.Label
    $titleLbl.Text = $Title
    $titleLbl.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 8.5)
    $titleLbl.ForeColor = $t.Muted
    $titleLbl.AutoSize = $true
    $titleLbl.Location = New-Object System.Drawing.Point(72, 10)
    $inner.Controls.Add($titleLbl)

    $mainLbl = New-Object System.Windows.Forms.Label
    $mainLbl.Text = "-"
    $mainLbl.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
    $mainLbl.ForeColor = $t.Text
    $mainLbl.Location = New-Object System.Drawing.Point(72, 28)
    $mainLbl.Size = New-Object System.Drawing.Size(280, 36)
    $mainLbl.Anchor = "Top,Left,Right"
    $inner.Controls.Add($mainLbl)

    $statLbl = New-Object System.Windows.Forms.Label
    $statLbl.Text = ""
    $statLbl.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5)
    $statLbl.ForeColor = $t.Accent
    $statLbl.TextAlign = "MiddleRight"
    $statLbl.Location = New-Object System.Drawing.Point(360, 18)
    $statLbl.Size = New-Object System.Drawing.Size(160, 36)
    $statLbl.Anchor = "Top,Right"
    $inner.Controls.Add($statLbl)

    $inner.Add_Resize({
        param($sender, $e)
        foreach ($ctrl in $sender.Controls) {
            if ($ctrl -is [System.Windows.Forms.Label] -and $ctrl.Anchor -band [System.Windows.Forms.AnchorStyles]::Right -and $ctrl.Anchor -band [System.Windows.Forms.AnchorStyles]::Left) {
                # main label handled by Anchor
            }
        }
        $right = $sender.Controls | Where-Object { $_.Anchor -eq ([System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right) } | Select-Object -First 1
        $mid = $sender.Controls | Where-Object { $_.Font -and $_.Font.Size -eq 10 -and $_.Location.X -eq 72 } | Select-Object -First 1
        if ($right -and $mid) {
            $mid.Width = [math]::Max(120, $right.Left - $mid.Left - 12)
        }
    })

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
    $iconBox.Location = New-Object System.Drawing.Point(8, 8)
    $iconBox.Size = New-Object System.Drawing.Size(36, 36)
    $iconBox.BackColor = $t.IconBox
    Add-PanelBorder $iconBox $t.Border
    $row.Controls.Add($iconBox)

    $accentDot = New-Object System.Windows.Forms.Panel
    $accentDot.Size = New-Object System.Drawing.Size(10, 10)
    $accentDot.Location = New-Object System.Drawing.Point(13, 13)
    $accentDot.BackColor = $t.Accent
    $iconBox.Controls.Add($accentDot)

    $titleLbl = New-Object System.Windows.Forms.Label
    $titleLbl.Text = $Title
    $titleLbl.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
    $titleLbl.ForeColor = $t.Text
    $titleLbl.AutoSize = $true
    $titleLbl.Location = New-Object System.Drawing.Point(56, 16)
    $row.Controls.Add($titleLbl)

    $valLbl = New-Object System.Windows.Forms.Label
    $valLbl.Text = "-"
    $valLbl.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
    $valLbl.ForeColor = $t.Muted
    $valLbl.TextAlign = "MiddleRight"
    $valLbl.Location = New-Object System.Drawing.Point(300, 14)
    $valLbl.Size = New-Object System.Drawing.Size(200, 24)
    $valLbl.Anchor = "Top,Right"
    $row.Controls.Add($valLbl)

    $row.Add_Paint({
        param($sender, $e)
        $pen = New-Object System.Drawing.Pen $Script:Theme.Border, 1
        $e.Graphics.DrawLine($pen, 8, ($sender.Height - 1), ($sender.Width - 8), ($sender.Height - 1))
        $pen.Dispose()
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
        'BtnWeekly','BtnCleanup','BtnUpdates','BtnRepair','BtnGamingOpt','BtnRefreshDevice',
        'BtnFixPower','BtnCopyRamTip','BtnRestartNow','BtnOpenStorage',
        'BtnDiscordOff','BtnRefreshGame','BtnRefreshHome','BtnAmd','BtnNv','BtnRestoreOnly'
    )
    foreach ($n in $runBtns) {
        $b = $Script:GuiControls.$n
        if ($b) { $b.Enabled = -not $Busy }
    }
    foreach ($key in $Script:NavButtons.Keys) {
        $Script:NavButtons[$key].Enabled = -not $Busy
    }
    if (-not $Busy) { $Script:LastJobText = "Ready" }
    Update-GuiStatusBar
}

function Invoke-GuiAction {
    param([scriptblock]$Action, [string]$Title = "Working")
    if ($Script:GuiBusy) { return }
    Set-GuiBusy $true
    Set-UiProgressValue 0
    Set-UiStatusText $Title
    Update-GuiStatusBar -JobText $Title
    try {
        & $Action
        Update-GuiHomeSummary
        Update-GuiDevicePanel
        Update-GuiGamingStatus
        Set-UiStatusText ("Done - {0}" -f (Get-Elapsed))
        Update-GuiStatusBar -JobText ("Done - {0}" -f (Get-Elapsed))
    } catch {
        Write-Fail $_.Exception.Message
        Set-UiStatusText "Failed"
        [System.Windows.Forms.MessageBox]::Show(
            $_.Exception.Message,
            "PC Maintenance",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    } finally {
        Set-GuiBusy $false
    }
}

function Update-GuiHomeSummary {
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
            $line = "{0} GB  ·  {1} stick(s)" -f $s.RamGb, $s.RamSticks
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
        $Script:GuiControls.Free.Text = ("C: free {0} GB" -f (Get-CFreeGB))
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
}

function Show-MaintenanceGui {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    $Script:Theme = Get-GuiTheme
    $t = $Script:Theme
    $Script:ContentPanels = @{}
    $Script:NavButtons = @{}
    $Script:NavIcons = @{}
    $Script:LastProgressPct = 0

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "PC Maintenance Kit v5.1"
    $form.Size = New-Object System.Drawing.Size(1060, 780)
    $form.StartPosition = "CenterScreen"
    $form.BackColor = $t.Bg
    $form.ForeColor = $t.Text
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $form.MinimumSize = New-Object System.Drawing.Size(980, 720)
    Enable-DoubleBuffer $form

    # ---- HEADER (Dock Top) ----
    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Top"
    $header.Height = 118
    $header.BackColor = $t.Header
    Enable-DoubleBuffer $header
    $form.Controls.Add($header)

    $brand = New-Object System.Windows.Forms.Label
    $brand.Text = "PC Maintenance Kit"
    $brand.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 15)
    $brand.ForeColor = $t.Text
    $brand.AutoSize = $true
    $brand.Location = New-Object System.Drawing.Point(24, 14)
    $header.Controls.Add($brand)

    $ver = New-Object System.Windows.Forms.Label
    $ver.Text = "v5.1  ·  Gamer Toolkit"
    $ver.ForeColor = $t.Accent
    $ver.AutoSize = $true
    $ver.Location = New-Object System.Drawing.Point(26, 42)
    $header.Controls.Add($ver)

    $freeLbl = New-Object System.Windows.Forms.Label
    $freeLbl.Text = "C: free -"
    $freeLbl.ForeColor = $t.Accent
    $freeLbl.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5)
    $freeLbl.AutoSize = $true
    $freeLbl.Anchor = "Top,Right"
    $freeLbl.Location = New-Object System.Drawing.Point(($header.Width - 220), 16)
    $header.Controls.Add($freeLbl)

    $rebootBadge = New-Object System.Windows.Forms.Label
    $rebootBadge.Text = "..."
    $rebootBadge.AutoSize = $true
    $rebootBadge.Anchor = "Top,Right"
    $rebootBadge.Location = New-Object System.Drawing.Point(($header.Width - 220), 40)
    $header.Controls.Add($rebootBadge)

    $header.Add_Resize({
        param($sender, $e)
        $freeLbl.Left = [math]::Max(700, $sender.ClientSize.Width - 220)
        $rebootBadge.Left = [math]::Max(700, $sender.ClientSize.Width - 220)
    })

    $navNames = @('Home','Cleanup','Updates','Gaming','Repair','Device')
    $navX = 24
    foreach ($name in $navNames) {
        $nb = New-Object System.Windows.Forms.Button
        $nb.Text = $name
        $nb.Location = New-Object System.Drawing.Point($navX, 70)
        $nb.Size = New-Object System.Drawing.Size(100, 36)
        $nb.FlatStyle = "Flat"
        $nb.FlatAppearance.BorderSize = 0
        $nb.BackColor = $t.Header
        $nb.ForeColor = $t.Muted
        $nb.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5)
        $nb.Cursor = [System.Windows.Forms.Cursors]::Hand
        $nb.Tag = "idle"
        $nb.TextAlign = "MiddleCenter"
        $nb.Add_Click({
            param($sender, $e)
            Set-ActiveNav ([string]$sender.Text)
        })
        $nb.Add_Paint({
            param($sender, $e)
            if ($sender.Tag -eq "active") {
                $pen = New-Object System.Drawing.Pen $Script:Theme.Accent, 3
                $y = $sender.Height - 2
                $e.Graphics.DrawLine($pen, 10, $y, ($sender.Width - 10), $y)
                $pen.Dispose()
            }
        })
        $header.Controls.Add($nb)
        $Script:NavButtons[$name] = $nb
        $navX += 104
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
    Add-PanelBorder $logCard $t.Accent
    $footerHost.Controls.Add($logCard)

    $logTop = New-Object System.Windows.Forms.Panel
    $logTop.Dock = "Top"
    $logTop.Height = 34
    $logTop.BackColor = $t.Panel
    $logCard.Controls.Add($logTop)

    $logTitle = New-Object System.Windows.Forms.Label
    $logTitle.Text = "Maintenance Log"
    $logTitle.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
    $logTitle.ForeColor = $t.Accent
    $logTitle.AutoSize = $true
    $logTitle.Location = New-Object System.Drawing.Point(16, 10)
    $logTop.Controls.Add($logTitle)

    $btnClearLog = New-Object System.Windows.Forms.LinkLabel
    $btnClearLog.Text = "Clear log"
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
    $btnCluster.Width = 240
    $btnCluster.BackColor = $t.Panel
    $logBottom.Controls.Add($btnCluster)

    $btnLogs = New-PremiumButton "View Full Log" (New-Object System.Drawing.Point(8, 12)) (New-Object System.Drawing.Size(120, 32)) "Muted"
    $btnCli = New-PremiumButton "CLI" (New-Object System.Drawing.Point(136, 12)) (New-Object System.Drawing.Size(44, 32)) "Muted"
    $btnQuit = New-PremiumButton "Quit" (New-Object System.Drawing.Point(186, 12)) (New-Object System.Drawing.Size(46, 32)) "Danger"
    $btnCluster.Controls.AddRange(@($btnLogs, $btnCli, $btnQuit))

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
    $progressTrack.Controls.Add($progressFill)

    $progress = New-Object System.Windows.Forms.ProgressBar
    $progress.Visible = $false
    $progress.Minimum = 0
    $progress.Maximum = 100
    $progress.Value = 0

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
    $status.Anchor = "Top,Left,Right"
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

    # ---- HOME ----
    $pageHome = New-Content "Home"
    $homeSplit = New-Object System.Windows.Forms.TableLayoutPanel
    $homeSplit.Dock = "Fill"
    $homeSplit.ColumnCount = 2
    $homeSplit.RowCount = 1
    [void]$homeSplit.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 58)))
    [void]$homeSplit.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 42)))
    $homeSplit.Padding = New-Object System.Windows.Forms.Padding(0)
    $pageHome.Controls.Add($homeSplit)

    $homeLeft = New-Object System.Windows.Forms.Panel
    $homeLeft.Dock = "Fill"
    $homeLeft.BackColor = $t.Bg
    $homeLeft.Padding = New-Object System.Windows.Forms.Padding(0, 0, 12, 0)
    $homeSplit.Controls.Add($homeLeft, 0, 0)

    $metricsHost = New-Object System.Windows.Forms.Panel
    $metricsHost.Dock = "Fill"
    $metricsHost.BackColor = $t.Bg
    $homeLeft.Controls.Add($metricsHost)

    $sumTitle = New-Object System.Windows.Forms.Label
    $sumTitle.Text = "System Summary"
    $sumTitle.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 11)
    $sumTitle.ForeColor = $t.Text
    $sumTitle.Dock = "Top"
    $sumTitle.Height = 28
    $homeLeft.Controls.Add($sumTitle)

    # Dock Top metrics: add in reverse visual order (bottom first)
    $ramCard = New-MetricCard "EDA2" "RAM"
    $gpuCard = New-MetricCard "E7F4" "GPU"
    $cpuCard = New-MetricCard "E950" "CPU"
    $metricsHost.Controls.Add($ramCard.Panel)
    $metricsHost.Controls.Add($gpuCard.Panel)
    $metricsHost.Controls.Add($cpuCard.Panel)

    $homeRight = New-Object System.Windows.Forms.Panel
    $homeRight.Dock = "Fill"
    $homeRight.BackColor = $t.Bg
    $homeRight.Padding = New-Object System.Windows.Forms.Padding(12, 0, 0, 0)
    $homeSplit.Controls.Add($homeRight, 1, 0)

    $cardOpts = New-CardPanel "Maintenance Options" "Fill"
    $homeRight.Controls.Add($cardOpts)

    $chkHomeRestore = New-PremiumCheck "Create restore point" (New-Object System.Drawing.Point(20, 48)) $true
    $chkHomeShader = New-PremiumCheck "Clear GPU shader caches" (New-Object System.Drawing.Point(20, 82)) $true
    $chkHomeGaming = New-PremiumCheck "Apply gaming optimizations" (New-Object System.Drawing.Point(20, 116)) $true
    $chkHomeWU = New-PremiumCheck "Windows Update (slow)" (New-Object System.Drawing.Point(20, 150)) $false
    $chkHomeWinget = New-PremiumCheck "winget app upgrades (slow)" (New-Object System.Drawing.Point(20, 184)) $false
    $cardOpts.Controls.AddRange(@($chkHomeRestore, $chkHomeShader, $chkHomeGaming, $chkHomeWU, $chkHomeWinget))

    $btnWeekly = New-PremiumButton "Run Weekly Full" (New-Object System.Drawing.Point(20, 236)) (New-Object System.Drawing.Size(250, 48)) "Cta"
    $btnRefreshHome = New-PremiumButton "Refresh" (New-Object System.Drawing.Point(282, 236)) (New-Object System.Drawing.Size(110, 48)) "Ghost"
    $cardOpts.Controls.AddRange(@($btnWeekly, $btnRefreshHome))

    $nextLbl = New-Object System.Windows.Forms.Label
    $nextLbl.Text = "Weekly kit · safe defaults (WU/winget off)"
    $nextLbl.ForeColor = $t.Muted
    $nextLbl.Location = New-Object System.Drawing.Point(20, 292)
    $nextLbl.AutoSize = $true
    $cardOpts.Controls.Add($nextLbl)

    $cardOpts.Add_Resize({
        param($sender, $e)
        $y = $sender.ClientSize.Height - 84
        $btnWeekly.Top = $y
        $btnRefreshHome.Top = $y
        $btnWeekly.Width = [math]::Max(180, $sender.ClientSize.Width - 160)
        $btnRefreshHome.Left = $btnWeekly.Left + $btnWeekly.Width + 12
        $btnRefreshHome.Width = 110
        $nextLbl.Top = $sender.ClientSize.Height - 28
    })

    # ---- CLEANUP ----
    $pageClean = New-Content "Cleanup"
    $cardClean = New-CardPanel "Cleanup" "Fill"
    $pageClean.Controls.Add($cardClean)

    $cleanHint = New-Object System.Windows.Forms.Label
    $cleanHint.Text = "Safe free-space cleanup. Launcher caches need confirmation and never uninstall games."
    $cleanHint.ForeColor = $t.Muted
    $cleanHint.Location = New-Object System.Drawing.Point(20, 48)
    $cleanHint.Size = New-Object System.Drawing.Size(900, 28)
    $cleanHint.Anchor = "Top,Left,Right"
    $cardClean.Controls.Add($cleanHint)

    $daysLbl = New-Object System.Windows.Forms.Label
    $daysLbl.Text = "Temp older than (days)"
    $daysLbl.ForeColor = $t.Text
    $daysLbl.Location = New-Object System.Drawing.Point(20, 90)
    $daysLbl.AutoSize = $true
    $cardClean.Controls.Add($daysLbl)

    $daysNum = New-Object System.Windows.Forms.NumericUpDown
    $daysNum.Minimum = 0
    $daysNum.Maximum = 30
    $daysNum.Value = 2
    $daysNum.Location = New-Object System.Drawing.Point(200, 88)
    $daysNum.Width = 70
    $daysNum.BackColor = $t.PanelAlt
    $daysNum.ForeColor = $t.Text
    $daysNum.BorderStyle = "FixedSingle"
    $cardClean.Controls.Add($daysNum)

    $chkCleanShader = New-PremiumCheck "GPU shader caches" (New-Object System.Drawing.Point(20, 136)) $true
    $chkSteam = New-PremiumCheck "Steam downloading cache" (New-Object System.Drawing.Point(20, 172)) $false
    $chkEpic = New-PremiumCheck "Epic launcher cache/logs" (New-Object System.Drawing.Point(20, 208)) $false
    $chkRiot = New-PremiumCheck "Riot Client cache/logs" (New-Object System.Drawing.Point(20, 244)) $false
    $cardClean.Controls.AddRange(@($chkCleanShader, $chkSteam, $chkEpic, $chkRiot))

    $btnCleanup = New-PremiumButton "Run Cleanup" (New-Object System.Drawing.Point(20, 280)) (New-Object System.Drawing.Size(200, 44)) "Primary"
    $btnCleanup.Anchor = "Bottom,Right"
    $cardClean.Controls.Add($btnCleanup)
    $cardClean.Add_Resize({
        param($sender, $e)
        $btnCleanup.Left = $sender.ClientSize.Width - 220
        $btnCleanup.Top = $sender.ClientSize.Height - 60
        $cleanHint.Width = $sender.ClientSize.Width - 40
    })

    # ---- UPDATES ----
    $pageUpd = New-Content "Updates"
    $cardUpd = New-CardPanel "Updates" "Fill"
    $pageUpd.Controls.Add($cardUpd)

    $updHint = New-Object System.Windows.Forms.Label
    $updHint.Text = "Run updates when you are not in a ranked match. Driver apps open separately."
    $updHint.ForeColor = $t.Muted
    $updHint.Location = New-Object System.Drawing.Point(20, 48)
    $updHint.Size = New-Object System.Drawing.Size(900, 28)
    $updHint.Anchor = "Top,Left,Right"
    $cardUpd.Controls.Add($updHint)

    $chkUpdRestore = New-PremiumCheck "Create restore point first" (New-Object System.Drawing.Point(20, 96)) $true
    $chkUpdWU = New-PremiumCheck "Windows Update" (New-Object System.Drawing.Point(20, 132)) $true
    $chkUpdWinget = New-PremiumCheck "winget upgrades" (New-Object System.Drawing.Point(20, 168)) $true
    $cardUpd.Controls.AddRange(@($chkUpdRestore, $chkUpdWU, $chkUpdWinget))

    $btnUpdates = New-PremiumButton "Run Updates" (New-Object System.Drawing.Point(20, 240)) (New-Object System.Drawing.Size(180, 44)) "Primary"
    $btnAmd = New-PremiumButton "Open AMD Adrenalin" (New-Object System.Drawing.Point(220, 240)) (New-Object System.Drawing.Size(200, 44)) "Ghost"
    $btnNv = New-PremiumButton "Open NVIDIA App" (New-Object System.Drawing.Point(440, 240)) (New-Object System.Drawing.Size(180, 44)) "Ghost"
    $btnUpdates.Anchor = "Bottom,Left"
    $btnAmd.Anchor = "Bottom,Left"
    $btnNv.Anchor = "Bottom,Left"
    $cardUpd.Controls.AddRange(@($btnUpdates, $btnAmd, $btnNv))
    $cardUpd.Add_Resize({
        param($sender, $e)
        $y = $sender.ClientSize.Height - 60
        $btnUpdates.Top = $y
        $btnAmd.Top = $y
        $btnNv.Top = $y
        $updHint.Width = $sender.ClientSize.Width - 40
    })

    # ---- GAMING ----
    $pageGame = New-Content "Gaming"
    $gameSplit = New-Object System.Windows.Forms.TableLayoutPanel
    $gameSplit.Dock = "Fill"
    $gameSplit.ColumnCount = 2
    $gameSplit.RowCount = 1
    [void]$gameSplit.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 62)))
    [void]$gameSplit.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 38)))
    $pageGame.Controls.Add($gameSplit)

    $gameLeft = New-Object System.Windows.Forms.Panel
    $gameLeft.Dock = "Fill"
    $gameLeft.Padding = New-Object System.Windows.Forms.Padding(0, 0, 12, 0)
    $gameSplit.Controls.Add($gameLeft, 0, 0)

    $cardGameStatus = New-CardPanel "Gaming Status" "Fill"
    $gameLeft.Controls.Add($cardGameStatus)

    $rowsHost = New-Object System.Windows.Forms.Panel
    $rowsHost.Location = New-Object System.Drawing.Point(8, 44)
    $rowsHost.Size = New-Object System.Drawing.Size(560, 260)
    $rowsHost.Anchor = "Top,Bottom,Left,Right"
    $rowsHost.BackColor = $t.Panel
    $cardGameStatus.Controls.Add($rowsHost)

    $rowDiscord = New-GameStatusRow "E8BD" "Discord HW accel"
    $rowPower = New-GameStatusRow "E945" "Power Plan"
    $rowRelive = New-GameStatusRow "E7F4" "AMD ReLive"
    $rowDvr = New-GameStatusRow "E722" "Xbox Game DVR"
    $rowGm = New-GameStatusRow "E7FC" "Game Mode"
    $rowsHost.Controls.Add($rowDiscord.Panel)
    $rowsHost.Controls.Add($rowPower.Panel)
    $rowsHost.Controls.Add($rowRelive.Panel)
    $rowsHost.Controls.Add($rowDvr.Panel)
    $rowsHost.Controls.Add($rowGm.Panel)

    $cardGameStatus.Add_Resize({
        param($sender, $e)
        $rowsHost.Width = $sender.ClientSize.Width - 16
        $rowsHost.Height = $sender.ClientSize.Height - 52
    })

    $gameRight = New-Object System.Windows.Forms.Panel
    $gameRight.Dock = "Fill"
    $gameRight.Padding = New-Object System.Windows.Forms.Padding(12, 0, 0, 0)
    $gameSplit.Controls.Add($gameRight, 1, 0)

    $cardGameActions = New-CardPanel "Actions" "Fill"
    $gameRight.Controls.Add($cardGameActions)

    $btnGamingOpt = New-PremiumButton "Apply gaming optimize" (New-Object System.Drawing.Point(24, 52)) (New-Object System.Drawing.Size(280, 48)) "Primary"
    $btnFixPower = New-PremiumButton "Fix power plan (Ultimate)" (New-Object System.Drawing.Point(24, 112)) (New-Object System.Drawing.Size(280, 48)) "Ghost"
    $btnDiscordOff = New-PremiumButton "Discord HW accel OFF" (New-Object System.Drawing.Point(24, 172)) (New-Object System.Drawing.Size(280, 48)) "Ghost"
    $btnRefreshGame = New-PremiumButton "Refresh status" (New-Object System.Drawing.Point(24, 232)) (New-Object System.Drawing.Size(280, 48)) "Ghost"
    $cardGameActions.Controls.AddRange(@($btnGamingOpt, $btnFixPower, $btnDiscordOff, $btnRefreshGame))

    $gameTip = New-Object System.Windows.Forms.Label
    $gameTip.Text = "Tip: Fullscreen + FPS near refresh rate usually beats uncapped FPS."
    $gameTip.ForeColor = $t.Muted
    $gameTip.Location = New-Object System.Drawing.Point(24, 292)
    $gameTip.Size = New-Object System.Drawing.Size(280, 40)
    $gameTip.Anchor = "Bottom,Left,Right"
    $cardGameActions.Controls.Add($gameTip)

    $cardGameActions.Add_Resize({
        param($sender, $e)
        $w = [math]::Max(200, $sender.ClientSize.Width - 48)
        foreach ($b in @($btnGamingOpt, $btnFixPower, $btnDiscordOff, $btnRefreshGame)) {
            $b.Width = $w
        }
        $gameTip.Width = $w
        $gameTip.Top = $sender.ClientSize.Height - 48
    })

    # ---- REPAIR ----
    $pageRepair = New-Content "Repair"
    $cardRepair = New-CardPanel "Repair" "Fill"
    $pageRepair.Controls.Add($cardRepair)

    $repHint = New-Object System.Windows.Forms.Label
    $repHint.Text = "Only when Windows feels broken. DISM + SFC can take 10-30+ minutes."
    $repHint.ForeColor = $t.Muted
    $repHint.Location = New-Object System.Drawing.Point(20, 52)
    $repHint.Size = New-Object System.Drawing.Size(900, 28)
    $repHint.Anchor = "Top,Left,Right"
    $cardRepair.Controls.Add($repHint)

    $chkRepRestore = New-PremiumCheck "Create restore point first" (New-Object System.Drawing.Point(20, 100)) $true
    $cardRepair.Controls.Add($chkRepRestore)

    $btnRepair = New-PremiumButton "Run DISM + SFC" (New-Object System.Drawing.Point(20, 160)) (New-Object System.Drawing.Size(200, 48)) "Danger"
    $btnRestoreOnly = New-PremiumButton "Restore point only" (New-Object System.Drawing.Point(240, 160)) (New-Object System.Drawing.Size(200, 48)) "Ghost"
    $cardRepair.Controls.AddRange(@($btnRepair, $btnRestoreOnly))

    # ---- DEVICE ----
    $pageDev = New-Content "Device"
    $devSplit = New-Object System.Windows.Forms.TableLayoutPanel
    $devSplit.Dock = "Fill"
    $devSplit.ColumnCount = 2
    $devSplit.RowCount = 1
    [void]$devSplit.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 62)))
    [void]$devSplit.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 38)))
    $pageDev.Controls.Add($devSplit)

    $devLeft = New-Object System.Windows.Forms.Panel
    $devLeft.Dock = "Fill"
    $devLeft.Padding = New-Object System.Windows.Forms.Padding(0, 0, 12, 0)
    $devSplit.Controls.Add($devLeft, 0, 0)

    $cardDev = New-CardPanel "Device" "Fill"
    $devLeft.Controls.Add($cardDev)

    $deviceSummary = New-Object System.Windows.Forms.TextBox
    $deviceSummary.Multiline = $true
    $deviceSummary.ReadOnly = $true
    $deviceSummary.ScrollBars = "Vertical"
    $deviceSummary.BorderStyle = "None"
    $deviceSummary.BackColor = $t.Panel
    $deviceSummary.ForeColor = $t.Text
    $deviceSummary.Font = New-Object System.Drawing.Font("Consolas", 9.5)
    $deviceSummary.Location = New-Object System.Drawing.Point(16, 48)
    $deviceSummary.Size = New-Object System.Drawing.Size(500, 250)
    $deviceSummary.Anchor = "Top,Bottom,Left,Right"
    $cardDev.Controls.Add($deviceSummary)

    $devRight = New-Object System.Windows.Forms.Panel
    $devRight.Dock = "Fill"
    $devRight.Padding = New-Object System.Windows.Forms.Padding(12, 0, 0, 0)
    $devSplit.Controls.Add($devRight, 1, 0)

    $cardDevAct = New-CardPanel "Quick Actions" "Fill"
    $devRight.Controls.Add($cardDevAct)

    $btnRefreshDevice = New-PremiumButton "Refresh" (New-Object System.Drawing.Point(24, 52)) (New-Object System.Drawing.Size(280, 40)) "Ghost"
    $btnCopyRamTip = New-PremiumButton "Copy RAM upgrade tip" (New-Object System.Drawing.Point(24, 104)) (New-Object System.Drawing.Size(280, 40)) "Ghost"
    $btnOpenStorage = New-PremiumButton "Open Storage settings" (New-Object System.Drawing.Point(24, 156)) (New-Object System.Drawing.Size(280, 40)) "Muted"
    $btnRestartNow = New-PremiumButton "Restart PC now" (New-Object System.Drawing.Point(24, 208)) (New-Object System.Drawing.Size(280, 40)) "Danger"
    $cardDevAct.Controls.AddRange(@($btnRefreshDevice, $btnCopyRamTip, $btnOpenStorage, $btnRestartNow))

    $devTip = New-Object System.Windows.Forms.Label
    $devTip.Text = "Gaming optimize and power plan live on the Gaming tab."
    $devTip.ForeColor = $t.Muted
    $devTip.Location = New-Object System.Drawing.Point(24, 270)
    $devTip.Size = New-Object System.Drawing.Size(280, 40)
    $devTip.Anchor = "Bottom,Left,Right"
    $cardDevAct.Controls.Add($devTip)

    $cardDevAct.Add_Resize({
        param($sender, $e)
        $w = [math]::Max(200, $sender.ClientSize.Width - 48)
        foreach ($b in @($btnRefreshDevice, $btnCopyRamTip, $btnOpenStorage, $btnRestartNow)) {
            $b.Width = $w
        }
        $devTip.Width = $w
        $devTip.Top = $sender.ClientSize.Height - 48
    })

    $Script:GuiControls = [pscustomobject]@{
        Form            = $form
        Free            = $freeLbl
        RebootBadge     = $rebootBadge
        StatusBar       = $statusBar
        CpuMain         = $cpuCard.Main
        CpuStat         = $cpuCard.Stat
        GpuMain         = $gpuCard.Main
        GpuStat         = $gpuCard.Stat
        RamMain         = $ramCard.Main
        RamStat         = $ramCard.Stat
        DeviceSummary   = $deviceSummary
        GameModeVal     = $rowGm.Value
        GameDvrVal      = $rowDvr.Value
        ReLiveVal       = $rowRelive.Value
        PowerVal        = $rowPower.Value
        DiscordVal      = $rowDiscord.Value
        ChkHomeRestore  = $chkHomeRestore
        ChkHomeShader   = $chkHomeShader
        ChkHomeGaming   = $chkHomeGaming
        ChkHomeWU       = $chkHomeWU
        ChkHomeWinget   = $chkHomeWinget
        DaysNum         = $daysNum
        ChkCleanShader  = $chkCleanShader
        ChkSteam        = $chkSteam
        ChkEpic         = $chkEpic
        ChkRiot         = $chkRiot
        ChkUpdRestore   = $chkUpdRestore
        ChkUpdWU        = $chkUpdWU
        ChkUpdWinget    = $chkUpdWinget
        ChkRepRestore   = $chkRepRestore
        BtnWeekly       = $btnWeekly
        BtnCleanup      = $btnCleanup
        BtnUpdates      = $btnUpdates
        BtnRepair       = $btnRepair
        BtnGamingOpt    = $btnGamingOpt
        BtnRefreshDevice = $btnRefreshDevice
        BtnFixPower     = $btnFixPower
        BtnCopyRamTip   = $btnCopyRamTip
        BtnRestartNow   = $btnRestartNow
        BtnOpenStorage  = $btnOpenStorage
        BtnDiscordOff   = $btnDiscordOff
        BtnRefreshGame  = $btnRefreshGame
        BtnRefreshHome  = $btnRefreshHome
        BtnAmd          = $btnAmd
        BtnNv           = $btnNv
        BtnRestoreOnly  = $btnRestoreOnly
    }

    $Script:Ui = [pscustomobject]@{
        Form          = $form
        Progress      = $progress
        ProgressFill  = $progressFill
        ProgressTrack = $progressTrack
        Status        = $status
        Log           = $log
        Free          = $freeLbl
    }

    Set-ActiveNav "Home"
    Update-GuiHomeSummary
    Update-GuiDevicePanel
    Update-GuiGamingStatus
    Update-GuiStatusBar -JobText "Ready"
    Append-UiLog "PC Maintenance Kit v5.1 ready" "Cyan"

    $btnClearLog.Add_Click({
        $box = Get-UiControl Log
        if ($box) { $box.Clear() }
    })

    $btnWeekly.Add_Click({
        Invoke-GuiAction -Title "Weekly Full" -Action {
            $logBox = Get-UiControl Log
            if ($logBox) { $logBox.Clear() }
            Append-UiLog "Weekly Full starting..." "Cyan"
            $Script:DoCleanup = $true
            $Script:DoRestorePoint = [bool]$Script:GuiControls.ChkHomeRestore.Checked
            $Script:DoShaderCleanup = [bool]$Script:GuiControls.ChkHomeShader.Checked
            $Script:DoGamingOptimize = [bool]$Script:GuiControls.ChkHomeGaming.Checked
            $Script:DoWinUpdate = [bool]$Script:GuiControls.ChkHomeWU.Checked
            $Script:DoWinget = [bool]$Script:GuiControls.ChkHomeWinget.Checked
            $Script:DoAmd = $false
            $Script:DoRepair = $false
            $Script:TempOlderThanDays = 2
            [void](Invoke-MaintenanceRun)
            [System.Windows.Forms.MessageBox]::Show(
                "Weekly run finished.`nLogs: Desktop\PC-Maintenance-Logs",
                "PC Maintenance",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
        }
    })

    $btnRefreshHome.Add_Click({
        Update-GuiHomeSummary
        Update-GuiGamingStatus
        Update-GuiStatusBar -JobText "Home refreshed"
    })

    $btnCleanup.Add_Click({
        $needConfirm = $Script:GuiControls.ChkSteam.Checked -or $Script:GuiControls.ChkEpic.Checked -or $Script:GuiControls.ChkRiot.Checked
        if ($needConfirm) {
            $r = [System.Windows.Forms.MessageBox]::Show(
                "Clear selected launcher caches?`nThis does not uninstall games.",
                "Confirm cleanup",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Question
            )
            if ($r -ne [System.Windows.Forms.DialogResult]::Yes) { return }
        }
        Invoke-GuiAction -Title "Cleanup" -Action {
            $logBox = Get-UiControl Log
            if ($logBox) { $logBox.Clear() }
            Init-Log
            $Script:Report.Clear()
            $Script:RunStart = Get-Date
            $Script:TempOlderThanDays = [int]$Script:GuiControls.DaysNum.Value
            $Script:TotalSteps = 3
            if ($Script:GuiControls.ChkCleanShader.Checked) { $Script:TotalSteps++ }
            if ($Script:GuiControls.ChkSteam.Checked -or $Script:GuiControls.ChkEpic.Checked -or $Script:GuiControls.ChkRiot.Checked) { $Script:TotalSteps++ }
            $Script:CurrentStep = 0
            Invoke-TempCleanup
            Invoke-BrowserCacheCleanup
            Invoke-RecycleAndCleanMgr
            if ($Script:GuiControls.ChkCleanShader.Checked) { Invoke-ShaderCacheCleanup }
            if ($Script:GuiControls.ChkSteam.Checked -or $Script:GuiControls.ChkEpic.Checked -or $Script:GuiControls.ChkRiot.Checked) {
                $doSteam = [bool]$Script:GuiControls.ChkSteam.Checked
                $doEpic  = [bool]$Script:GuiControls.ChkEpic.Checked
                $doRiot  = [bool]$Script:GuiControls.ChkRiot.Checked
                Invoke-LauncherCacheCleanup -Steam:$doSteam -Epic:$doEpic -Riot:$doRiot
            }
            Append-UiLog "Cleanup finished." "Green"
        }
    })

    $btnUpdates.Add_Click({
        Invoke-GuiAction -Title "Updates" -Action {
            $logBox = Get-UiControl Log
            if ($logBox) { $logBox.Clear() }
            $Script:DoCleanup = $false
            $Script:DoShaderCleanup = $false
            $Script:DoGamingOptimize = $false
            $Script:DoRepair = $false
            $Script:DoAmd = $false
            $Script:DoRestorePoint = [bool]$Script:GuiControls.ChkUpdRestore.Checked
            $Script:DoWinUpdate = [bool]$Script:GuiControls.ChkUpdWU.Checked
            $Script:DoWinget = [bool]$Script:GuiControls.ChkUpdWinget.Checked
            if (-not $Script:DoWinUpdate -and -not $Script:DoWinget) {
                Write-Warn "Nothing selected"
                return
            }
            [void](Invoke-MaintenanceRun)
        }
    })

    $btnAmd.Add_Click({
        Invoke-GuiAction -Title "AMD" -Action {
            Init-Log
            $Script:Report.Clear()
            $Script:TotalSteps = 1
            $Script:CurrentStep = 0
            Invoke-AmdOpen
        }
    })

    $btnNv.Add_Click({
        Invoke-GuiAction -Title "NVIDIA" -Action {
            Init-Log
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
            Init-Log
            $Script:Report.Clear()
            $Script:RunStart = Get-Date
            $Script:TotalSteps = 2
            $Script:CurrentStep = 0
            Invoke-GamingOptimize
            Invoke-GamingChecks
            Update-GuiGamingStatus
        }
    })

    $btnFixPower.Add_Click({
        Invoke-GuiAction -Title "Fix power plan" -Action {
            Init-Log
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
        try {
            Set-DiscordHardwareAcceleration $false
            [System.Windows.Forms.MessageBox]::Show(
                "Discord hardwareAcceleration set to false.`nFully quit and reopen Discord.",
                "PC Maintenance",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
            Update-GuiGamingStatus
        } catch {
            [System.Windows.Forms.MessageBox]::Show(
                $_.Exception.Message,
                "PC Maintenance",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
        }
    })

    $btnRefreshGame.Add_Click({
        Update-GuiGamingStatus
        Update-GuiStatusBar -JobText "Gaming status refreshed"
    })

    $btnRepair.Add_Click({
        $r = [System.Windows.Forms.MessageBox]::Show(
            "Run DISM + SFC?`nThis can take 10-30+ minutes. Do not close the app.",
            "Confirm repair",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($r -ne [System.Windows.Forms.DialogResult]::Yes) { return }
        Invoke-GuiAction -Title "Repair" -Action {
            $logBox = Get-UiControl Log
            if ($logBox) { $logBox.Clear() }
            $Script:DoCleanup = $false
            $Script:DoShaderCleanup = $false
            $Script:DoGamingOptimize = $false
            $Script:DoWinUpdate = $false
            $Script:DoWinget = $false
            $Script:DoAmd = $false
            $Script:DoRepair = $true
            $Script:DoRestorePoint = [bool]$Script:GuiControls.ChkRepRestore.Checked
            [void](Invoke-MaintenanceRun)
        }
    })

    $btnRestoreOnly.Add_Click({
        Invoke-GuiAction -Title "Restore point" -Action {
            Init-Log
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
            Init-Log
            $Script:Report.Clear()
            $Script:TotalSteps = 1
            $Script:CurrentStep = 0
            Invoke-DeviceHealthReport
        }
    })

    $btnCopyRamTip.Add_Click({
        try {
            $tip = Copy-RamUpgradeTipToClipboard
            Append-UiLog "Copied to clipboard: $tip" "Cyan"
            Update-GuiStatusBar -JobText "RAM tip copied"
            [System.Windows.Forms.MessageBox]::Show(
                $tip,
                "RAM upgrade tip (copied)",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
        } catch {
            [System.Windows.Forms.MessageBox]::Show(
                $_.Exception.Message,
                "PC Maintenance",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
        }
    })

    $btnOpenStorage.Add_Click({
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
        [void](Invoke-RestartComputerConfirmed)
    })

    $btnLogs.Add_Click({
        $dir = Join-Path $env:USERPROFILE "Desktop\PC-Maintenance-Logs"
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Start-Process explorer.exe $dir
    })

    $btnCli.Add_Click({
        $scriptPath = Join-Path $Script:AppRoot "PC-Maintenance.ps1"
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -Mode Cli"
    })

    $btnQuit.Add_Click({ $form.Close() })

    [void]$form.ShowDialog()
}

function Show-CliMenu {
    Clear-Host
    Write-Host ""
    Write-Host "  ========================================"
    Write-Host "     PC MAINTENANCE KIT v5.1 (Gamer)"
    Write-Host "  ========================================"
    Write-Host "  Logs: Desktop\PC-Maintenance-Logs"
    Write-Host ""
    Write-Host "  [1] Weekly Full (cleanup + gaming; WU/winget off)"
    Write-Host "  [2] Cleanup only"
    Write-Host "  [3] Updates only"
    Write-Host "  [4] Repair Windows (DISM + SFC)"
    Write-Host "  [5] Full + Repair + Updates"
    Write-Host "  [Q] Quit"
    Write-Host "  ========================================"
    Write-Host ""

    $choice = Read-Host "  Choose option"
    switch ($choice.ToUpper()) {
        '1' { Apply-ModeFlags Full }
        '2' { Apply-ModeFlags CleanupOnly }
        '3' { Apply-ModeFlags UpdatesOnly }
        '4' { Apply-ModeFlags Repair }
        '5' { Apply-ModeFlags FullRepair }
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
