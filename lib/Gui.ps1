$Script:GuiBusy = $false
$Script:LastJobText = "Ready"
$Script:Theme = $null
$Script:ContentPanels = @{}
$Script:NavButtons = @{}
$Script:NavIcons = @{}

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

function Add-PanelBorder {
    param($Panel, $Color = $null, [int]$Width = 1)
    $Panel.Add_Paint({
        param($sender, $e)
        $c = if ($sender.Tag -is [System.Drawing.Color]) { $sender.Tag } else { $Script:Theme.Border }
        $pen = New-Object System.Drawing.Pen $c, $Width
        $rect = New-Object System.Drawing.Rectangle 0, 0, ($sender.Width - 1), ($sender.Height - 1)
        $e.Graphics.DrawRectangle($pen, $rect)
        $pen.Dispose()
    })
    if ($Color) { $Panel.Tag = $Color }
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
        [System.Drawing.Point]$Location,
        [System.Drawing.Size]$Size,
        [string]$Title = ""
    )
    $t = $Script:Theme
    $p = New-Object System.Windows.Forms.Panel
    $p.Location = $Location
    $p.Size = $Size
    $p.BackColor = $t.Panel
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
        [System.Drawing.Point]$Location,
        [System.Drawing.Size]$Size,
        [string]$Glyph,
        [string]$Title
    )
    $t = $Script:Theme
    $card = New-Object System.Windows.Forms.Panel
    $card.Location = $Location
    $card.Size = $Size
    $card.BackColor = $t.Panel
    Add-PanelBorder $card $t.Border

    $iconBox = New-Object System.Windows.Forms.Panel
    $iconBox.Location = New-Object System.Drawing.Point(14, 16)
    $iconBox.Size = New-Object System.Drawing.Size(44, 44)
    $iconBox.BackColor = $t.IconBox
    Add-PanelBorder $iconBox $t.Border
    $card.Controls.Add($iconBox)

    $icon = New-Object System.Windows.Forms.Label
    $icon.Text = [char][int]"0x$Glyph"
    $icon.Font = New-Object System.Drawing.Font("Segoe MDL2 Assets", 14)
    $icon.ForeColor = $t.Accent
    $icon.AutoSize = $true
    $icon.Location = New-Object System.Drawing.Point(10, 10)
    $iconBox.Controls.Add($icon)

    $titleLbl = New-Object System.Windows.Forms.Label
    $titleLbl.Text = $Title
    $titleLbl.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 8.5)
    $titleLbl.ForeColor = $t.Muted
    $titleLbl.AutoSize = $true
    $titleLbl.Location = New-Object System.Drawing.Point(72, 12)
    $card.Controls.Add($titleLbl)

    $mainLbl = New-Object System.Windows.Forms.Label
    $mainLbl.Text = "-"
    $mainLbl.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
    $mainLbl.ForeColor = $t.Text
    $mainLbl.Location = New-Object System.Drawing.Point(72, 32)
    $mainLbl.Size = New-Object System.Drawing.Size(300, 40)
    $card.Controls.Add($mainLbl)

    $statLbl = New-Object System.Windows.Forms.Label
    $statLbl.Text = ""
    $statLbl.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5)
    $statLbl.ForeColor = $t.Accent
    $statLbl.TextAlign = "MiddleRight"
    $statLbl.Location = New-Object System.Drawing.Point(($Size.Width - 170), 22)
    $statLbl.Size = New-Object System.Drawing.Size(150, 36)
    $card.Controls.Add($statLbl)

    return [pscustomobject]@{
        Panel = $card
        Main  = $mainLbl
        Stat  = $statLbl
    }
}

