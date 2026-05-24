# Senso Agent Runtime - Awesome PowerShell Bootstrap v2
# Installs top community modules from awesome-powershell
# Run: powershell -ExecutionPolicy Bypass -File scripts\bootstrap_awesome_ps.ps1
#
# v2 fixes:
#   - Fixed module names: InvokeBuild (not Invoke-Build), ThreadJob (not PSThreadJob)
#   - Skipped PESecurity (repo removed from PSGallery and GitHub)
#   - Added Scoop + fzf prereq check for PSFzf
#   - Removed modules with deps on missing native binaries

param(
    [switch]$WhatIf,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

Write-Host ""
Write-Host "  Senso Agent Runtime - PowerShell Module Bootstrap v2" -ForegroundColor Cyan
Write-Host "  Source: awesome-powershell (janikvonrotz/awesome-powershell)" -ForegroundColor DarkGray
Write-Host ""

# --- Step 1: Ensure Scoop + fzf are available for PSFzf ---
Write-Host "  [Prereqs] Checking fzf for PSFzf..." -ForegroundColor Yellow

$scoopCmd = Get-Command scoop -ErrorAction SilentlyContinue
$fzfCmd = Get-Command fzf -ErrorAction SilentlyContinue

if (-not $fzfCmd) {
    if (-not $scoopCmd) {
        Write-Host "  [Prereqs] Scoop not found. Installing Scoop..." -ForegroundColor Yellow
        if (-not $WhatIf) {
            try {
                Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
                # Refresh PATH for current session
                $env:PATH = "$env:USERPROFILE\scoop\shims;$env:PATH"
                Write-Host "  [Prereqs] Scoop installed OK" -ForegroundColor Green
            }
            catch {
                Write-Host "  [Prereqs] Scoop install FAILED: $($_.Exception.Message)" -ForegroundColor Red
                Write-Host "  [Prereqs] Run manually: Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression" -ForegroundColor DarkGray
            }
        }
        else {
            Write-Host "  [Prereqs] WOULD install Scoop" -ForegroundColor Yellow
        }
    }

    if (-not $WhatIf) {
        Write-Host "  [Prereqs] Installing fzf via Scoop..." -ForegroundColor Yellow
        try {
            scoop install fzf 2>&1
            $env:PATH = "$env:USERPROFILE\scoop\shims;$env:PATH"
            Write-Host "  [Prereqs] fzf installed OK" -ForegroundColor Green
        }
        catch {
            Write-Host "  [Prereqs] fzf install FAILED: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "  [Prereqs] PSFzf will still install but needs fzf binary to work" -ForegroundColor DarkGray
        }
    }
    else {
        Write-Host "  [Prereqs] WOULD install fzf via Scoop" -ForegroundColor Yellow
    }
}
else {
    Write-Host "  [Prereqs] fzf already available: $($fzfCmd.Source)" -ForegroundColor Green
}

Write-Host ""

# --- Step 2: Install modules ---
$ModuleList = @(
    @{ Name="PSReadLine";        Reason="Bash-inspired readline, history, reverse search" },
    @{ Name="posh-git";          Reason="Git/PowerShell integration, branch in prompt" },
    @{ Name="oh-my-posh";        Reason="Prompt theme engine (Posh-Git, icons)" },
    @{ Name="PSFzf";             Reason="Fuzzy file finder (fzf wrapper) for PowerShell" },
    @{ Name="Terminal-Icons";    Reason="File and folder icons in terminal" },
    @{ Name="z";                 Reason="Directory jumper (z, jump to frequent dirs)" },
    @{ Name="PSColor";           Reason="Colorized ls/dir output" },
    @{ Name="PowerLS";           Reason="Enhanced Get-ChildItem with colors" },
    @{ Name="Get-ChildItemColor";Reason="Color-coded directory listing" },
    @{ Name="PSZoom";            Reason="Zoom (video) meeting management" },
    @{ Name="PSWindowsUpdate";   Reason="Windows Update cmdlets from PowerShell" },
    @{ Name="PSPKI";             Reason="PKI/Certificate management" },
    @{ Name="Carbon";            Reason="Windows system administration toolkit" },
    @{ Name="DSInternals";       Reason="Active Directory internals and forensics" },
    @{ Name="InvokeBuild";       Reason="Build and test automation" },
    @{ Name="ThreadJob";         Reason="Thread-based concurrent jobs (AllowClobber)" },
    @{ Name="PSScriptAnalyzer";  Reason="Static analysis and code quality checks" },
    @{ Name="BurntToast";        Reason="Windows 10/11 toast notifications" },
    @{ Name="Pode";              Reason="Cross-platform web server framework" }
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
        Write-Host "  SKIP  $name (already installed)" -ForegroundColor DarkGray
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
Write-Host "  Note: PESecurity removed - repo archived on GitHub" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Done. Restart PowerShell for all modules to take effect." -ForegroundColor Cyan
Write-Host ""
