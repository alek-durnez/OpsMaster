<#
    .SYNOPSIS
    OpsMaster v5.0 - Hybrid Software Manager (Direct + Chocolatey)
#>

# INITIALIZATION

$ErrorActionPreference = "Stop"
$SettingsFile = "$PSScriptRoot\settings.json"

# 1. Load Configuration
if (-not (Test-Path $SettingsFile)) {
    Write-Error "CRITICAL: Missing settings.json. Aborting."
    exit 1
}

try {
    $Global:Config = Get-Content $SettingsFile | ConvertFrom-Json
} catch {
    Write-Error "CRITICAL: Malformed settings.json."
    exit 1
}

# 2. Resolve Paths
$BlueprintFile = if ([System.IO.Path]::IsPathRooted($Global:Config.BlueprintPath)) { $Global:Config.BlueprintPath } else { Join-Path $PSScriptRoot $Global:Config.BlueprintPath }
$SecretFile    = if ([System.IO.Path]::IsPathRooted($Global:Config.SecretsPath))   { $Global:Config.SecretsPath }   else { Join-Path $PSScriptRoot $Global:Config.SecretsPath }
$LogFile       = $Global:Config.LogPath

# 3. Load Secrets
$WebhookURL = ""
if (Test-Path $SecretFile) {
    try {
        $Secrets = Get-Content $SecretFile | ConvertFrom-Json
        $WebhookURL = $Secrets.DiscordWebhook
    } catch {
        Write-Warning "Failed to parse secrets.json. Alerting disabled."
    }
}

# FUNCTIONS

function Send-Notification {
    param([string]$Message)

    if ([string]::IsNullOrWhiteSpace($WebhookURL)) { return }

    try {
        $Payload = @{ content = "🤖 **OpsMaster:** $Message" }
        Invoke-RestMethod -Uri $WebhookURL -Method Post -Body ($Payload | ConvertTo-Json) -ContentType 'application/json' -ErrorAction Stop
    } catch {
        Write-Warning "Failed to send alert: $_"
    }
}

function Write-Log {
    param(
        [string]$Message,
        [string]$Color = "White",
        [switch]$Alert
    )

    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogLine   = "[$TimeStamp] $Message"

    # Console Output
    Write-Host $LogLine -ForegroundColor $Color

    # File Logging
    try {
        $LogDir = Split-Path $LogFile
        if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
        Add-Content -Path $LogFile -Value $LogLine
    } catch {
        Write-Warning "Log write failed: $_"
    }

    # ChatOps Notification
    if ($Alert -and $Global:Config.Notifications.Enabled) {
        Send-Notification -Message $Message
    }
}

function Ensure-Chocolatey {
    # Check if 'choco' command exists
    if (Get-Command "choco" -ErrorAction SilentlyContinue) { return }

    Write-Log "BOOTSTRAP: Chocolatey package manager not found. Installing..." "Yellow"
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1')) | Out-Null
        
        # Reload Env Vars so we can use it immediately without restarting script
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        Write-Log "BOOTSTRAP: Chocolatey installed successfully." "Green"
    } catch {
        Write-Log "ERROR: Failed to bootstrap Chocolatey. $_" "Red"
    }
}

function Assert-Software {
    param($Item)

    # BRANCH A: Chocolatey Package
    if ($Item.Provider -eq "Chocolatey") {
        Ensure-Chocolatey
        
        $Pkg = $Item.PackageId
        # Check if installed locally
        $Installed = choco list --local-only --limit-output | Select-String -Pattern "^$Pkg\|"
        
        if ($Installed) {
            Write-Log "OK: Chocolatey package '$Pkg' is installed." "Green"
        } else {
            Write-Log "DRIFT: Package '$Pkg' missing. Installing via Chocolatey..." "Yellow"
            try {
                choco install $Pkg -y --no-progress
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "FIXED: Chocolatey installed '$Pkg'." "Green" -Alert
                } else {
                    Write-Log "ERROR: Chocolatey failed to install '$Pkg'." "Red"
                }
            } catch {
                Write-Log "ERROR: Choco execution failed." "Red"
            }
        }
    }

    # BRANCH B: Direct Download (Legacy)
    elseif ($Item.Provider -eq "Direct") {
        if (Test-Path $Item.CheckPath) {
            Write-Log "OK: Software '$($Item.Name)' is installed." "Green"
            return
        }

        Write-Log "DRIFT: Software '$($Item.Name)' missing. Downloading..." "Yellow"
        $TempInstaller = "$env:TEMP\$($Item.Name)-Install.exe"
        
        try {
            # Download
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $Item.Url -OutFile $TempInstaller -UseBasicParsing
            
            # Install
            Write-Log "Installing..." "Cyan"
            $Process = Start-Process -FilePath $TempInstaller -ArgumentList $Item.SilentArgs -Wait -PassThru -WindowStyle Hidden
            
            # Verify
            if ($Process.ExitCode -eq 0) {
                Write-Log "FIXED: Installed '$($Item.Name)'." "Green" -Alert
            } else {
                Write-Log "ERROR: Install failed (Code: $($Process.ExitCode))." "Red"
            }
        } catch {
            Write-Log "ERROR: Direct install failed for $($Item.Name). $_" "Red"
        } finally {
            if (Test-Path $TempInstaller) { Remove-Item $TempInstaller -Force -ErrorAction SilentlyContinue }
        }
    }
}