function New-GameStatusRow {
    param(
        [System.Drawing.Point]$Location,
        [int]$Width,
        [string]$Glyph,
        [string]$Title
    )
    $t = $Script:Theme
    $row = New-Object System.Windows.Forms.Panel
    $row.Location = $Location
    $row.Size = New-Object System.Drawing.Size($Width, 52)
    $row.BackColor = $t.Panel

    $iconBox = New-Object System.Windows.Forms.Panel
    $iconBox.Location = New-Object System.Drawing.Point(8, 8)
    $iconBox.Size = New-Object System.Drawing.Size(36, 36)
    $iconBox.BackColor = $t.IconBox
    Add-PanelBorder $iconBox $t.Border
    $row.Controls.Add($iconBox)

    $icon = New-Object System.Windows.Forms.Label
    $icon.Text = [char][int]"0x$Glyph"
    $icon.Font = New-Object System.Drawing.Font("Segoe MDL2 Assets", 11)
    $icon.ForeColor = $t.Accent
    $icon.AutoSize = $true
    $icon.Location = New-Object System.Drawing.Point(8, 8)
    $iconBox.Controls.Add($icon)

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
    $valLbl.Location = New-Object System.Drawing.Point(($Width - 220), 14)
    $valLbl.Size = New-Object System.Drawing.Size(200, 24)
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
        if ($Script:NavIcons.ContainsKey($key)) {
            $Script:NavIcons[$key].ForeColor = if ($isActive) { $t.Accent } else { $t.Muted }
        }
    }
    foreach ($key in $Script:ContentPanels.Keys) {
        $Script:ContentPanels[$key].Visible = ($key -eq $Name)
    }
}

