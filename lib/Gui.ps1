#Requires -Version 5.1

$Script:GuiControls = $null

function Get-GuiSelectedMode {
    foreach ($c in $Script:GuiControls.ModeBox.Controls) {
        if ($c -is [System.Windows.Forms.RadioButton] -and $c.Checked) {
            return [string]$c.Tag
        }
    }
    return "Full"
}

function Set-GuiRunningState([bool]$running) {
    $enabled = -not $running
    $Script:GuiControls.BtnRun.Enabled = $enabled
    $Script:GuiControls.BtnCli.Enabled = $enabled
    $Script:GuiControls.ModeBox.Enabled = $enabled
    $Script:GuiControls.OptBox.Enabled = $enabled
}

function Update-GuiFreeSpace {
    try {
        $Script:GuiControls.Free.Text = ("C: free {0} GB" -f (Get-CFreeGB))
    } catch {
        $Script:GuiControls.Free.Text = "C: free -"
    }
}

function Show-MaintenanceGui {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    $bg      = [System.Drawing.Color]::FromArgb(22, 26, 32)
    $panel   = [System.Drawing.Color]::FromArgb(32, 38, 46)
    $accent  = [System.Drawing.Color]::FromArgb(46, 160, 120)
    $accent2 = [System.Drawing.Color]::FromArgb(56, 120, 180)
    $text    = [System.Drawing.Color]::FromArgb(230, 234, 238)
    $muted   = [System.Drawing.Color]::FromArgb(150, 160, 170)
    $btnBg   = [System.Drawing.Color]::FromArgb(42, 50, 60)

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "PC Maintenance v4"
    $form.Size = New-Object System.Drawing.Size(860, 640)
    $form.StartPosition = "CenterScreen"
    $form.BackColor = $bg
    $form.ForeColor = $text
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $form.MinimumSize = New-Object System.Drawing.Size(780, 560)

    $title = New-Object System.Windows.Forms.Label
    $title.Text = "PC Maintenance"
    $title.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 18)
    $title.ForeColor = $text
    $title.AutoSize = $true
    $title.Location = New-Object System.Drawing.Point(24, 18)
    $form.Controls.Add($title)

    $sub = New-Object System.Windows.Forms.Label
    $sub.Text = "Cleanup / Updates / Health checks / Optional repair"
    $sub.ForeColor = $muted
    $sub.AutoSize = $true
    $sub.Location = New-Object System.Drawing.Point(26, 52)
    $form.Controls.Add($sub)

    $freeLbl = New-Object System.Windows.Forms.Label
    $freeLbl.Text = "C: free -"
    $freeLbl.ForeColor = $accent
    $freeLbl.AutoSize = $true
    $freeLbl.Location = New-Object System.Drawing.Point(620, 28)
    $freeLbl.Anchor = "Top,Right"
    $form.Controls.Add($freeLbl)

    $modeBox = New-Object System.Windows.Forms.GroupBox
    $modeBox.Text = "Mode"
    $modeBox.ForeColor = $muted
    $modeBox.BackColor = $panel
    $modeBox.Location = New-Object System.Drawing.Point(24, 88)
    $modeBox.Size = New-Object System.Drawing.Size(390, 210)
    $form.Controls.Add($modeBox)

    $modeDefs = @(
        @{ Text = "Full run (weekly)";    Tag = "Full" },
        @{ Text = "Cleanup only";         Tag = "CleanupOnly" },
        @{ Text = "Updates only";         Tag = "UpdatesOnly" },
        @{ Text = "Repair (DISM + SFC)";  Tag = "Repair" },
        @{ Text = "Full + Repair";        Tag = "FullRepair" }
    )
    $y = 28
    foreach ($m in $modeDefs) {
        $rb = New-Object System.Windows.Forms.RadioButton
        $rb.Text = $m.Text
        $rb.Tag = $m.Tag
        $rb.ForeColor = $text
        $rb.Location = New-Object System.Drawing.Point(18, $y)
        $rb.AutoSize = $true
        if ($m.Tag -eq "Full") { $rb.Checked = $true }
        $modeBox.Controls.Add($rb)
        $y += 32
    }

    $optBox = New-Object System.Windows.Forms.GroupBox
    $optBox.Text = "Options"
    $optBox.ForeColor = $muted
    $optBox.BackColor = $panel
    $optBox.Location = New-Object System.Drawing.Point(430, 88)
    $optBox.Size = New-Object System.Drawing.Size(390, 210)
    $optBox.Anchor = "Top,Right"
    $form.Controls.Add($optBox)

    $chkRestore = New-Object System.Windows.Forms.CheckBox
    $chkRestore.Text = "Create restore point"
    $chkRestore.Checked = $true
    $chkRestore.ForeColor = $text
    $chkRestore.Location = New-Object System.Drawing.Point(18, 36)
    $chkRestore.AutoSize = $true
    $optBox.Controls.Add($chkRestore)

    $chkAmd = New-Object System.Windows.Forms.CheckBox
    $chkAmd.Text = "Open AMD Adrenalin"
    $chkAmd.Checked = $true
    $chkAmd.ForeColor = $text
    $chkAmd.Location = New-Object System.Drawing.Point(18, 72)
    $chkAmd.AutoSize = $true
    $optBox.Controls.Add($chkAmd)

    $daysLbl = New-Object System.Windows.Forms.Label
    $daysLbl.Text = "Delete temp files older than (days)"
    $daysLbl.ForeColor = $text
    $daysLbl.Location = New-Object System.Drawing.Point(18, 114)
    $daysLbl.AutoSize = $true
    $optBox.Controls.Add($daysLbl)

    $daysNum = New-Object System.Windows.Forms.NumericUpDown
    $daysNum.Minimum = 0
    $daysNum.Maximum = 30
    $daysNum.Value = 2
    $daysNum.Location = New-Object System.Drawing.Point(18, 142)
    $daysNum.Width = 70
    $daysNum.BackColor = $btnBg
    $daysNum.ForeColor = $text
    $optBox.Controls.Add($daysNum)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = "Logs save to Desktop\PC-Maintenance-Logs"
    $hint.ForeColor = $muted
    $hint.Location = New-Object System.Drawing.Point(110, 146)
    $hint.AutoSize = $true
    $optBox.Controls.Add($hint)

    $progress = New-Object System.Windows.Forms.ProgressBar
    $progress.Location = New-Object System.Drawing.Point(24, 314)
    $progress.Size = New-Object System.Drawing.Size(796, 22)
    $progress.Style = "Continuous"
    $progress.Anchor = "Top,Left,Right"
    $form.Controls.Add($progress)

    $status = New-Object System.Windows.Forms.Label
    $status.Text = "Ready"
    $status.ForeColor = $muted
    $status.Location = New-Object System.Drawing.Point(24, 342)
    $status.AutoSize = $true
    $form.Controls.Add($status)

    $log = New-Object System.Windows.Forms.RichTextBox
    $log.Location = New-Object System.Drawing.Point(24, 370)
    $log.Size = New-Object System.Drawing.Size(796, 160)
    $log.BackColor = [System.Drawing.Color]::FromArgb(14, 16, 20)
    $log.ForeColor = $text
    $log.Font = New-Object System.Drawing.Font("Consolas", 9)
    $log.ReadOnly = $true
    $log.BorderStyle = "FixedSingle"
    $log.Anchor = "Top,Bottom,Left,Right"
    $form.Controls.Add($log)

    $btnRun = New-Object System.Windows.Forms.Button
    $btnRun.Text = "Run"
    $btnRun.Location = New-Object System.Drawing.Point(24, 548)
    $btnRun.Size = New-Object System.Drawing.Size(140, 36)
    $btnRun.FlatStyle = "Flat"
    $btnRun.BackColor = $accent
    $btnRun.ForeColor = [System.Drawing.Color]::White
    $btnRun.FlatAppearance.BorderSize = 0
    $btnRun.Anchor = "Bottom,Left"
    $form.Controls.Add($btnRun)

    $btnLogs = New-Object System.Windows.Forms.Button
    $btnLogs.Text = "Open logs"
    $btnLogs.Location = New-Object System.Drawing.Point(180, 548)
    $btnLogs.Size = New-Object System.Drawing.Size(140, 36)
    $btnLogs.FlatStyle = "Flat"
    $btnLogs.BackColor = $accent2
    $btnLogs.ForeColor = [System.Drawing.Color]::White
    $btnLogs.FlatAppearance.BorderSize = 0
    $btnLogs.Anchor = "Bottom,Left"
    $form.Controls.Add($btnLogs)

    $btnCli = New-Object System.Windows.Forms.Button
    $btnCli.Text = "CLI menu"
    $btnCli.Location = New-Object System.Drawing.Point(336, 548)
    $btnCli.Size = New-Object System.Drawing.Size(140, 36)
    $btnCli.FlatStyle = "Flat"
    $btnCli.BackColor = $btnBg
    $btnCli.ForeColor = [System.Drawing.Color]::White
    $btnCli.FlatAppearance.BorderSize = 0
    $btnCli.Anchor = "Bottom,Left"
    $form.Controls.Add($btnCli)

    $btnQuit = New-Object System.Windows.Forms.Button
    $btnQuit.Text = "Quit"
    $btnQuit.Location = New-Object System.Drawing.Point(680, 548)
    $btnQuit.Size = New-Object System.Drawing.Size(140, 36)
    $btnQuit.FlatStyle = "Flat"
    $btnQuit.BackColor = [System.Drawing.Color]::FromArgb(90, 50, 50)
    $btnQuit.ForeColor = [System.Drawing.Color]::White
    $btnQuit.FlatAppearance.BorderSize = 0
    $btnQuit.Anchor = "Bottom,Right"
    $form.Controls.Add($btnQuit)

    $Script:GuiControls = @{
        Form       = $form
        ModeBox    = $modeBox
        OptBox     = $optBox
        ChkRestore = $chkRestore
        ChkAmd     = $chkAmd
        DaysNum    = $daysNum
        BtnRun     = $btnRun
        BtnCli     = $btnCli
        Free       = $freeLbl
    }

    $Script:Ui = @{
        Form     = $form
        Progress = $progress
        Status   = $status
        Log      = $log
        Free     = $freeLbl
    }

    Update-GuiFreeSpace

    $btnRun.Add_Click({
        Set-GuiRunningState $true
        $Script:Ui.Progress.Value = 0
        $Script:Ui.Log.Clear()
        $Script:Ui.Status.Text = "Starting..."
        Append-UiLog "Starting PC Maintenance..." "Cyan"

        $mode = Get-GuiSelectedMode
        Apply-ModeFlags -ModeName $mode

        if ($mode -eq "CleanupOnly" -or $mode -eq "Repair") {
            $Script:DoRestorePoint = $Script:GuiControls.ChkRestore.Checked
            $Script:DoAmd = $false
        } else {
            $Script:DoRestorePoint = $Script:GuiControls.ChkRestore.Checked
            $Script:DoAmd = $Script:GuiControls.ChkAmd.Checked
        }

        $Script:TempOlderThanDays = [int]$Script:GuiControls.DaysNum.Value

        try {
            [void](Invoke-MaintenanceRun)
            Update-GuiFreeSpace
            $Script:Ui.Status.Text = ("Finished - {0}" -f (Get-Elapsed))
            [System.Windows.Forms.MessageBox]::Show(
                "Maintenance finished.`nLogs: Desktop\PC-Maintenance-Logs",
                "PC Maintenance",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
        } catch {
            Write-Fail $_.Exception.Message
            $Script:Ui.Status.Text = "Failed"
            [System.Windows.Forms.MessageBox]::Show(
                $_.Exception.Message,
                "PC Maintenance",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        } finally {
            Set-GuiRunningState $false
        }
    }.GetNewClosure())

    $btnLogs.Add_Click({
        $dir = Join-Path $env:USERPROFILE "Desktop\PC-Maintenance-Logs"
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Start-Process explorer.exe $dir
    }.GetNewClosure())

    $btnCli.Add_Click({
        $scriptPath = Join-Path $Script:AppRoot "PC-Maintenance.ps1"
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -Mode Cli"
    }.GetNewClosure())

    $btnQuit.Add_Click({
        $Script:GuiControls.Form.Close()
    }.GetNewClosure())

    [void]$form.ShowDialog()
}

function Show-CliMenu {
    Clear-Host
    Write-Host ""
    Write-Host "  ========================================"
    Write-Host "     PC MAINTENANCE v4"
    Write-Host "  ========================================"
    Write-Host "  Logs: Desktop\PC-Maintenance-Logs"
    Write-Host ""
    Write-Host "  [1] Full run (recommended weekly)"
    Write-Host "  [2] Cleanup only"
    Write-Host "  [3] Updates only"
    Write-Host "  [4] Repair Windows (DISM + SFC)"
    Write-Host "  [5] Full + Repair"
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
            Write-Host "  Invalid - using Full run" -ForegroundColor Yellow
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