function Assert-Service {
    param($Name, $DesiredState)

    $Service = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $Service) {
        Write-Log "SKIP: Service '$Name' not found on system." "Gray"
        return
    }

    if ($Service.Status -ne $DesiredState) {
        Write-Log "DRIFT: Service '$Name' is $($Service.Status). Enforcing $DesiredState..." "Yellow"
        try {
            if ($DesiredState -eq "Running") { Start-Service $Name } else { Stop-Service $Name }
            Write-Log "FIXED: Service '$Name' is now $DesiredState." "Green" -Alert
        } catch {
            Write-Log "ERROR: Access denied managing '$Name'. Require Elevation." "Red"
        }
    } else {
        Write-Log "OK: Service '$Name' is $DesiredState." "Green"
    }
}

function Assert-File {
    param($Path, $Content)

    if (-not (Test-Path $Path)) {
        Write-Log "DRIFT: File '$Path' missing. Creating..." "Yellow"
        
        $Dir = Split-Path $Path
        if (-not (Test-Path $Dir)) { New-Item -Path $Dir -ItemType Directory -Force | Out-Null }
        
        Set-Content -Path $Path -Value $Content
        Write-Log "FIXED: Created file '$Path'." "Green" -Alert
    } else {
        $CurrentContent = Get-Content $Path -Raw
        if ($CurrentContent.Trim() -ne $Content.Trim()) {
            Write-Log "DRIFT: File '$Path' content mismatch. Remedying..." "Yellow"
            Set-Content -Path $Path -Value $Content
            Write-Log "FIXED: Restored content for '$Path'." "Green" -Alert
        } else {
            Write-Log "OK: File '$Path' is compliant." "Green"
        }
    }
}

function Assert-Registry {
    param($Path, $Name, $Value)

    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }

    $Current = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue

    if (-not $Current) {
        Write-Log "DRIFT: Registry Key '$Name' missing. Creating..." "Yellow"
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType String | Out-Null
        Write-Log "FIXED: Created Registry Key '$Name'." "Green" -Alert
    } elseif ($Current.$Name -ne $Value) {
        Write-Log "DRIFT: Registry '$Name' value incorrect. Correcting..." "Yellow"
        Set-ItemProperty -Path $Path -Name $Name -Value $Value
        Write-Log "FIXED: Updated Registry Key '$Name'." "Green" -Alert
    } else {
        Write-Log "OK: Registry '$Name' is compliant." "Green"
    }
}

#EXECUTION ENGINE

Write-Host "`nPSMASTER v5.0" -ForegroundColor Cyan

if (-not (Test-Path $BlueprintFile)) {
    Write-Error "Blueprint definition not found at: $BlueprintFile"
    exit 1
}

$Blueprint = Get-Content $BlueprintFile | ConvertFrom-Json
Write-Log "Target: $($Blueprint.ServerName)" "Cyan"
Write-Log "Starting compliance scan...`n"

# Resource Loop
# pass the whole $item object to Assert-Software now
if ($Blueprint.Config.Software) { 
    foreach ($item in $Blueprint.Config.Software) { 
        Assert-Software -Item $item 
    } 
}

if ($Blueprint.Config.Registry) { 
    foreach ($item in $Blueprint.Config.Registry) { 
        Assert-Registry $item.Path $item.Name $item.Value 
    } 
}

if ($Blueprint.Config.Files) { 
    foreach ($item in $Blueprint.Config.Files) { 
        Assert-File $item.Path $item.Content 
    } 
}

if ($Blueprint.Config.Services) { 
    foreach ($item in $Blueprint.Config.Services) { 
        Assert-Service $item.Name $item.State 
    } 
}

Write-Log "`nScan Complete." "Cyan"