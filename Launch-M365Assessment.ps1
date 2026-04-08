###################################################################################################
# Script:        Launch-M365Assessment.ps1
# Author:        Ryan Holderread - Rackspace Technology
# Description:
#   Entry point for M365-QuickAssess. Run this script in any PowerShell version.
#   Handles PS7 install, dependency install, and launches the assessment automatically.
#   Must be run as Administrator or will prompt for elevation.
###################################################################################################

# -------------------------------------------------------------------
# Self-elevate if not running as admin
# -------------------------------------------------------------------
if ( -not ( [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent() ).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator ) )
{
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs -WindowStyle Hidden
    exit
}

# -------------------------------------------------------------------
# If running in PS5, check for PS7 and relaunch or install
# -------------------------------------------------------------------
if ( $PSVersionTable.PSVersion.Major -lt 7 )
{
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue

    if ( $pwsh )
    {
        Write-Host " Relaunching in PowerShell 7..." -ForegroundColor Cyan
        Start-Process pwsh -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs -WindowStyle Normal
        exit
    }

    Write-Host " PowerShell 7 not found. Installing via winget..." -ForegroundColor Yellow

    $winget = Get-Command winget -ErrorAction SilentlyContinue

    if ( $winget )
    {
        winget install --id Microsoft.PowerShell --source winget --silent --accept-package-agreements --accept-source-agreements
        Write-Host " PowerShell 7 installed. Relaunching..." -ForegroundColor Green
        Start-Sleep 5
        Start-Process pwsh -ArgumentList "-NoProfile -ExecutionPolicy Unrestricted -File `"$PSCommandPath`"" -Verb RunAs -WindowStyle Normal
        exit
    }
    else
    {
        Write-Host " winget not available. Please install PowerShell 7 manually: https://aka.ms/powershell" -ForegroundColor Red
        pause
        exit 1
    }
}

# -------------------------------------------------------------------
# Now running in PS7 as admin
# -------------------------------------------------------------------
Write-Host ""
Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host " M365-QuickAssess - Setup and Launch" -ForegroundColor Cyan
Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host ""

# -------------------------------------------------------------------
# Flag file sentinel -- prevents relaunch loop after dependency install
# -------------------------------------------------------------------
$flagFile = "$env:TEMP\M365-QuickAssess-Setup.tag"
$setupAlreadyRan = Test-Path $flagFile

# -------------------------------------------------------------------
# Install dependencies
# -------------------------------------------------------------------
$anyInstalled = $false

if ( -not $setupAlreadyRan )
{
    $modules = @(
        'Microsoft.Graph.Authentication',
        'Microsoft.Graph.Users',
        'Microsoft.Graph.Groups',
        'Microsoft.Graph.Identity.DirectoryManagement',
        'Microsoft.Graph.Identity.SignIns',
        'Microsoft.Graph.Applications',
        'Microsoft.Graph.Reports',
        'Microsoft.Graph.DeviceManagement',
        'Microsoft.Graph.DeviceManagement.Administration',
        'Microsoft.Graph.Security',
        'Microsoft.Graph.Teams',
        'Microsoft.Graph.Devices.CorporateManagement',
        'Microsoft.Online.SharePoint.PowerShell',
        'Az.Accounts',
        'Az.Resources'
    )

    foreach ( $m in $modules )
    {
        if ( -not ( Get-Module $m -ListAvailable ) )
        {
            Write-Host " Installing $m..." -ForegroundColor Yellow
            Install-Module $m -Scope AllUsers -Force -AllowClobber -SkipPublisherCheck -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            $anyInstalled = $true
        }
    }

    # -------------------------------------------------------------------
    # EXO - pinned to 3.8.0
    # -------------------------------------------------------------------
    $exo = Get-Module ExchangeOnlineManagement -ListAvailable | Where-Object { $_.Version -eq '3.8.0' }

    if ( -not $exo )
    {
        Write-Host " Installing ExchangeOnlineManagement 3.8.0..." -ForegroundColor Yellow
        Get-Module ExchangeOnlineManagement -ListAvailable | ForEach-Object {
            Uninstall-Module ExchangeOnlineManagement -RequiredVersion $_.Version -Force -ErrorAction SilentlyContinue
        }
        Install-Module ExchangeOnlineManagement -RequiredVersion 3.8.0 -Scope AllUsers -Force -AllowClobber -SkipPublisherCheck -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        $anyInstalled = $true
    }

    # -------------------------------------------------------------------
    # Install M365-QuickAssess
    # -------------------------------------------------------------------
    if ( -not ( Get-Module M365-QuickAssess -ListAvailable ) )
    {
        Write-Host " Installing M365-QuickAssess..." -ForegroundColor Yellow
        Install-Module M365-QuickAssess -Scope AllUsers -Force -AllowClobber -SkipPublisherCheck -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        $anyInstalled = $true
    }

    # -------------------------------------------------------------------
    # If anything was installed, write flag file and relaunch once
    # -------------------------------------------------------------------
    if ( $anyInstalled )
    {
        New-Item $flagFile -Force | Out-Null
        Write-Host ""
        Write-Host " Dependencies installed. Relaunching..." -ForegroundColor Green
        Start-Sleep 3
        Start-Process pwsh -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
        exit
    }
}

# -------------------------------------------------------------------
# Clean up flag file
# -------------------------------------------------------------------
if ( Test-Path $flagFile )
{
    Remove-Item $flagFile -Force -ErrorAction SilentlyContinue
}

# -------------------------------------------------------------------
# Launch assessment
# -------------------------------------------------------------------
Write-Host " All dependencies present. Starting assessment..." -ForegroundColor Green
Write-Host ""
Write-Host " Loading Graph modules " -ForegroundColor Cyan

Import-Module M365-QuickAssess -Force
Invoke-M365QuickAssess

Write-Host ""
Write-Host " Press any key to exit..." -ForegroundColor Cyan