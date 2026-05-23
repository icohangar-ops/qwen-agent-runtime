<#
.SYNOPSIS
    Senso Agent Runtime — Windows One-Shot Setup
.DESCRIPTION
    Configures execution policy, installs Python dependencies,
    sets up config, and optionally adds Windows Defender exclusions.
#>

param(
    [string]$AgentId = "laptop-primary",
    [string]$Role = "primary"
)

$ErrorActionPreference = "Stop"
Write-Host "`n=== Senso Agent Runtime Setup ===" -ForegroundColor Cyan
Write-Host "Agent: $AgentId | Role: $Role`n" -ForegroundColor Cyan

# 1. Execution Policy
Write-Host "[1/5] Setting execution policy..." -ForegroundColor Yellow
$currentPolicy = Get-ExecutionPolicy -Scope CurrentUser
if ($currentPolicy -ne "RemoteSigned" -and $currentPolicy -ne "Unrestricted") {
    Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
    Write-Host "  Set to RemoteSigned" -ForegroundColor Green
} else {
    Write-Host "  Already $currentPolicy — OK" -ForegroundColor Green
}

# 2. Python check
Write-Host "[2/5] Checking Python..." -ForegroundColor Yellow
$pythonCmd = $null
foreach ($cmd in @("python3", "python", "py")) {
    try {
        $version = & $cmd --version 2>&1
        if ($version -match "Python 3\.(1[1-9]|[2-9])") {
            $pythonCmd = $cmd
            Write-Host "  Found: $version" -ForegroundColor Green
            break
        }
    } catch {}
}
if (-not $pythonCmd) {
    Write-Host "  Python 3.11+ not found. Installing..." -ForegroundColor Red
    winget install Python.Python.3.12 --accept-source-agreements --accept-package-agreements
    $pythonCmd = "python"
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
}

# 3. Install dependencies
Write-Host "[3/5] Installing Python dependencies..." -ForegroundColor Yellow
$projectDir = Split-Path -Parent $PSScriptRoot
if (Test-Path "$projectDir\requirements.txt") {
    & $pythonCmd -m pip install -r "$projectDir\requirements.txt" --quiet
    Write-Host "  Dependencies installed" -ForegroundColor Green
} else {
    Write-Host "  requirements.txt not found, skipping" -ForegroundColor Red
}

# 4. Create config from example
Write-Host "[4/5] Setting up config..." -ForegroundColor Yellow
$configDir = "$projectDir\config"
if (!(Test-Path "$configDir\config.yaml")) {
    if (Test-Path "$configDir\config.example.yaml") {
        Copy-Item "$configDir\config.example.yaml" "$configDir\config.yaml"
        Write-Host "  Created config/config.yaml from example" -ForegroundColor Green
        Write-Host "  >>> EDIT config/config.yaml and add your Qwen API key <<<" -ForegroundColor Magenta
    }
} else {
    Write-Host "  config.yaml already exists" -ForegroundColor Green
}

# 5. Create logs directory
Write-Host "[5/5] Setting up directories..." -ForegroundColor Yellow
$logsDir = "$projectDir\logs"
if (!(Test-Path $logsDir)) {
    New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
    Write-Host "  Created logs/" -ForegroundColor Green
}

Write-Host "`n=== Setup Complete ===" -ForegroundColor Cyan
Write-Host @"
Next steps:
  1. Edit config\config.yaml — add your Qwen API key
     Get key: https://dashscope.console.aliyun.com/apiKey
  2. Run: python -m agent.main
  3. (Optional) Add Windows Defender exclusion for the project folder:
     Add-MpPreference -ExclusionPath "$projectDir"
"@ -ForegroundColor White
