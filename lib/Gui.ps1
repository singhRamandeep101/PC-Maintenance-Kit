$Script:GuiBusy = $false

function New-DarkButton {
    param(
        [string]$Text,
        [System.Drawing.Point]$Location,
        [System.Drawing.Size]$Size,
        [System.Drawing.Color]$BackColor
    )
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text
    $b.Location = $Location
    $b.Size = $Size
    $b.FlatStyle = "Flat"
    $b.BackColor = $BackColor
    $b.ForeColor = [System.Drawing.Color]::White
    $b.FlatAppearance.BorderSize = 0
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    return $b
}

function New-DarkCheck {
    param([string]$Text, [System.Drawing.Point]$Location, [bool]$Checked = $true)
    $c = New-Object System.Windows.Forms.CheckBox
    $c.Text = $Text
    $c.Location = $Location
    $c.AutoSize = $true
    $c.Checked = $Checked
    $c.ForeColor = [System.Drawing.Color]::FromArgb(230, 234, 238)
    return $c
}

function Set-GuiBusy([bool]$Busy) {
    $Script:GuiBusy = $Busy
    $form = Get-UiControl Form
    if (-not $form) { return }
    foreach ($ctrl in $form.Controls) {
        if ($ctrl -is [System.Windows.Forms.TabControl]) {
            $ctrl.Enabled = -not $Busy
        }
    }
    $runBtns = @('BtnWeekly','BtnCleanup','BtnUpdates','BtnRepair','BtnGamingOpt','BtnRefreshDevice')
    foreach ($n in $runBtns) {
        $b = $Script:GuiControls.$n
        if ($b) { $b.Enabled = -not $Busy }
    }
}

