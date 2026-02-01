#INITIALIZATION

$ErrorActionPreference = "Stop"
$SettingsFile = "$PSScriptRoot\settings.json"

# Load Configuration
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

# Resolve Paths
$BlueprintFile = if ([System.IO.Path]::IsPathRooted($Global:Config.BlueprintPath)) { $Global:Config.BlueprintPath } else { Join-Path $PSScriptRoot $Global:Config.BlueprintPath }
$SecretFile    = if ([System.IO.Path]::IsPathRooted($Global:Config.SecretsPath))   { $Global:Config.SecretsPath }   else { Join-Path $PSScriptRoot $Global:Config.SecretsPath }
$LogFile       = $Global:Config.LogPath

# Load Secrets (Fail gracefully if missing)
$WebhookURL = ""
if (Test-Path $SecretFile) {
    try {
        $Secrets = Get-Content $SecretFile | ConvertFrom-Json
        $WebhookURL = $Secrets.DiscordWebhook
    } catch {
        Write-Warning "Failed to parse secrets.json. Alerting disabled."
    }
}

#FUNCTIONS

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

function Assert-Software {
    param($Name, $CheckPath, $Url, $SilentArgs)

    if (Test-Path $CheckPath) {
        Write-Log "OK: Software '$Name' is installed." "Green"
        return
    }

    Write-Log "DRIFT: Software '$Name' missing. Initiating install..." "Yellow"
    
    $TempInstaller = "$env:TEMP\$Name-Install.exe"
    
    try {
        # Download
        Write-Log "Downloading payload from $Url..." "Cyan"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $Url -OutFile $TempInstaller -UseBasicParsing
        
        # Install
        Write-Log "Executing silent installer..." "Cyan"
        $Process = Start-Process -FilePath $TempInstaller -ArgumentList $SilentArgs -Wait -PassThru -WindowStyle Hidden
        
        # Verify
        if ($Process.ExitCode -eq 0 -and (Test-Path $CheckPath)) {
            Write-Log "FIXED: Installed '$Name' successfully." "Green" -Alert
        } else {
            Write-Log "ERROR: Installation '$Name' failed. Exit Code: $($Process.ExitCode)" "Red"
        }
    } catch {
        Write-Log "ERROR: Deployment failed for '$Name'. Exception: $_" "Red"
    } finally {
        if (Test-Path $TempInstaller) { Remove-Item $TempInstaller -Force -ErrorAction SilentlyContinue }
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
        $CurrentHash = Get-FileHash -Path $Path -Algorithm MD5
        # Simple content comparison for text files
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

Write-Host "`n=== OPSMASTER v4.1 ===" -ForegroundColor Cyan

if (-not (Test-Path $BlueprintFile)) {
    Write-Error "Blueprint definition not found at: $BlueprintFile"
    exit 1
}

$Blueprint = Get-Content $BlueprintFile | ConvertFrom-Json
Write-Log "Target: $($Blueprint.ServerName)" "Cyan"
Write-Log "Starting compliance scan...`n"

# Resource Loop
if ($Blueprint.Config.Software) { 
    foreach ($item in $Blueprint.Config.Software) { 
        Assert-Software $item.Name $item.CheckPath $item.Url $item.SilentArgs 
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