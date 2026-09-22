#Requires -Version 5.1
# Tab page builders for Show-MaintenanceGui (widgets live in Gui.ps1).

function Add-GuiHomePage {
    param(
        $Page,
        $Theme
    )
    $t = $Theme
            $homeSplit = New-Object System.Windows.Forms.TableLayoutPanel
        $homeSplit.Dock = "Fill"
        $homeSplit.ColumnCount = 2
        $homeSplit.RowCount = 1
        [void]$homeSplit.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 58)))
        [void]$homeSplit.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 42)))
        $homeSplit.Padding = New-Object System.Windows.Forms.Padding(0)
        $Page.Controls.Add($homeSplit)

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

        # Score hero (Dock Top added last = sits above System Summary)
        $cardHomeScore = New-CardPanel "Your PC for gaming" "Top"
        $cardHomeScore.Height = 178
        $cardHomeScore.Padding = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
        $homeLeft.Controls.Add($cardHomeScore)

        $homeScoreVal = New-Object System.Windows.Forms.Label
        $homeScoreVal.Text = "--"
        $homeScoreVal.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 28)
        $homeScoreVal.ForeColor = $t.Accent
        $homeScoreVal.Location = New-Object System.Drawing.Point(20, 40)
        $homeScoreVal.Size = New-Object System.Drawing.Size(90, 44)
        $homeScoreVal.BackColor = [System.Drawing.Color]::Transparent
        $cardHomeScore.Controls.Add($homeScoreVal)

        $homeGradeVal = New-Object System.Windows.Forms.Label
        $homeGradeVal.Text = "/100"
        $homeGradeVal.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 12)
        $homeGradeVal.ForeColor = $t.Text
        $homeGradeVal.Location = New-Object System.Drawing.Point(110, 54)
        $homeGradeVal.AutoSize = $true
        $homeGradeVal.BackColor = [System.Drawing.Color]::Transparent
        $cardHomeScore.Controls.Add($homeGradeVal)

        $homeLimiterVal = New-Object System.Windows.Forms.Label
        $homeLimiterVal.Text = "Scanning..."
        $homeLimiterVal.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $homeLimiterVal.ForeColor = $t.Muted
        $homeLimiterVal.Location = New-Object System.Drawing.Point(20, 88)
        $homeLimiterVal.Size = New-Object System.Drawing.Size(480, 18)
        $homeLimiterVal.Anchor = "Top,Left,Right"
        $homeLimiterVal.BackColor = [System.Drawing.Color]::Transparent
        $cardHomeScore.Controls.Add($homeLimiterVal)

        $homeFixesVal = New-Object System.Windows.Forms.Label
        $homeFixesVal.Text = ""
        $homeFixesVal.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
        $homeFixesVal.ForeColor = $t.Muted
        $homeFixesVal.Location = New-Object System.Drawing.Point(20, 108)
        $homeFixesVal.Size = New-Object System.Drawing.Size(480, 58)
        $homeFixesVal.Anchor = "Top,Left,Right"
        $homeFixesVal.BackColor = [System.Drawing.Color]::Transparent
        $cardHomeScore.Controls.Add($homeFixesVal)

        $cardHomeScore.Add_Resize({
            param($sender, $e)
            $w = [math]::Max(200, $sender.ClientSize.Width - 40)
            $homeLimiterVal.Width = $w
            $homeFixesVal.Width = $w
        }.GetNewClosure())

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
        $cardOpts.AutoScroll = $true
        $homeRight.Controls.Add($cardOpts)

        $btnFixMyPc = New-PremiumButton "Fix my PC for gaming" (New-Object System.Drawing.Point(20, 48)) (New-Object System.Drawing.Size(360, 44)) "Cta"
        $btnWeekly = New-PremiumButton "Run Weekly Full" (New-Object System.Drawing.Point(20, 100)) (New-Object System.Drawing.Size(240, 40)) "Primary"
        $btnRefreshHome = New-PremiumButton "Refresh" (New-Object System.Drawing.Point(270, 100)) (New-Object System.Drawing.Size(110, 40)) "Ghost"
        $cardOpts.Controls.AddRange(@($btnFixMyPc, $btnWeekly, $btnRefreshHome))

        $chkHomeRestore = New-PremiumCheck "Create restore point" (New-Object System.Drawing.Point(20, 156)) $true
        $chkHomeShader = New-PremiumCheck "Clear GPU shader caches" (New-Object System.Drawing.Point(20, 184)) $true
        $chkHomeGaming = New-PremiumCheck "Apply gaming optimizations" (New-Object System.Drawing.Point(20, 212)) $true
        $chkHomeWU = New-PremiumCheck "Windows Update (slow)" (New-Object System.Drawing.Point(20, 240)) $false
        $chkHomeWinget = New-PremiumCheck "winget app upgrades (slow)" (New-Object System.Drawing.Point(20, 268)) $false
        $cardOpts.Controls.AddRange(@($chkHomeRestore, $chkHomeShader, $chkHomeGaming, $chkHomeWU, $chkHomeWinget))

        $presetLbl = New-Object System.Windows.Forms.Label
        $presetLbl.Text = "Presets"
        $presetLbl.ForeColor = $t.Muted
        $presetLbl.Location = New-Object System.Drawing.Point(20, 304)
        $presetLbl.AutoSize = $true
        $cardOpts.Controls.Add($presetLbl)

        $btnPresetGamer = New-PremiumButton "Gamer" (New-Object System.Drawing.Point(20, 326)) (New-Object System.Drawing.Size(100, 34)) "Ghost"
        $btnPresetQuiet = New-PremiumButton "Quiet" (New-Object System.Drawing.Point(130, 326)) (New-Object System.Drawing.Size(100, 34)) "Ghost"
        $btnPresetFull = New-PremiumButton "Full" (New-Object System.Drawing.Point(240, 326)) (New-Object System.Drawing.Size(100, 34)) "Ghost"
        $cardOpts.Controls.AddRange(@($btnPresetGamer, $btnPresetQuiet, $btnPresetFull))

        $chkScheduleWeekly = New-PremiumCheck "Schedule Weekly Full (Sundays 6 PM)" (New-Object System.Drawing.Point(20, 370)) $false
        $cardOpts.Controls.Add($chkScheduleWeekly)

        $lblScheduleStatus = New-Object System.Windows.Forms.Label
        $lblScheduleStatus.Text = "Weekly schedule: off"
        $lblScheduleStatus.ForeColor = $t.Muted
        $lblScheduleStatus.Location = New-Object System.Drawing.Point(20, 400)
        $lblScheduleStatus.Size = New-Object System.Drawing.Size(360, 18)
        $cardOpts.Controls.Add($lblScheduleStatus)

        $nextLbl = New-Object System.Windows.Forms.Label
        $nextLbl.Text = "Presets fill the checkboxes. Schedule runs your saved Home options while signed in."
        $nextLbl.ForeColor = $t.Muted
        $nextLbl.Location = New-Object System.Drawing.Point(20, 424)
        $nextLbl.Size = New-Object System.Drawing.Size(360, 36)
        $cardOpts.Controls.Add($nextLbl)

        $layoutHomeOpts = {
            param($sender, $e)
            $pad = 20
            $w = [math]::Max(180, $sender.ClientSize.Width - ($pad * 2))
            $y = 48

            $btnFixMyPc.SetBounds($pad, $y, $w, 44)
            $y += 54

            $refreshW = 110
            $gap = 10
            $weekW = [math]::Max(140, $w - $refreshW - $gap)
            $btnWeekly.SetBounds($pad, $y, $weekW, 40)
            $btnRefreshHome.SetBounds(($pad + $weekW + $gap), $y, $refreshW, 40)
            $y += 52

            foreach ($chk in @($chkHomeRestore, $chkHomeShader, $chkHomeGaming, $chkHomeWU, $chkHomeWinget)) {
                $chk.Location = New-Object System.Drawing.Point($pad, $y)
                $y += 28
            }

            $y += 8
            $presetLbl.Location = New-Object System.Drawing.Point($pad, $y)
            $y += 22
            $pw = [math]::Max(80, [int][math]::Floor(($w - 20) / 3.0))
            $btnPresetGamer.SetBounds($pad, $y, $pw, 34)
            $btnPresetQuiet.SetBounds(($pad + $pw + 10), $y, $pw, 34)
            $btnPresetFull.SetBounds(($pad + (2 * ($pw + 10))), $y, $pw, 34)
            $y += 44

            $chkScheduleWeekly.Location = New-Object System.Drawing.Point($pad, $y)
            $y += 28
            $lblScheduleStatus.SetBounds($pad, $y, $w, 18)
            $y += 22
            $nextLbl.SetBounds($pad, $y, $w, 36)
            $y += 44

            $sender.AutoScrollMinSize = New-Object System.Drawing.Size(0, $y)
        }.GetNewClosure()

        $cardOpts.Add_Resize($layoutHomeOpts)
        [void]$layoutHomeOpts.Invoke($cardOpts, $null)


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
    param(
        $Page,
        $Theme
    )
    $t = $Theme
            $cardClean = New-CardPanel "Cleanup" "Fill"
        $Page.Controls.Add($cardClean)

        $cleanHint = New-Object System.Windows.Forms.Label
        $cleanHint.Text = "Safe free-space cleanup. Preview sizes first. Browser caches cover all profiles. Launcher caches need confirmation. WU download-cache wipe is opt-in."
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
        $chkEpic = New-PremiumCheck "Epic cache / logs / Data / EMS / staging" (New-Object System.Drawing.Point(20, 208)) $false
        $chkRiot = New-PremiumCheck "Riot Client cache/logs" (New-Object System.Drawing.Point(20, 244)) $false
        $chkWuCache = New-PremiumCheck "Windows Update download cache (stops wuauserv briefly)" (New-Object System.Drawing.Point(20, 280)) $false
        $cardClean.Controls.AddRange(@($chkCleanShader, $chkSteam, $chkEpic, $chkRiot, $chkWuCache))

        $lblCleanupLive = New-Object System.Windows.Forms.Label
        $lblCleanupLive.Text = "Ready - preview sizes or run cleanup."
        $lblCleanupLive.ForeColor = $t.Muted
        $lblCleanupLive.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $lblCleanupLive.Location = New-Object System.Drawing.Point(20, 318)
        $lblCleanupLive.Size = New-Object System.Drawing.Size(900, 22)
        $lblCleanupLive.Anchor = "Left,Right,Bottom"
        $cardClean.Controls.Add($lblCleanupLive)

        $btnPreview = New-PremiumButton "Preview sizes" (New-Object System.Drawing.Point(20, 350)) (New-Object System.Drawing.Size(140, 44)) "Ghost"
        $btnCleanup = New-PremiumButton "Run Cleanup" (New-Object System.Drawing.Point(20, 350)) (New-Object System.Drawing.Size(200, 44)) "Primary"
        $btnCleanup.Anchor = "Bottom,Right"
        $btnPreview.Anchor = "Bottom,Left"
        $cardClean.Controls.AddRange(@($btnPreview, $btnCleanup))
        $cardClean.Add_Resize({
            param($sender, $e)
            # Never ride up over the last checkbox on short windows
            $floor = $chkWuCache.Bottom + 16
            $top = [math]::Max($floor + 30, $sender.ClientSize.Height - 60)
            $btnCleanup.Left = [math]::Max(180, $sender.ClientSize.Width - 220)
            $btnCleanup.Top = $top
            $btnPreview.Top = $top
            $lblCleanupLive.Top = $top - 28
            $lblCleanupLive.Width = [math]::Max(200, $sender.ClientSize.Width - 40)
            $cleanHint.Width = $sender.ClientSize.Width - 40
        }.GetNewClosure())


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
    param(
        $Page,
        $Theme
    )
    $t = $Theme
            $cardUpd = New-CardPanel "Updates" "Fill"
        $Page.Controls.Add($cardUpd)

        $updHint = New-Object System.Windows.Forms.Label
        $updHint.Text = "Installs Windows Update + winget apps. Self-updaters (Roblox, Discord, Steam, Epic) are skipped."
        $updHint.ForeColor = $t.Muted
        $updHint.Location = New-Object System.Drawing.Point(20, 48)
        $updHint.Size = New-Object System.Drawing.Size(900, 28)
        $updHint.Anchor = "Top,Left,Right"
        $cardUpd.Controls.Add($updHint)

        $chkUpdRestore = New-PremiumCheck "Create restore point first" (New-Object System.Drawing.Point(20, 96)) $true
        $chkUpdWU = New-PremiumCheck "Windows Update" (New-Object System.Drawing.Point(20, 132)) $true
        $chkUpdWinget = New-PremiumCheck "winget upgrades" (New-Object System.Drawing.Point(20, 168)) $true
        $cardUpd.Controls.AddRange(@($chkUpdRestore, $chkUpdWU, $chkUpdWinget))

        $lblUpdatesLive = New-Object System.Windows.Forms.Label
        $lblUpdatesLive.Text = "Ready - Windows Update and winget when you need them."
        $lblUpdatesLive.ForeColor = $t.Muted
        $lblUpdatesLive.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $lblUpdatesLive.Location = New-Object System.Drawing.Point(20, 210)
        $lblUpdatesLive.Size = New-Object System.Drawing.Size(900, 22)
        $lblUpdatesLive.Anchor = "Left,Right,Bottom"
        $cardUpd.Controls.Add($lblUpdatesLive)

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
            $lblUpdatesLive.Top = $y - 28
            $lblUpdatesLive.Width = [math]::Max(200, $sender.ClientSize.Width - 40)
            $updHint.Width = $sender.ClientSize.Width - 40
        }.GetNewClosure())


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
    param(
        $Page,
        $Theme
    )
    $t = $Theme
            $gameSplit = New-Object System.Windows.Forms.TableLayoutPanel
        $gameSplit.Dock = "Fill"
        $gameSplit.ColumnCount = 2
        $gameSplit.RowCount = 1
        [void]$gameSplit.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 62)))
        [void]$gameSplit.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 38)))
        $Page.Controls.Add($gameSplit)

        $gameLeft = New-Object System.Windows.Forms.Panel
        $gameLeft.Dock = "Fill"
        $gameLeft.Padding = New-Object System.Windows.Forms.Padding(0, 0, 12, 0)
        $gameSplit.Controls.Add($gameLeft, 0, 0)

        $cardGameStatus = New-CardPanel "Gaming Status" "Fill"
        $gameLeft.Controls.Add($cardGameStatus)

        $optScoreVal = New-Object System.Windows.Forms.Label
        $optScoreVal.Text = "--"
        $optScoreVal.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 28)
        $optScoreVal.ForeColor = $t.Accent
        $optScoreVal.Location = New-Object System.Drawing.Point(16, 42)
        $optScoreVal.Size = New-Object System.Drawing.Size(90, 44)
        $optScoreVal.BackColor = [System.Drawing.Color]::Transparent
        $cardGameStatus.Controls.Add($optScoreVal)

        $optGradeVal = New-Object System.Windows.Forms.Label
        $optGradeVal.Text = "/100"
        $optGradeVal.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 12)
        $optGradeVal.ForeColor = $t.Text
        $optGradeVal.Location = New-Object System.Drawing.Point(100, 54)
        $optGradeVal.Size = New-Object System.Drawing.Size(280, 28)
        $optGradeVal.BackColor = [System.Drawing.Color]::Transparent
        $cardGameStatus.Controls.Add($optGradeVal)

        $optLimiterVal = New-Object System.Windows.Forms.Label
        $optLimiterVal.Text = "Scanning..."
        $optLimiterVal.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $optLimiterVal.ForeColor = $t.Muted
        $optLimiterVal.Location = New-Object System.Drawing.Point(16, 88)
        $optLimiterVal.Size = New-Object System.Drawing.Size(520, 20)
        $optLimiterVal.Anchor = "Top,Left,Right"
        $optLimiterVal.BackColor = [System.Drawing.Color]::Transparent
        $cardGameStatus.Controls.Add($optLimiterVal)

        $optFixesTitle = New-Object System.Windows.Forms.Label
        $optFixesTitle.Text = "Top fixes"
        $optFixesTitle.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9)
        $optFixesTitle.ForeColor = $t.Text
        $optFixesTitle.Location = New-Object System.Drawing.Point(16, 112)
        $optFixesTitle.Size = New-Object System.Drawing.Size(200, 18)
        $optFixesTitle.BackColor = [System.Drawing.Color]::Transparent
        $cardGameStatus.Controls.Add($optFixesTitle)

        $optFixesVal = New-Object System.Windows.Forms.Label
        $optFixesVal.Text = ""
        $optFixesVal.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
        $optFixesVal.ForeColor = $t.Muted
        $optFixesVal.Location = New-Object System.Drawing.Point(16, 132)
        $optFixesVal.Size = New-Object System.Drawing.Size(520, 58)
        $optFixesVal.Anchor = "Top,Left,Right"
        $optFixesVal.BackColor = [System.Drawing.Color]::Transparent
        $cardGameStatus.Controls.Add($optFixesVal)

        $rowsHost = New-Object System.Windows.Forms.Panel
        $rowsHost.Location = New-Object System.Drawing.Point(8, 196)
        $rowsHost.Size = New-Object System.Drawing.Size(560, 220)
        $rowsHost.Anchor = "Top,Bottom,Left,Right"
        $rowsHost.BackColor = $t.Panel
        # Five 52px rows need 260px; scroll instead of clipping on short windows
        $rowsHost.AutoScroll = $true
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
            $w = [math]::Max(200, $sender.ClientSize.Width - 32)
            $optLimiterVal.Width = $w
            $optFixesVal.Width = $w
            $rowsHost.Width = $sender.ClientSize.Width - 16
            $rowsHost.Height = [math]::Max(120, $sender.ClientSize.Height - 204)
        }.GetNewClosure())

        $gameRight = New-Object System.Windows.Forms.Panel
        $gameRight.Dock = "Fill"
        $gameRight.Padding = New-Object System.Windows.Forms.Padding(12, 0, 0, 0)
        $gameSplit.Controls.Add($gameRight, 1, 0)

        $cardGameActions = New-CardPanel "Actions" "Fill"
        $gameRight.Controls.Add($cardGameActions)

        $btnGamingOpt = New-PremiumButton "Apply gaming optimize" (New-Object System.Drawing.Point(24, 52)) (New-Object System.Drawing.Size(280, 44)) "Primary"
        $btnApplyOptFixes = New-PremiumButton "Apply recommended fixes" (New-Object System.Drawing.Point(24, 104)) (New-Object System.Drawing.Size(280, 44)) "Ghost"
        $btnFixPower = New-PremiumButton "Fix power plan (Ultimate)" (New-Object System.Drawing.Point(24, 156)) (New-Object System.Drawing.Size(280, 44)) "Ghost"
        $btnDiscordOff = New-PremiumButton "Discord HW accel OFF" (New-Object System.Drawing.Point(24, 208)) (New-Object System.Drawing.Size(280, 44)) "Ghost"
        $btnScanScore = New-PremiumButton "Scan optimization score" (New-Object System.Drawing.Point(24, 260)) (New-Object System.Drawing.Size(280, 44)) "Ghost"
        $btnRefreshGame = New-PremiumButton "Refresh status" (New-Object System.Drawing.Point(24, 312)) (New-Object System.Drawing.Size(280, 44)) "Ghost"
        $cardGameActions.Controls.AddRange(@($btnGamingOpt, $btnApplyOptFixes, $btnFixPower, $btnDiscordOff, $btnScanScore, $btnRefreshGame))

        $gameTip = New-Object System.Windows.Forms.Label
        $gameTip.Text = "Score = config/setup for gaming feel, not GPU power. Fullscreen + FPS near refresh rate helps 1% lows."
        $gameTip.ForeColor = $t.Muted
        $gameTip.Location = New-Object System.Drawing.Point(24, 368)
        $gameTip.Size = New-Object System.Drawing.Size(280, 52)
        $gameTip.Anchor = "Bottom,Left,Right"
        $cardGameActions.Controls.Add($gameTip)

        $cardGameActions.Add_Resize({
            param($sender, $e)
            $w = [math]::Max(200, $sender.ClientSize.Width - 48)
            foreach ($b in @($btnGamingOpt, $btnApplyOptFixes, $btnFixPower, $btnDiscordOff, $btnScanScore, $btnRefreshGame)) {
                $b.Width = $w
            }
            $gameTip.Width = $w
            $gameTip.Top = $sender.ClientSize.Height - 60
        }.GetNewClosure())


    return [ordered]@{
        BtnApplyOptFixes = $btnApplyOptFixes
        BtnDiscordOff = $btnDiscordOff
        BtnFixPower = $btnFixPower
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
    param(
        $Page,
        $Theme
    )
    $t = $Theme
            $cardRepair = New-CardPanel "Repair" "Fill"
        $Page.Controls.Add($cardRepair)

        $repHint = New-Object System.Windows.Forms.Label
        $repHint.Text = "Only when Windows feels broken. DISM + SFC can take 10-30+ minutes."
        $repHint.ForeColor = $t.Muted
        $repHint.Location = New-Object System.Drawing.Point(20, 52)
        $repHint.Size = New-Object System.Drawing.Size(900, 28)
        $repHint.Anchor = "Top,Left,Right"
        $cardRepair.Controls.Add($repHint)

        $chkRepRestore = New-PremiumCheck "Create restore point first" (New-Object System.Drawing.Point(20, 100)) $true
        $cardRepair.Controls.Add($chkRepRestore)

        $lblRepairLive = New-Object System.Windows.Forms.Label
        $lblRepairLive.Text = "Ready - only run when Windows feels broken."
        $lblRepairLive.ForeColor = $t.Muted
        $lblRepairLive.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $lblRepairLive.Location = New-Object System.Drawing.Point(20, 140)
        $lblRepairLive.Size = New-Object System.Drawing.Size(900, 22)
        $lblRepairLive.Anchor = "Left,Right,Bottom"
        $cardRepair.Controls.Add($lblRepairLive)

        $btnRepair = New-PremiumButton "Run DISM + SFC" (New-Object System.Drawing.Point(20, 180)) (New-Object System.Drawing.Size(200, 48)) "Danger"
        $btnRestoreOnly = New-PremiumButton "Restore point only" (New-Object System.Drawing.Point(240, 180)) (New-Object System.Drawing.Size(200, 48)) "Ghost"
        $btnRepair.Anchor = "Bottom,Left"
        $btnRestoreOnly.Anchor = "Bottom,Left"
        $cardRepair.Controls.AddRange(@($btnRepair, $btnRestoreOnly))
        $cardRepair.Add_Resize({
            param($sender, $e)
            $y = $sender.ClientSize.Height - 64
            $btnRepair.Top = $y
            $btnRestoreOnly.Top = $y
            $lblRepairLive.Top = $y - 28
            $lblRepairLive.Width = [math]::Max(200, $sender.ClientSize.Width - 40)
            $repHint.Width = $sender.ClientSize.Width - 40
        }.GetNewClosure())


    return [ordered]@{
        BtnRepair = $btnRepair
        BtnRestoreOnly = $btnRestoreOnly
        ChkRepRestore = $chkRepRestore
        LblRepairLive = $lblRepairLive
    }
}