function Invoke-GuiAction {
    param([scriptblock]$Action, [string]$Title = "Working")
    if ($Script:GuiBusy) { return }
    Set-GuiBusy $true
    Set-UiProgressValue 0
    Set-UiStatusText $Title
    try {
        & $Action
        Update-GuiHomeSummary
        Update-GuiDevicePanel
        Set-UiStatusText ("Done - {0}" -f (Get-Elapsed))
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
    $box = $Script:GuiControls.HomeSummary
    if (-not $box) { return }
    try {
        $box.Text = Format-DeviceSummaryText
    } catch {
        $box.Text = "Could not read device summary."
    }
    try {
        $Script:GuiControls.Free.Text = ("C: free {0} GB" -f (Get-CFreeGB))
    } catch { }
    $badge = $Script:GuiControls.RebootBadge
    if ($badge) {
        if (Test-RebootPending) {
            $badge.Text = "Restart pending"
            $badge.ForeColor = [System.Drawing.Color]::FromArgb(230, 180, 60)
        } else {
            $badge.Text = "No restart pending"
            $badge.ForeColor = [System.Drawing.Color]::FromArgb(80, 200, 120)
        }
    }
}

function Update-GuiDevicePanel {
    $box = $Script:GuiControls.DeviceSummary
    if (-not $box) { return }
    try { $box.Text = Format-DeviceSummaryText } catch { $box.Text = "Unavailable" }
}

function Update-GuiGamingStatus {
    $box = $Script:GuiControls.GamingStatus
    if (-not $box) { return }
    $gm = Get-GameModeEnabled
    $dvr = Get-GameDvrEnabled
    $relive = Get-AmdReLiveEnabled
    $power = Get-ActivePowerPlanName
    $discord = Get-DiscordHardwareAcceleration
    $lines = @(
        ("Game Mode:     {0}" -f $(if ($null -eq $gm) { "Unknown" } elseif ($gm -eq 1) { "On" } else { "Off" }))
        ("Xbox Game DVR: {0}" -f $(if ($null -eq $dvr) { "Unknown" } elseif ($dvr -eq 0) { "Off" } else { "On" }))
        ("AMD ReLive:    {0}" -f $(if ($null -eq $relive) { "N/A" } elseif ($relive -eq 0) { "Off" } else { "On" }))
        ("Power plan:    {0}" -f $power)
        ("Discord HW accel: {0}" -f $(if ($null -eq $discord) { "Discord not found" } elseif ($discord) { "On (can cause hitching)" } else { "Off" }))
    )
    $box.Text = $lines -join "`r`n"
}

function Show-MaintenanceGui {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    $bg      = [System.Drawing.Color]::FromArgb(18, 22, 28)
    $panel   = [System.Drawing.Color]::FromArgb(28, 34, 42)
    $accent  = [System.Drawing.Color]::FromArgb(46, 160, 120)
    $accent2 = [System.Drawing.Color]::FromArgb(56, 120, 180)
    $warn    = [System.Drawing.Color]::FromArgb(180, 90, 50)
    $text    = [System.Drawing.Color]::FromArgb(230, 234, 238)
    $muted   = [System.Drawing.Color]::FromArgb(150, 160, 170)
    $btnBg   = [System.Drawing.Color]::FromArgb(42, 50, 60)

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "PC Maintenance Kit v5 - Gamer Toolkit"
    $form.Size = New-Object System.Drawing.Size(980, 720)
    $form.StartPosition = "CenterScreen"
    $form.BackColor = $bg
    $form.ForeColor = $text
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $form.MinimumSize = New-Object System.Drawing.Size(900, 640)

    $title = New-Object System.Windows.Forms.Label
    $title.Text = "PC Maintenance Kit"
    $title.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 16)
    $title.ForeColor = $text
    $title.AutoSize = $true
    $title.Location = New-Object System.Drawing.Point(20, 14)
    $form.Controls.Add($title)

    $sub = New-Object System.Windows.Forms.Label
    $sub.Text = "Gamer toolkit - cleanup, updates, gaming tweaks, repair"
    $sub.ForeColor = $muted
    $sub.AutoSize = $true
    $sub.Location = New-Object System.Drawing.Point(22, 44)
    $form.Controls.Add($sub)

    $freeLbl = New-Object System.Windows.Forms.Label
    $freeLbl.Text = "C: free -"
    $freeLbl.ForeColor = $accent
    $freeLbl.AutoSize = $true
    $freeLbl.Location = New-Object System.Drawing.Point(720, 18)
    $freeLbl.Anchor = "Top,Right"
    $form.Controls.Add($freeLbl)

    $rebootBadge = New-Object System.Windows.Forms.Label
    $rebootBadge.Text = "..."
    $rebootBadge.AutoSize = $true
    $rebootBadge.Location = New-Object System.Drawing.Point(720, 42)
    $rebootBadge.Anchor = "Top,Right"
    $form.Controls.Add($rebootBadge)

    $tabs = New-Object System.Windows.Forms.TabControl
    $tabs.Location = New-Object System.Drawing.Point(20, 72)
    $tabs.Size = New-Object System.Drawing.Size(920, 360)
    $tabs.Anchor = "Top,Bottom,Left,Right"
    $tabs.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5)
    $form.Controls.Add($tabs)

    function Add-Tab([string]$Name) {
        $tp = New-Object System.Windows.Forms.TabPage
        $tp.Text = $Name
        $tp.BackColor = $panel
        $tp.ForeColor = $text
        $tp.Padding = New-Object System.Windows.Forms.Padding(12)
        [void]$tabs.TabPages.Add($tp)
        return $tp
    }

    # ---- Home ----
    $tabHome = Add-Tab "Home"
    $homeIntro = New-Object System.Windows.Forms.Label
    $homeIntro.Text = "Weekly maintenance for gaming PCs. Defaults skip Windows Update / winget for speed and safety."
    $homeIntro.ForeColor = $muted
    $homeIntro.Location = New-Object System.Drawing.Point(16, 16)
    $homeIntro.Size = New-Object System.Drawing.Size(860, 36)
    $tabHome.Controls.Add($homeIntro)

    $homeSummary = New-Object System.Windows.Forms.TextBox
    $homeSummary.Multiline = $true
    $homeSummary.ReadOnly = $true
    $homeSummary.ScrollBars = "Vertical"
    $homeSummary.BackColor = [System.Drawing.Color]::FromArgb(14, 16, 20)
    $homeSummary.ForeColor = $text
    $homeSummary.BorderStyle = "FixedSingle"
    $homeSummary.Font = New-Object System.Drawing.Font("Consolas", 9)
    $homeSummary.Location = New-Object System.Drawing.Point(16, 56)
    $homeSummary.Size = New-Object System.Drawing.Size(560, 200)
    $tabHome.Controls.Add($homeSummary)

    $chkHomeRestore = New-DarkCheck "Create restore point" (New-Object System.Drawing.Point(600, 56)) $true
    $chkHomeShader = New-DarkCheck "Clear GPU shader caches" (New-Object System.Drawing.Point(600, 88)) $true
    $chkHomeGaming = New-DarkCheck "Apply gaming optimizations" (New-Object System.Drawing.Point(600, 120)) $true
    $chkHomeWU = New-DarkCheck "Windows Update (slow)" (New-Object System.Drawing.Point(600, 152)) $false
    $chkHomeWinget = New-DarkCheck "winget app upgrades (slow)" (New-Object System.Drawing.Point(600, 184)) $false
    $tabHome.Controls.AddRange(@($chkHomeRestore, $chkHomeShader, $chkHomeGaming, $chkHomeWU, $chkHomeWinget))

    $btnWeekly = New-DarkButton "Run Weekly Full" (New-Object System.Drawing.Point(600, 230)) (New-Object System.Drawing.Size(200, 40)) $accent
    $btnRefreshHome = New-DarkButton "Refresh" (New-Object System.Drawing.Point(816, 230)) (New-Object System.Drawing.Size(80, 40)) $btnBg
    $tabHome.Controls.AddRange(@($btnWeekly, $btnRefreshHome))

    # ---- Cleanup ----
    $tabClean = Add-Tab "Cleanup"
    $cleanIntro = New-Object System.Windows.Forms.Label
    $cleanIntro.Text = "Safe cleanup. Launcher caches need confirmation - they only remove download leftovers, not games."
    $cleanIntro.ForeColor = $muted
    $cleanIntro.Location = New-Object System.Drawing.Point(16, 16)
    $cleanIntro.Size = New-Object System.Drawing.Size(860, 36)
    $tabClean.Controls.Add($cleanIntro)

    $daysLbl = New-Object System.Windows.Forms.Label
    $daysLbl.Text = "Temp older than (days)"
    $daysLbl.ForeColor = $text
    $daysLbl.Location = New-Object System.Drawing.Point(16, 60)
    $daysLbl.AutoSize = $true
    $tabClean.Controls.Add($daysLbl)

    $daysNum = New-Object System.Windows.Forms.NumericUpDown
    $daysNum.Minimum = 0
    $daysNum.Maximum = 30
    $daysNum.Value = 2
    $daysNum.Location = New-Object System.Drawing.Point(180, 58)
    $daysNum.Width = 70
    $daysNum.BackColor = $btnBg
    $daysNum.ForeColor = $text
    $tabClean.Controls.Add($daysNum)

    $chkCleanShader = New-DarkCheck "GPU shader caches" (New-Object System.Drawing.Point(16, 100)) $true
    $chkSteam = New-DarkCheck "Steam downloading cache" (New-Object System.Drawing.Point(16, 132)) $false
    $chkEpic = New-DarkCheck "Epic launcher cache/logs" (New-Object System.Drawing.Point(16, 164)) $false
    $chkRiot = New-DarkCheck "Riot Client cache/logs" (New-Object System.Drawing.Point(16, 196)) $false
    $tabClean.Controls.AddRange(@($chkCleanShader, $chkSteam, $chkEpic, $chkRiot))

    $btnCleanup = New-DarkButton "Run Cleanup" (New-Object System.Drawing.Point(16, 250)) (New-Object System.Drawing.Size(180, 40)) $accent
    $tabClean.Controls.Add($btnCleanup)

    # ---- Updates ----
    $tabUpd = Add-Tab "Updates"
    $updIntro = New-Object System.Windows.Forms.Label
    $updIntro.Text = "Optional updates. Prefer running these when you are not mid-ranked game."
    $updIntro.ForeColor = $muted
    $updIntro.Location = New-Object System.Drawing.Point(16, 16)
    $updIntro.Size = New-Object System.Drawing.Size(860, 36)
    $tabUpd.Controls.Add($updIntro)

    $chkUpdRestore = New-DarkCheck "Create restore point first" (New-Object System.Drawing.Point(16, 60)) $true
    $chkUpdWU = New-DarkCheck "Windows Update" (New-Object System.Drawing.Point(16, 92)) $true
    $chkUpdWinget = New-DarkCheck "winget upgrades" (New-Object System.Drawing.Point(16, 124)) $true
    $tabUpd.Controls.AddRange(@($chkUpdRestore, $chkUpdWU, $chkUpdWinget))

    $btnUpdates = New-DarkButton "Run Updates" (New-Object System.Drawing.Point(16, 180)) (New-Object System.Drawing.Size(160, 40)) $accent2
    $btnAmd = New-DarkButton "Open AMD Adrenalin" (New-Object System.Drawing.Point(196, 180)) (New-Object System.Drawing.Size(180, 40)) $btnBg
    $btnNv = New-DarkButton "Open NVIDIA App" (New-Object System.Drawing.Point(396, 180)) (New-Object System.Drawing.Size(160, 40)) $btnBg
    $tabUpd.Controls.AddRange(@($btnUpdates, $btnAmd, $btnNv))

    # ---- Gaming ----
    $tabGame = Add-Tab "Gaming"
    $gameIntro = New-Object System.Windows.Forms.Label
    $gameIntro.Text = "Low-latency gaming defaults. Discord HW accel off can reduce hitching with overlays closed."
    $gameIntro.ForeColor = $muted
    $gameIntro.Location = New-Object System.Drawing.Point(16, 16)
    $gameIntro.Size = New-Object System.Drawing.Size(860, 36)
    $tabGame.Controls.Add($gameIntro)

    $gamingStatus = New-Object System.Windows.Forms.TextBox
    $gamingStatus.Multiline = $true
    $gamingStatus.ReadOnly = $true
    $gamingStatus.BackColor = [System.Drawing.Color]::FromArgb(14, 16, 20)
    $gamingStatus.ForeColor = $text
    $gamingStatus.BorderStyle = "FixedSingle"
    $gamingStatus.Font = New-Object System.Drawing.Font("Consolas", 9)
    $gamingStatus.Location = New-Object System.Drawing.Point(16, 56)
    $gamingStatus.Size = New-Object System.Drawing.Size(560, 160)
    $tabGame.Controls.Add($gamingStatus)

    $btnGamingOpt = New-DarkButton "Apply gaming optimize" (New-Object System.Drawing.Point(600, 56)) (New-Object System.Drawing.Size(220, 40)) $accent
    $btnDiscordOff = New-DarkButton "Discord HW accel OFF" (New-Object System.Drawing.Point(600, 110)) (New-Object System.Drawing.Size(220, 40)) $btnBg
    $btnRefreshGame = New-DarkButton "Refresh status" (New-Object System.Drawing.Point(600, 164)) (New-Object System.Drawing.Size(220, 40)) $btnBg
    $tabGame.Controls.AddRange(@($btnGamingOpt, $btnDiscordOff, $btnRefreshGame))

    $gameTip = New-Object System.Windows.Forms.Label
    $gameTip.Text = "Tip: Fullscreen + FPS cap near refresh rate usually beats uncapped FPS for microstutter."
    $gameTip.ForeColor = $muted
    $gameTip.Location = New-Object System.Drawing.Point(16, 240)
    $gameTip.Size = New-Object System.Drawing.Size(860, 40)
    $tabGame.Controls.Add($gameTip)

    # ---- Repair ----
    $tabRepair = Add-Tab "Repair"
    $repIntro = New-Object System.Windows.Forms.Label
    $repIntro.Text = "Only when Windows feels broken. DISM + SFC can take 10-30+ minutes."
    $repIntro.ForeColor = $muted
    $repIntro.Location = New-Object System.Drawing.Point(16, 16)
    $repIntro.Size = New-Object System.Drawing.Size(860, 36)
    $tabRepair.Controls.Add($repIntro)

    $chkRepRestore = New-DarkCheck "Create restore point first" (New-Object System.Drawing.Point(16, 60)) $true
    $tabRepair.Controls.Add($chkRepRestore)

    $btnRepair = New-DarkButton "Run DISM + SFC" (New-Object System.Drawing.Point(16, 110)) (New-Object System.Drawing.Size(180, 40)) $warn
    $btnRestoreOnly = New-DarkButton "Restore point only" (New-Object System.Drawing.Point(216, 110)) (New-Object System.Drawing.Size(180, 40)) $btnBg
    $tabRepair.Controls.AddRange(@($btnRepair, $btnRestoreOnly))

    # ---- Device ----
    $tabDev = Add-Tab "Device"
    $devIntro = New-Object System.Windows.Forms.Label
    $devIntro.Text = "Hardware snapshot. Single-channel RAM is a common cause of gaming microstutter."
    $devIntro.ForeColor = $muted
    $devIntro.Location = New-Object System.Drawing.Point(16, 16)
    $devIntro.Size = New-Object System.Drawing.Size(860, 36)
    $tabDev.Controls.Add($devIntro)

    $deviceSummary = New-Object System.Windows.Forms.TextBox
    $deviceSummary.Multiline = $true
    $deviceSummary.ReadOnly = $true
    $deviceSummary.ScrollBars = "Vertical"
    $deviceSummary.BackColor = [System.Drawing.Color]::FromArgb(14, 16, 20)
    $deviceSummary.ForeColor = $text
    $deviceSummary.BorderStyle = "FixedSingle"
    $deviceSummary.Font = New-Object System.Drawing.Font("Consolas", 9)
    $deviceSummary.Location = New-Object System.Drawing.Point(16, 56)
    $deviceSummary.Size = New-Object System.Drawing.Size(700, 220)
    $deviceSummary.Anchor = "Top,Bottom,Left,Right"
    $tabDev.Controls.Add($deviceSummary)

    $btnRefreshDevice = New-DarkButton "Refresh" (New-Object System.Drawing.Point(740, 56)) (New-Object System.Drawing.Size(140, 40)) $accent2
    $tabDev.Controls.Add($btnRefreshDevice)

    # ---- Shared log / progress ----
    $progress = New-Object System.Windows.Forms.ProgressBar
    $progress.Location = New-Object System.Drawing.Point(20, 444)
    $progress.Size = New-Object System.Drawing.Size(920, 18)
    $progress.Anchor = "Bottom,Left,Right"
    $form.Controls.Add($progress)

    $status = New-Object System.Windows.Forms.Label
    $status.Text = "Ready"
    $status.ForeColor = $muted
    $status.Location = New-Object System.Drawing.Point(20, 468)
    $status.AutoSize = $true
    $status.Anchor = "Bottom,Left"
    $form.Controls.Add($status)

    $log = New-Object System.Windows.Forms.RichTextBox
    $log.Location = New-Object System.Drawing.Point(20, 492)
    $log.Size = New-Object System.Drawing.Size(920, 120)
    $log.BackColor = [System.Drawing.Color]::FromArgb(12, 14, 18)
    $log.ForeColor = $text
    $log.Font = New-Object System.Drawing.Font("Consolas", 9)
    $log.ReadOnly = $true
    $log.BorderStyle = "FixedSingle"
    $log.Anchor = "Bottom,Left,Right"
    $form.Controls.Add($log)

    $btnLogs = New-DarkButton "Open logs" (New-Object System.Drawing.Point(20, 628)) (New-Object System.Drawing.Size(120, 36)) $accent2
    $btnCli = New-DarkButton "CLI" (New-Object System.Drawing.Point(156, 628)) (New-Object System.Drawing.Size(90, 36)) $btnBg
    $btnQuit = New-DarkButton "Quit" (New-Object System.Drawing.Point(820, 628)) (New-Object System.Drawing.Size(120, 36)) ([System.Drawing.Color]::FromArgb(90, 50, 50))
    $btnLogs.Anchor = "Bottom,Left"
    $btnCli.Anchor = "Bottom,Left"
    $btnQuit.Anchor = "Bottom,Right"
    $form.Controls.AddRange(@($btnLogs, $btnCli, $btnQuit))

    $Script:GuiControls = [pscustomobject]@{
        Form            = $form
        Free            = $freeLbl
        RebootBadge     = $rebootBadge
        HomeSummary     = $homeSummary
        DeviceSummary   = $deviceSummary
        GamingStatus    = $gamingStatus
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
    }

    $Script:Ui = [pscustomobject]@{
        Form     = $form
        Progress = $progress
        Status   = $status
        Log      = $log
        Free     = $freeLbl
    }

    Update-GuiHomeSummary
    Update-GuiDevicePanel
    Update-GuiGamingStatus

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

    $btnRefreshHome.Add_Click({ Update-GuiHomeSummary; Update-GuiGamingStatus })

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

    $btnRefreshGame.Add_Click({ Update-GuiGamingStatus })

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
        Invoke-GuiAction -Title "Device report" -Action {
            Init-Log
            $Script:Report.Clear()
            $Script:TotalSteps = 1
            $Script:CurrentStep = 0
            Invoke-DeviceHealthReport
        }
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
    Write-Host "     PC MAINTENANCE KIT v5 (Gamer)"
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