function Set-GuiBusy([bool]$Busy) {
    $Script:GuiBusy = $Busy
    $runBtns = @(
        'BtnWeekly','BtnCleanup','BtnUpdates','BtnRepair','BtnGamingOpt','BtnRefreshDevice',
        'BtnFixPower','BtnApplyGamingDevice','BtnCopyRamTip','BtnRestartNow','BtnOpenStorage',
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

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "PC Maintenance Kit v5.1"
    $form.Size = New-Object System.Drawing.Size(1060, 780)
    $form.StartPosition = "CenterScreen"
    $form.BackColor = $t.Bg
    $form.ForeColor = $t.Text
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $form.MinimumSize = New-Object System.Drawing.Size(980, 720)

    $header = New-Object System.Windows.Forms.Panel
    $header.Location = New-Object System.Drawing.Point(0, 0)
    $header.Size = New-Object System.Drawing.Size(1060, 118)
    $header.BackColor = $t.Header
    $header.Anchor = "Top,Left,Right"
    $form.Controls.Add($header)

    $brandIcon = New-Object System.Windows.Forms.Label
    $brandIcon.Text = [char]0xE90F
    $brandIcon.Font = New-Object System.Drawing.Font("Segoe MDL2 Assets", 16)
    $brandIcon.ForeColor = $t.Accent
    $brandIcon.AutoSize = $true
    $brandIcon.Location = New-Object System.Drawing.Point(22, 16)
    $header.Controls.Add($brandIcon)

    $brand = New-Object System.Windows.Forms.Label
    $brand.Text = "PC Maintenance Kit"
    $brand.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 15)
    $brand.ForeColor = $t.Text
    $brand.AutoSize = $true
    $brand.Location = New-Object System.Drawing.Point(52, 14)
    $header.Controls.Add($brand)

    $ver = New-Object System.Windows.Forms.Label
    $ver.Text = "v5.1  ·  Gamer Toolkit"
    $ver.ForeColor = $t.Accent
    $ver.AutoSize = $true
    $ver.Location = New-Object System.Drawing.Point(54, 42)
    $header.Controls.Add($ver)

    $freeLbl = New-Object System.Windows.Forms.Label
    $freeLbl.Text = "C: free -"
    $freeLbl.ForeColor = $t.Accent
    $freeLbl.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5)
    $freeLbl.AutoSize = $true
    $freeLbl.Location = New-Object System.Drawing.Point(800, 16)
    $freeLbl.Anchor = "Top,Right"
    $header.Controls.Add($freeLbl)

    $rebootBadge = New-Object System.Windows.Forms.Label
    $rebootBadge.Text = "..."
    $rebootBadge.AutoSize = $true
    $rebootBadge.Location = New-Object System.Drawing.Point(800, 40)
    $rebootBadge.Anchor = "Top,Right"
    $header.Controls.Add($rebootBadge)

    $navDefs = @(
        @{ Name = 'Home'; Glyph = 'E80F' }
        @{ Name = 'Cleanup'; Glyph = 'EA99' }
        @{ Name = 'Updates'; Glyph = 'E895' }
        @{ Name = 'Gaming'; Glyph = 'E7FC' }
        @{ Name = 'Repair'; Glyph = 'E90F' }
        @{ Name = 'Device'; Glyph = 'E770' }
    )
    $navX = 24
    foreach ($def in $navDefs) {
        $name = $def.Name
        $wrap = New-Object System.Windows.Forms.Panel
        $wrap.Location = New-Object System.Drawing.Point($navX, 68)
        $wrap.Size = New-Object System.Drawing.Size(108, 44)
        $wrap.BackColor = $t.Header
        $wrap.Cursor = [System.Windows.Forms.Cursors]::Hand
        $wrap.Tag = $name
        $header.Controls.Add($wrap)

        $ico = New-Object System.Windows.Forms.Label
        $ico.Text = [char][int]("0x$($def.Glyph)")
        $ico.Font = New-Object System.Drawing.Font("Segoe MDL2 Assets", 11)
        $ico.ForeColor = $t.Muted
        $ico.AutoSize = $true
        $ico.Location = New-Object System.Drawing.Point(8, 4)
        $ico.Cursor = [System.Windows.Forms.Cursors]::Hand
        $ico.Tag = $name
        $wrap.Controls.Add($ico)

        $nb = New-Object System.Windows.Forms.Button
        $nb.Text = $name
        $nb.Location = New-Object System.Drawing.Point(28, 2)
        $nb.Size = New-Object System.Drawing.Size(78, 36)
        $nb.FlatStyle = "Flat"
        $nb.FlatAppearance.BorderSize = 0
        $nb.BackColor = $t.Header
        $nb.ForeColor = $t.Muted
        $nb.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5)
        $nb.Cursor = [System.Windows.Forms.Cursors]::Hand
        $nb.Tag = "idle"
        $nb.TextAlign = "MiddleLeft"
        $nb.Add_Click({
            param($sender, $e)
            Set-ActiveNav ([string]$sender.Text)
        })
        $nb.Add_Paint({
            param($sender, $e)
            if ($sender.Tag -eq "active") {
                $pen = New-Object System.Drawing.Pen $Script:Theme.Accent, 3
                $y = $sender.Height - 2
                $e.Graphics.DrawLine($pen, 0, $y, ($sender.Width - 4), $y)
                $pen.Dispose()
            }
        })
        $wrap.Controls.Add($nb)

        $navClick = {
            param($sender, $e)
            Set-ActiveNav ([string]$sender.Tag)
        }
        $wrap.Add_Click($navClick)
        $ico.Add_Click($navClick)

        $Script:NavButtons[$name] = $nb
        $Script:NavIcons[$name] = $ico
        $navX += 112
    }

    $hostPanel = New-Object System.Windows.Forms.Panel
    $hostPanel.Location = New-Object System.Drawing.Point(0, 118)
    $hostPanel.Size = New-Object System.Drawing.Size(1060, 360)
    $hostPanel.BackColor = $t.Bg
    $hostPanel.Anchor = "Top,Bottom,Left,Right"
    $form.Controls.Add($hostPanel)

    function New-Content([string]$Name) {
        $p = New-Object System.Windows.Forms.Panel
        $p.Location = New-Object System.Drawing.Point(0, 0)
        $p.Size = New-Object System.Drawing.Size(1060, 360)
        $p.BackColor = $t.Bg
        $p.Visible = $false
        $p.Anchor = "Top,Bottom,Left,Right"
        $hostPanel.Controls.Add($p)
        $Script:ContentPanels[$Name] = $p
        return $p
    }

    # ---- HOME ----
    $pageHome = New-Content "Home"

    $sumTitle = New-Object System.Windows.Forms.Label
    $sumTitle.Text = "System Summary"
    $sumTitle.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 11)
    $sumTitle.ForeColor = $t.Text
    $sumTitle.AutoSize = $true
    $sumTitle.Location = New-Object System.Drawing.Point(24, 12)
    $pageHome.Controls.Add($sumTitle)

    $cpuCard = New-MetricCard (New-Object System.Drawing.Point(24, 42)) (New-Object System.Drawing.Size(560, 78)) "E950" "CPU"
    $gpuCard = New-MetricCard (New-Object System.Drawing.Point(24, 132)) (New-Object System.Drawing.Size(560, 78)) "E7F4" "GPU"
    $ramCard = New-MetricCard (New-Object System.Drawing.Point(24, 222)) (New-Object System.Drawing.Size(560, 78)) "E950" "RAM"
    $cpuCard.Panel.Anchor = "Top,Left"
    $gpuCard.Panel.Anchor = "Top,Left"
    $ramCard.Panel.Anchor = "Top,Left"
    $pageHome.Controls.AddRange(@($cpuCard.Panel, $gpuCard.Panel, $ramCard.Panel))

    $cardOpts = New-CardPanel (New-Object System.Drawing.Point(608, 16)) (New-Object System.Drawing.Size(420, 320)) "Maintenance Options"
    $cardOpts.Anchor = "Top,Right"
    $pageHome.Controls.Add($cardOpts)

    $chkHomeRestore = New-PremiumCheck "Create restore point" (New-Object System.Drawing.Point(20, 48)) $true
    $chkHomeShader = New-PremiumCheck "Clear GPU shader caches" (New-Object System.Drawing.Point(20, 82)) $true
    $chkHomeGaming = New-PremiumCheck "Apply gaming optimizations" (New-Object System.Drawing.Point(20, 116)) $true
    $chkHomeWU = New-PremiumCheck "Windows Update (slow)" (New-Object System.Drawing.Point(20, 150)) $false
    $chkHomeWinget = New-PremiumCheck "winget app upgrades (slow)" (New-Object System.Drawing.Point(20, 184)) $false
    $cardOpts.Controls.AddRange(@($chkHomeRestore, $chkHomeShader, $chkHomeGaming, $chkHomeWU, $chkHomeWinget))

    $btnWeekly = New-PremiumButton "  Run Weekly Full" (New-Object System.Drawing.Point(20, 236)) (New-Object System.Drawing.Size(260, 48)) "Cta"
    $btnRefreshHome = New-PremiumButton "Refresh" (New-Object System.Drawing.Point(292, 236)) (New-Object System.Drawing.Size(104, 48)) "Ghost"
    $cardOpts.Controls.AddRange(@($btnWeekly, $btnRefreshHome))

    $nextLbl = New-Object System.Windows.Forms.Label
    $nextLbl.Text = "Weekly kit · safe defaults (WU/winget off)"
    $nextLbl.ForeColor = $t.Muted
    $nextLbl.Location = New-Object System.Drawing.Point(20, 292)
    $nextLbl.AutoSize = $true
    $cardOpts.Controls.Add($nextLbl)

    # ---- CLEANUP ----
    $pageClean = New-Content "Cleanup"
    $cardClean = New-CardPanel (New-Object System.Drawing.Point(24, 16)) (New-Object System.Drawing.Size(1000, 320)) "Cleanup"
    $cardClean.Anchor = "Top,Bottom,Left,Right"
    $pageClean.Controls.Add($cardClean)

    $cleanHint = New-Object System.Windows.Forms.Label
    $cleanHint.Text = "Safe free-space cleanup. Launcher caches need confirmation and never uninstall games."
    $cleanHint.ForeColor = $t.Muted
    $cleanHint.Location = New-Object System.Drawing.Point(20, 48)
    $cleanHint.Size = New-Object System.Drawing.Size(940, 28)
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

    $btnCleanup = New-PremiumButton "Run Cleanup" (New-Object System.Drawing.Point(760, 250)) (New-Object System.Drawing.Size(200, 44)) "Primary"
    $cardClean.Controls.Add($btnCleanup)

    # ---- UPDATES ----
    $pageUpd = New-Content "Updates"
    $cardUpd = New-CardPanel (New-Object System.Drawing.Point(24, 16)) (New-Object System.Drawing.Size(1000, 320)) "Updates"
    $cardUpd.Anchor = "Top,Bottom,Left,Right"
    $pageUpd.Controls.Add($cardUpd)

    $updHint = New-Object System.Windows.Forms.Label
    $updHint.Text = "Run updates when you are not in a ranked match. Driver apps open separately."
    $updHint.ForeColor = $t.Muted
    $updHint.Location = New-Object System.Drawing.Point(20, 48)
    $updHint.Size = New-Object System.Drawing.Size(940, 28)
    $cardUpd.Controls.Add($updHint)

    $chkUpdRestore = New-PremiumCheck "Create restore point first" (New-Object System.Drawing.Point(20, 96)) $true
    $chkUpdWU = New-PremiumCheck "Windows Update" (New-Object System.Drawing.Point(20, 132)) $true
    $chkUpdWinget = New-PremiumCheck "winget upgrades" (New-Object System.Drawing.Point(20, 168)) $true
    $cardUpd.Controls.AddRange(@($chkUpdRestore, $chkUpdWU, $chkUpdWinget))

    $btnUpdates = New-PremiumButton "Run Updates" (New-Object System.Drawing.Point(20, 240)) (New-Object System.Drawing.Size(180, 44)) "Primary"
    $btnAmd = New-PremiumButton "Open AMD Adrenalin" (New-Object System.Drawing.Point(220, 240)) (New-Object System.Drawing.Size(200, 44)) "Ghost"
    $btnNv = New-PremiumButton "Open NVIDIA App" (New-Object System.Drawing.Point(440, 240)) (New-Object System.Drawing.Size(180, 44)) "Ghost"
    $cardUpd.Controls.AddRange(@($btnUpdates, $btnAmd, $btnNv))

    # ---- GAMING ----
    $pageGame = New-Content "Gaming"
    $cardGameStatus = New-CardPanel (New-Object System.Drawing.Point(24, 16)) (New-Object System.Drawing.Size(620, 320)) "Gaming Status"
    $cardGameStatus.Anchor = "Top,Bottom,Left"
    $pageGame.Controls.Add($cardGameStatus)

    $rowGm = New-GameStatusRow (New-Object System.Drawing.Point(12, 48)) 590 "E7FC" "Game Mode"
    $rowDvr = New-GameStatusRow (New-Object System.Drawing.Point(12, 100)) 590 "E7FC" "Xbox Game DVR"
    $rowRelive = New-GameStatusRow (New-Object System.Drawing.Point(12, 152)) 590 "E7F4" "AMD ReLive"
    $rowPower = New-GameStatusRow (New-Object System.Drawing.Point(12, 204)) 590 "E945" "Power Plan"
    $rowDiscord = New-GameStatusRow (New-Object System.Drawing.Point(12, 256)) 590 "E8BD" "Discord HW accel"
    $cardGameStatus.Controls.AddRange(@($rowGm.Panel, $rowDvr.Panel, $rowRelive.Panel, $rowPower.Panel, $rowDiscord.Panel))

    $cardGameActions = New-CardPanel (New-Object System.Drawing.Point(668, 16)) (New-Object System.Drawing.Size(360, 320)) "Actions"
    $cardGameActions.Anchor = "Top,Right"
    $pageGame.Controls.Add($cardGameActions)

    $btnGamingOpt = New-PremiumButton "Apply gaming optimize" (New-Object System.Drawing.Point(24, 60)) (New-Object System.Drawing.Size(310, 52)) "Primary"
    $btnDiscordOff = New-PremiumButton "Discord HW accel OFF" (New-Object System.Drawing.Point(24, 128)) (New-Object System.Drawing.Size(310, 52)) "Ghost"
    $btnRefreshGame = New-PremiumButton "Refresh status" (New-Object System.Drawing.Point(24, 196)) (New-Object System.Drawing.Size(310, 52)) "Ghost"
    $cardGameActions.Controls.AddRange(@($btnGamingOpt, $btnDiscordOff, $btnRefreshGame))

    $gameTip = New-Object System.Windows.Forms.Label
    $gameTip.Text = "Tip: Fullscreen + FPS near refresh rate usually beats uncapped FPS."
    $gameTip.ForeColor = $t.Muted
    $gameTip.Location = New-Object System.Drawing.Point(24, 270)
    $gameTip.Size = New-Object System.Drawing.Size(310, 36)
    $cardGameActions.Controls.Add($gameTip)

    # ---- REPAIR ----
    $pageRepair = New-Content "Repair"
    $cardRepair = New-CardPanel (New-Object System.Drawing.Point(24, 16)) (New-Object System.Drawing.Size(1000, 320)) "Repair"
    $cardRepair.Anchor = "Top,Bottom,Left,Right"
    $pageRepair.Controls.Add($cardRepair)

    $repHint = New-Object System.Windows.Forms.Label
    $repHint.Text = "Only when Windows feels broken. DISM + SFC can take 10-30+ minutes."
    $repHint.ForeColor = $t.Muted
    $repHint.Location = New-Object System.Drawing.Point(20, 52)
    $repHint.Size = New-Object System.Drawing.Size(940, 28)
    $cardRepair.Controls.Add($repHint)

    $chkRepRestore = New-PremiumCheck "Create restore point first" (New-Object System.Drawing.Point(20, 100)) $true
    $cardRepair.Controls.Add($chkRepRestore)

    $btnRepair = New-PremiumButton "Run DISM + SFC" (New-Object System.Drawing.Point(20, 160)) (New-Object System.Drawing.Size(200, 48)) "Danger"
    $btnRestoreOnly = New-PremiumButton "Restore point only" (New-Object System.Drawing.Point(240, 160)) (New-Object System.Drawing.Size(200, 48)) "Ghost"
    $cardRepair.Controls.AddRange(@($btnRepair, $btnRestoreOnly))

    # ---- DEVICE ----
    $pageDev = New-Content "Device"
    $cardDev = New-CardPanel (New-Object System.Drawing.Point(24, 16)) (New-Object System.Drawing.Size(620, 320)) "Device"
    $cardDev.Anchor = "Top,Bottom,Left"
    $pageDev.Controls.Add($cardDev)

    $deviceSummary = New-Object System.Windows.Forms.TextBox
    $deviceSummary.Multiline = $true
    $deviceSummary.ReadOnly = $true
    $deviceSummary.ScrollBars = "Vertical"
    $deviceSummary.BorderStyle = "None"
    $deviceSummary.BackColor = $t.Panel
    $deviceSummary.ForeColor = $t.Text
    $deviceSummary.Font = New-Object System.Drawing.Font("Consolas", 9.5)
    $deviceSummary.Location = New-Object System.Drawing.Point(16, 48)
    $deviceSummary.Size = New-Object System.Drawing.Size(588, 250)
    $cardDev.Controls.Add($deviceSummary)

    $cardDevAct = New-CardPanel (New-Object System.Drawing.Point(668, 16)) (New-Object System.Drawing.Size(360, 320)) "Quick Actions"
    $cardDevAct.Anchor = "Top,Right"
    $pageDev.Controls.Add($cardDevAct)

    $btnRefreshDevice = New-PremiumButton "Refresh" (New-Object System.Drawing.Point(24, 52)) (New-Object System.Drawing.Size(310, 36)) "Ghost"
    $btnFixPower = New-PremiumButton "Fix power plan (Ultimate)" (New-Object System.Drawing.Point(24, 98)) (New-Object System.Drawing.Size(310, 36)) "Muted"
    $btnApplyGamingDevice = New-PremiumButton "Apply gaming optimize" (New-Object System.Drawing.Point(24, 144)) (New-Object System.Drawing.Size(310, 36)) "Primary"
    $btnCopyRamTip = New-PremiumButton "Copy RAM upgrade tip" (New-Object System.Drawing.Point(24, 190)) (New-Object System.Drawing.Size(310, 36)) "Ghost"
    $btnOpenStorage = New-PremiumButton "Open Storage settings" (New-Object System.Drawing.Point(24, 236)) (New-Object System.Drawing.Size(310, 36)) "Muted"
    $btnRestartNow = New-PremiumButton "Restart PC now" (New-Object System.Drawing.Point(24, 282)) (New-Object System.Drawing.Size(310, 36)) "Danger"
    $cardDevAct.Controls.AddRange(@($btnRefreshDevice, $btnFixPower, $btnApplyGamingDevice, $btnCopyRamTip, $btnOpenStorage, $btnRestartNow))

    # ---- LOG FOOTER ----
    $logCard = New-Object System.Windows.Forms.Panel
    $logCard.Location = New-Object System.Drawing.Point(24, 490)
    $logCard.Size = New-Object System.Drawing.Size(1000, 180)
    $logCard.BackColor = $t.Panel
    $logCard.Anchor = "Bottom,Left,Right"
    Add-PanelBorder $logCard $t.Accent
    $form.Controls.Add($logCard)

    $logTitle = New-Object System.Windows.Forms.Label
    $logTitle.Text = "Maintenance Log"
    $logTitle.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
    $logTitle.ForeColor = $t.Accent
    $logTitle.AutoSize = $true
    $logTitle.Location = New-Object System.Drawing.Point(16, 10)
    $logCard.Controls.Add($logTitle)

    $btnClearLog = New-Object System.Windows.Forms.LinkLabel
    $btnClearLog.Text = "Clear log"
    $btnClearLog.LinkColor = $t.Accent
    $btnClearLog.ActiveLinkColor = $t.Text
    $btnClearLog.Location = New-Object System.Drawing.Point(900, 12)
    $btnClearLog.AutoSize = $true
    $btnClearLog.Anchor = "Top,Right"
    $logCard.Controls.Add($btnClearLog)

    $log = New-Object System.Windows.Forms.RichTextBox
    $log.Location = New-Object System.Drawing.Point(16, 36)
    $log.Size = New-Object System.Drawing.Size(968, 80)
    $log.BackColor = $t.LogBg
    $log.ForeColor = $t.Accent
    $log.Font = New-Object System.Drawing.Font("Consolas", 9)
    $log.ReadOnly = $true
    $log.BorderStyle = "None"
    $log.Anchor = "Top,Bottom,Left,Right"
    $logCard.Controls.Add($log)

    $progressTrack = New-Object System.Windows.Forms.Panel
    $progressTrack.Location = New-Object System.Drawing.Point(16, 128)
    $progressTrack.Size = New-Object System.Drawing.Size(700, 12)
    $progressTrack.BackColor = $t.IconBox
    $progressTrack.Anchor = "Bottom,Left,Right"
    $logCard.Controls.Add($progressTrack)

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
    $logCard.Controls.Add($progress)

    $progLbl = New-Object System.Windows.Forms.Label
    $progLbl.Text = "Overall Progress"
    $progLbl.ForeColor = $t.Muted
    $progLbl.Location = New-Object System.Drawing.Point(16, 146)
    $progLbl.AutoSize = $true
    $progLbl.Anchor = "Bottom,Left"
    $logCard.Controls.Add($progLbl)

    $status = New-Object System.Windows.Forms.Label
    $status.Text = "Ready"
    $status.ForeColor = $t.Muted
    $status.Location = New-Object System.Drawing.Point(150, 146)
    $status.Size = New-Object System.Drawing.Size(400, 18)
    $status.Anchor = "Bottom,Left"
    $logCard.Controls.Add($status)

    $statusBar = New-Object System.Windows.Forms.Label
    $statusBar.Text = "Ready"
    $statusBar.ForeColor = $t.Muted
    $statusBar.Location = New-Object System.Drawing.Point(560, 146)
    $statusBar.Size = New-Object System.Drawing.Size(160, 18)
    $statusBar.Anchor = "Bottom,Left,Right"
    $logCard.Controls.Add($statusBar)

    $btnLogs = New-PremiumButton "View Full Log" (New-Object System.Drawing.Point(740, 128)) (New-Object System.Drawing.Size(120, 32)) "Muted"
    $btnCli = New-PremiumButton "CLI" (New-Object System.Drawing.Point(870, 128)) (New-Object System.Drawing.Size(54, 32)) "Muted"
    $btnQuit = New-PremiumButton "Quit" (New-Object System.Drawing.Point(934, 128)) (New-Object System.Drawing.Size(50, 32)) "Danger"
    $btnLogs.Anchor = "Bottom,Right"
    $btnCli.Anchor = "Bottom,Right"
    $btnQuit.Anchor = "Bottom,Right"
    $logCard.Controls.AddRange(@($btnLogs, $btnCli, $btnQuit))

    $Script:GuiControls = [pscustomobject]@{
        Form            = $form
        Free            = $freeLbl
        RebootBadge     = $rebootBadge
        StatusBar       = $statusBar
        CpuMain         = $cpuCard.Main
        CpuStat         = $cpuCard.Stat
        GpuMain         = $gpuCard.Main
        GpuStat          = $gpuCard.Stat
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
        BtnApplyGamingDevice = $btnApplyGamingDevice
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

    $btnApplyGamingDevice.Add_Click({
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
            Update-GuiDevicePanel
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
