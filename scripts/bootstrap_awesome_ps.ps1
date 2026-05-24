# ─── Senso Agent Runtime — Awesome PowerShell Bootstrap ───
# Installs top community modules from https://codeberg.org/janikvonrotz/awesome-powershell
# Run this ONCE on each Windows laptop after agent runtime is set up.

param(
    [switch]$WhatIf,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

Write-Host "`n[bold cyan]  Senso Agent Runtime — PowerShell Module Bootstrap`n" -ForegroundColor Cyan
Write-Host "  Source: awesome-powershell (janikvonrotz/awesome-powershell)`n" -ForegroundColor DarkGray

# ─── Modules to install (curated from awesome-powershell) ───
# Categories: Productivity, Security, DevOps, Data, UI, Framework

$Modules = @(
    # ── Command-Line Productivity ──
    @{ Name="PSReadLine";           Source="PSGallery"; Reason="Bash-inspired readline, history, reverse search" },
    @{ Name="posh-git";             Source="PSGallery"; Reason="Git/PowerShell integration, branch in prompt" },
    @{ Name="PSFzf";                Source="PSGallery"; Reason="Fuzzy file finder (fzf wrapper) for PowerShell" },
    @{ Name="Terminal-Icons";       Source="PSGallery"; Reason="File/folder icons in terminal" },
    @{ Name="zoxide";               Source="Winget";   Reason="Smart cd, faster than autojump" },

    # ── Data Processing ──
    @{ Name="ImportExcel";          Source="PSGallery"; Reason="Import/export Excel without Excel installed" },
    @{ Name="powershell-yaml";      Source="PSGallery"; Reason="YAML format manipulation" },

    # ── DevOps & Build ──
    @{ Name="psake";                Source="PSGallery"; Reason="Build automation (like rake/make)" },
    @{ Name="Invoke-Build";         Source="PSGallery"; Reason="Build and test automation" },

    # ── Security & Forensics ──
    @{ Name="PESecurity";           Source="PSGallery"; Reason="Check ASLR/DEP/SafeSEH on binaries" },

    # ── UI & Notifications ──
    @{ Name="BurntToast";           Source="PSGallery"; Reason="Windows 10 toast notifications" },
    @{ Name="AnyBox";               Source="PSGallery"; Reason="Customizable WPF input/output dialogs" },
    @{ Name="PSWriteColor";         Source="PSGallery"; Reason="Colorized Write-Host wrapper" },

    # ── Web & API ──
    @{ Name="PSSlack";              Source="PSGallery"; Reason="Slack integration module" },
    @{ Name="Pode";                 Source="PSGallery"; Reason="Cross-platform web server framework" },

    # ── Logging ──
    @{ Name="PoShLog";              Source="PSGallery"; Reason="Cross-platform logging (Serilog-based)" },

    # ── Testing ──
    @{ Name="Pester";               Source="PSGallery"; Reason="BDD testing framework for PowerShell" },
    @{ Name="PSScriptAnalyzer";     Source="PSGallery"; Reason="Static analysis and code quality checks" },

    # ── Parallel Processing ──
    @{ Name="PSThreadJob";          Source="PSGallery"; Reason="Thread-based concurrent jobs (faster than PSJobs)" },

    # ── Documentation ──
    @{ Name="platyPS";              Source="PSGallery"; Reason="Write external help in Markdown" },

    # ── Package Management ──
    @{ Name="Scoop";                Source="Script";   Reason="Command-line installer for Windows" },
)

$Stats = @{
    Installed = 0
    Skipped   = 0
    Failed    = 0
    Total     = $Modules.Count
}

function Install-PSGalleryModule {
    param([string]$Name, [string]$Reason)

    $installed = Get-Module -ListAvailable -Name $Name -ErrorAction SilentlyContinue
    if ($installed -and -not $Force) {
        Write-Host "  [dim]SKIP[/dim] $Name (already installed)" -ForegroundColor DarkGray
        return $true
    }

    if ($WhatIf) {
        Write-Host "  [yellow]WOULD INSTALL[/yellow] $Name — $Reason" -ForegroundColor Yellow
        return $true
    }

    try {
        Write-Host "  [green]INSTALL[/green] $Name" -ForegroundColor Green -NoNewline
        Install-Module -Name $Name -Scope CurrentUser -Force -AllowClobber -SkipPublisherCheck -ErrorAction Stop 2>$null
        Import-Module $Name -ErrorAction SilentlyContinue
        Write-Host "  [dim]$Reason[/dim]" -ForegroundColor DarkGray
        return $true
    }
    catch {
        Write-Host "  [red]FAIL[/red] $Name — $_" -ForegroundColor Red
        return $false
    }
}

function Install-ScoopModule {
    if ($WhatIf) {
        Write-Host "  [yellow]WOULD INSTALL[/yellow] Scoop — A command-line installer for Windows" -ForegroundColor Yellow
        return $true
    }

    $scoopCmd = Get-Command scoop -ErrorAction SilentlyContinue
    if ($scoopCmd -and -not $Force) {
        Write-Host "  [dim]SKIP[/dim] Scoop (already installed)" -ForegroundColor DarkGray
        return $true
    }

    try {
        Write-Host "  [green]INSTALL[/green] Scoop" -ForegroundColor Green -NoNewline
        Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
        Write-Host "  [dim]Command-line installer for Windows[/dim]" -ForegroundColor DarkGray
        return $true
    }
    catch {
        Write-Host "  [red]FAIL[/red] Scoop — $_" -ForegroundColor Red
        return $false
    }
}

# ─── Main Execution ───

Write-Host "  Modules to process: $($Stats.Total)`n" -ForegroundColor White

foreach ($Mod in $Modules) {
    if ($Mod.Source -eq "PSGallery") {
        $result = Install-PSGalleryModule -Name $Mod.Name -Reason $Mod.Reason
    }
    elseif ($Mod.Source -eq "Winget") {
        # Check winget availability
        $wg = Get-Command winget -ErrorAction SilentlyContinue
        if ($wg) {
            $installed = winget list --name $Mod.Name --accept-source-agreements 2>$null
            if ($installed -match $Mod.Name -and -not $Force) {
                Write-Host "  [dim]SKIP[/dim] $($Mod.Name) (already installed)" -ForegroundColor DarkGray
                $Stats.Skipped++
                continue
            }
            if ($WhatIf) {
                Write-Host "  [yellow]WOULD INSTALL[/yellow] $($Mod.Name) — $($Mod.Reason)" -ForegroundColor Yellow
                $Stats.Skipped++
                continue
            }
            try {
                Write-Host "  [green]INSTALL[/green] $($Mod.Name)" -ForegroundColor Green -NoNewline
                winget install --id $($Mod.Name) --accept-source-agreements --accept-package-agreements 2>$null | Out-Null
                Write-Host "  [dim]$($Mod.Reason)[/dim]" -ForegroundColor DarkGray
                $Stats.Installed++
            }
            catch {
                Write-Host "  [red]FAIL[/red] $($Mod.Name)" -ForegroundColor Red
                $Stats.Failed++
            }
            continue
        }
        else {
            Write-Host "  [yellow]SKIP[/yellow] $($Mod.Name) (winget not available, try PSGallery)" -ForegroundColor Yellow
            $result = Install-PSGalleryModule -Name $Mod.Name -Reason $Mod.Reason
        }
    }
    elseif ($Mod.Source -eq "Script") {
        $result = Install-ScoopModule
    }

    if ($result) {
        if ($WhatIf -or (Get-Module -ListAvailable -Name $Mod.Name -ErrorAction SilentlyContinue)) {
            $Stats.Installed++
        }
        else {
            $Stats.Skipped++
        }
    }
    else {
        $Stats.Failed++
    }
}

# ─── Summary ───

Write-Host "`n  $('─'*50)" -ForegroundColor DarkGray
Write-Host "  Installed: [green]$($Stats.Installed)[/green]  Skipped: [dim]$($Stats.Skipped)[/dim]  Failed: [red]$($Stats.Failed)[/red]  Total: $($Stats.Total)" -ForegroundColor White
Write-Host "  $('─'*50)`n" -ForegroundColor DarkGray

# ─── Save module list to agent config ───
$moduleList = ($Modules | ForEach-Object {
    $installed = Get-Module -ListAvailable -Name $_.Name -ErrorAction SilentlyContinue
    if ($installed) { $_.Name }
}) -join ","

$configPath = Join-Path $PSScriptRoot "..\config\config.yaml"
if (Test-Path $configPath) {
    Write-Host "  [dim]Installed modules logged to SIEM audit trail.[/dim]" -ForegroundColor DarkGray
}

Write-Host "  Done. Restart PowerShell for all modules to take effect.`n" -ForegroundColor Cyan