function Add-GuiDevicePage {
    param(
        $Page,
        $Theme
    )
    $t = $Theme
            $devSplit = New-Object System.Windows.Forms.TableLayoutPanel
        $devSplit.Dock = "Fill"
        $devSplit.ColumnCount = 2
        $devSplit.RowCount = 1
        [void]$devSplit.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 62)))
        [void]$devSplit.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 38)))
        $Page.Controls.Add($devSplit)

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
        $btnCheckUpdate = New-PremiumButton "Check / install app update" (New-Object System.Drawing.Point(24, 208)) (New-Object System.Drawing.Size(280, 40)) "Ghost"
        $btnRestartNow = New-PremiumButton "Restart PC now" (New-Object System.Drawing.Point(24, 260)) (New-Object System.Drawing.Size(280, 40)) "Danger"
        $cardDevAct.Controls.AddRange(@($btnRefreshDevice, $btnCopyRamTip, $btnOpenStorage, $btnCheckUpdate, $btnRestartNow))

        $devTip = New-Object System.Windows.Forms.Label
        $devTip.Text = "Opt score lives on Gaming tab. Power plan / Game Mode fixes are there too."
        $devTip.ForeColor = $t.Muted
        $devTip.Location = New-Object System.Drawing.Point(24, 320)
        $devTip.Size = New-Object System.Drawing.Size(280, 40)
        $devTip.Anchor = "Bottom,Left,Right"
        $cardDevAct.Controls.Add($devTip)

        $cardDevAct.Add_Resize({
            param($sender, $e)
            $w = [math]::Max(200, $sender.ClientSize.Width - 48)
            foreach ($b in @($btnRefreshDevice, $btnCopyRamTip, $btnOpenStorage, $btnCheckUpdate, $btnRestartNow)) {
                $b.Width = $w
            }
            $devTip.Width = $w
            $devTip.Top = $sender.ClientSize.Height - 48
        }.GetNewClosure())



    return [ordered]@{
        BtnCheckUpdate = $btnCheckUpdate
        BtnCopyRamTip = $btnCopyRamTip
        BtnOpenStorage = $btnOpenStorage
        BtnRefreshDevice = $btnRefreshDevice
        BtnRestartNow = $btnRestartNow
        DeviceSummary = $deviceSummary
    }
}

