###################################################################################################
# Script:        Launch-M365Assessment.ps1
# Author:        Ryan Holderread - Rackspace Technology
# Description:
#   Entry point for M365-QuickAssess. Run this script in any PowerShell version.
#   Handles PS7 install, dependency install, and launches the assessment automatically.
#   Must be run as Administrator or will prompt for elevation.
###################################################################################################

# -------------------------------------------------------------------
# Pinned Graph module version -- increment here to upgrade all Graph modules
# -------------------------------------------------------------------
$GraphVersion = "2.26.1"

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
        Start-Process pwsh -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
        exit
    }

    Write-Host " PowerShell 7 not found. Installing via winget..." -ForegroundColor Yellow

    $winget = Get-Command winget -ErrorAction SilentlyContinue

    if ( $winget )
    {
        winget install --id Microsoft.PowerShell --source winget --silent --accept-package-agreements --accept-source-agreements
        Write-Host " PowerShell 7 installed. Relaunching..." -ForegroundColor Green
        Start-Sleep 5
        Start-Process pwsh -ArgumentList "-NoProfile -ExecutionPolicy Unrestricted -File `"$PSCommandPath`"" -Verb RunAs
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
# Ensure Program Files module path takes precedence
# Strip OneDrive and user-profile module paths to avoid false negatives
# -------------------------------------------------------------------
$programFilesModules = "C:\Program Files\PowerShell\Modules"
$env:PSModulePath    = ( $env:PSModulePath -split ";" | Where-Object { $_ -eq $programFilesModules -or $_ -like "C:\Program Files*" -or $_ -like "C:\Windows*"} ) -join ";"

if ( $env:PSModulePath -notlike "*$programFilesModules*" )
{
    $env:PSModulePath = $programFilesModules + ";" + $env:PSModulePath
}

Write-Host ""
Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host " M365-QuickAssess - Setup and Launch" -ForegroundColor Cyan
Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host ""

# -------------------------------------------------------------------
# Flag file sentinel -- prevents relaunch loop after dependency install
# -------------------------------------------------------------------
$flagFile        = "$env:TEMP\M365-QuickAssess-Setup.tag"
$setupAlreadyRan = Test-Path $flagFile

# -------------------------------------------------------------------
# Module lists -- defined here so both install and summary can access them
# -------------------------------------------------------------------
$graphModules = @(
    'Microsoft.Graph.Authentication',
    'Microsoft.Graph.Users',
    'Microsoft.Graph.Groups',
    'Microsoft.Graph.Identity.DirectoryManagement',
    'Microsoft.Graph.Identity.SignIns',
    'Microsoft.Graph.Applications',
    'Microsoft.Graph.Reports',
    'Microsoft.Graph.DeviceManagement',
    'Microsoft.Graph.DeviceManagement.Administration',
    'Microsoft.Graph.Devices.CorporateManagement',
    'Microsoft.Graph.Security',
    'Microsoft.Graph.Teams'
)

$otherModules = @(
    'Microsoft.Online.SharePoint.PowerShell',
    'Az.Accounts',
    'Az.Resources'
)

# -------------------------------------------------------------------
# Install dependencies
# -------------------------------------------------------------------
$anyInstalled = $false

if ( -not $setupAlreadyRan )
{
    # -------------------------------------------------------------------
    # Remove any Graph modules from Program Files that don't match pinned version
    # -------------------------------------------------------------------
    Write-Host ""
    Write-Host " Verifying Graph module dependencies..." -ForegroundColor Cyan
    Write-Host " All modules are published by Microsoft and installed from the PowerShell Gallery." -ForegroundColor DarkGray
    Write-Host ""

    Get-Module Microsoft.Graph.* -ListAvailable |
        Where-Object {
            $_.ModuleBase -like "C:\Program Files\PowerShell\Modules*" -and
            $_.Version -ne $GraphVersion
        } |
        ForEach-Object {
            Write-Host " Removing $( $_.Name ) $( $_.Version ) -- replacing with $GraphVersion..." -ForegroundColor Yellow
            Uninstall-Module $_.Name -RequiredVersion $_.Version -Force -ErrorAction SilentlyContinue
        }

    foreach ( $m in $graphModules )
    {
        $existing = Get-Module $m -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1

        if ( -not ( Get-Module $m -ListAvailable | Where-Object {
            $_.ModuleBase -like "C:\Program Files\PowerShell\Modules*" -and
            $_.Version -eq $GraphVersion
        } ) )
        {
            if ( $existing )
            {
                Write-Host " Installing $m $GraphVersion -- found $( $existing.Version ) at $( $existing.ModuleBase ), installing to C:\Program Files\PowerShell\Modules..." -ForegroundColor Yellow
            }
            else
            {
                Write-Host " Installing $m $GraphVersion -- not found on this machine, installing to C:\Program Files\PowerShell\Modules..." -ForegroundColor Yellow
            }

            Install-Module $m -RequiredVersion $GraphVersion -Scope AllUsers -Force -AllowClobber -SkipPublisherCheck -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            $anyInstalled = $true
        }
    }

    foreach ( $m in $otherModules )
    {
        $existing = Get-Module $m -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1

        $installedInPS7 = Get-Module $m -ListAvailable | Where-Object {
            $_.ModuleBase -like "C:\Program Files\PowerShell\Modules*"
        } | Select-Object -First 1

        if ( -not $installedInPS7 )
        {
            if ( $existing )
            {
                Write-Host " Installing $m -- found $( $existing.Version ) at $( $existing.ModuleBase ), installing to C:\Program Files\PowerShell\Modules..." -ForegroundColor Yellow
            }
            else
            {
                Write-Host " Installing $m -- not found on this machine, installing to C:\Program Files\PowerShell\Modules..." -ForegroundColor Yellow
            }

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
    if ( -not ( Get-Module M365-QuickAssess -ListAvailable | Where-Object {
        $_.ModuleBase -like "C:\Program Files\PowerShell\Modules*"
    } ) )
    {
        Write-Host " Installing M365-QuickAssess -- not found in C:\Program Files\PowerShell\Modules, installing..." -ForegroundColor Yellow
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
Write-Host " Loading Graph modules..." -ForegroundColor Cyan

Import-Module M365-QuickAssess -Force
Invoke-M365QuickAssess

# -------------------------------------------------------------------
# Done
# -------------------------------------------------------------------
Write-Host ""
Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host " Assessment Complete" -ForegroundColor Green
Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host " Please email both the JSON and log files from:" -ForegroundColor White
Write-Host " C:\ProgramData\Rackspace-Technology" -ForegroundColor Yellow
Write-Host " to your Rackspace Solutions Architect for review." -ForegroundColor White
Write-Host ""
Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host " Modules Installed by This Tool" -ForegroundColor Cyan
Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host " The following modules were installed to C:\Program Files\PowerShell\Modules:" -ForegroundColor White
Write-Host ""

foreach ( $m in $graphModules )
{
    Write-Host "   $m $GraphVersion" -ForegroundColor DarkGray
}

Write-Host "   ExchangeOnlineManagement 3.8.0" -ForegroundColor DarkGray
Write-Host "   Microsoft.Online.SharePoint.PowerShell" -ForegroundColor DarkGray
Write-Host "   Az.Accounts" -ForegroundColor DarkGray
Write-Host "   Az.Resources" -ForegroundColor DarkGray
Write-Host "   M365-QuickAssess" -ForegroundColor DarkGray
Write-Host ""
Write-Host " To manually remove any of these modules run:" -ForegroundColor White
Write-Host ""

foreach ( $m in $graphModules )
{
    Write-Host "   Uninstall-Module $m -RequiredVersion $GraphVersion -Force" -ForegroundColor Cyan
}

Write-Host "   Uninstall-Module ExchangeOnlineManagement -RequiredVersion 3.8.0 -Force" -ForegroundColor Cyan
Write-Host "   Uninstall-Module Microsoft.Online.SharePoint.PowerShell -Force" -ForegroundColor Cyan
Write-Host "   Uninstall-Module Az.Accounts -Force" -ForegroundColor Cyan
Write-Host "   Uninstall-Module Az.Resources -Force" -ForegroundColor Cyan
Write-Host "   Uninstall-Module M365-QuickAssess -Force" -ForegroundColor Cyan
Write-Host ""
Write-Host " Note: Having multiple versions of the same Graph modules across different" -ForegroundColor Yellow
Write-Host " scopes can cause assembly conflicts in new PowerShell sessions." -ForegroundColor Yellow
Write-Host ""
Read-Host " Press Enter to exit"
PAUSE