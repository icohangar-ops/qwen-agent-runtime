# Senso Agent Runtime - Awesome PowerShell Bootstrap
# Installs top community modules from awesome-powershell
# Run: powershell -ExecutionPolicy Bypass -File scripts\bootstrap_awesome_ps.ps1

param(
    [switch]$WhatIf,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

Write-Host ""
Write-Host "  Senso Agent Runtime - PowerShell Module Bootstrap" -ForegroundColor Cyan
Write-Host "  Source: awesome-powershell (janikvonrotz/awesome-powershell)" -ForegroundColor DarkGray
Write-Host ""

$ModuleList = @(
    @{ Name="PSReadLine";       Reason="Bash-inspired readline, history, reverse search" },
    @{ Name="posh-git";         Reason="Git/PowerShell integration, branch in prompt" },
    @{ Name="PSFzf";            Reason="Fuzzy file finder (fzf wrapper) for PowerShell" },
    @{ Name="Terminal-Icons";   Reason="File and folder icons in terminal" },
    @{ Name="ImportExcel";      Reason="Import/export Excel without Excel installed" },
    @{ Name="powershell-yaml";  Reason="YAML format manipulation" },
    @{ Name="psake";            Reason="Build automation (like rake/make)" },
    @{ Name="Invoke-Build";     Reason="Build and test automation" },
    @{ Name="PESecurity";       Reason="Check ASLR/DEP/SafeSEH on binaries" },
    @{ Name="BurntToast";       Reason="Windows 10 toast notifications" },
    @{ Name="AnyBox";           Reason="Customizable WPF input/output dialogs" },
    @{ Name="PSWriteColor";     Reason="Colorized Write-Host wrapper" },
    @{ Name="PSSlack";          Reason="Slack integration module" },
    @{ Name="Pode";             Reason="Cross-platform web server framework" },
    @{ Name="PoShLog";          Reason="Cross-platform logging (Serilog-based)" },
    @{ Name="Pester";           Reason="BDD testing framework for PowerShell" },
    @{ Name="PSScriptAnalyzer"; Reason="Static analysis and code quality checks" },
    @{ Name="PSThreadJob";      Reason="Thread-based concurrent jobs" },
    @{ Name="platyPS";          Reason="Write external help in Markdown" }
)

$installedCount = 0
$skippedCount = 0
$failedCount = 0

Write-Host "  Modules to process: $($ModuleList.Count)" -ForegroundColor White
Write-Host ""

foreach ($Mod in $ModuleList) {
    $name = $Mod.Name
    $reason = $Mod.Reason

    $alreadyInstalled = Get-Module -ListAvailable -Name $name -ErrorAction SilentlyContinue

    if ($alreadyInstalled -and -not $Force) {
        Write-Host "  SKIP $name (already installed)" -ForegroundColor DarkGray
        $skippedCount++
        continue
    }

    if ($WhatIf) {
        Write-Host "  WOULD INSTALL $name - $reason" -ForegroundColor Yellow
        $skippedCount++
        continue
    }

    try {
        Write-Host "  INSTALL $name ... " -ForegroundColor Green -NoNewline
        Install-Module -Name $name -Scope CurrentUser -Force -AllowClobber -SkipPublisherCheck -ErrorAction Stop 2>$null
        Import-Module $name -ErrorAction SilentlyContinue
        Write-Host "OK - $reason" -ForegroundColor DarkGray
        $installedCount++
    }
    catch {
        Write-Host "FAILED" -ForegroundColor Red
        Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor Red
        $failedCount++
    }
}

Write-Host ""
Write-Host "  --------------------------------------------------" -ForegroundColor DarkGray
Write-Host "  Installed: $installedCount  Skipped: $skippedCount  Failed: $failedCount  Total: $($ModuleList.Count)" -ForegroundColor White
Write-Host "  --------------------------------------------------" -ForegroundColor DarkGray
Write-Host ""

# Optional: Install Scoop
$scoopCmd = Get-Command scoop -ErrorAction SilentlyContinue
if (-not $scoopCmd -and -not $WhatIf) {
    Write-Host "  Scoop (package installer) not found. Install it?" -ForegroundColor Yellow
    Write-Host "  Run: Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression" -ForegroundColor DarkGray
}

Write-Host "  Done. Restart PowerShell for all modules to take effect." -ForegroundColor Cyan
Write-Host ""
