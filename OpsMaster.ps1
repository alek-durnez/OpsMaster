param (
    [string]$BlueprintFile = "$PSScriptRoot\blueprint.json"
)

# helper function

function Write-Log {
    param($Message, $Color="White")
    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$TimeStamp] $Message" -ForegroundColor $Color
}

function Assert-Service {
    param($Name, $DesiredState)
    
    $Service = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $Service) {
        Write-Log "SKIP: Service '$Name' not found." "Gray"
        return
    }

    if ($Service.Status -ne $DesiredState) {
        Write-Log "DRIFT: Service '$Name' is $($Service.Status). Fix -> $DesiredState" "Yellow"
        
        if ($DesiredState -eq "Running") { Start-Service $Name }
        elseif ($DesiredState -eq "Stopped") { Stop-Service $Name }
        
        Write-Log "FIXED: Service '$Name' is now $DesiredState" "Green"
    } else {
        Write-Log "OK: Service '$Name' is $DesiredState" "Green"
    }
}

function Assert-File {
    param($Path, $Content)
    
    # 1. Check if file exists
    if (-not (Test-Path $Path)) {
        Write-Log "DRIFT: File '$Path' is missing. Creating..." "Yellow"
        
        # Ensure directory exists
        $Dir = Split-Path $Path
        if (-not (Test-Path $Dir)) { New-Item -ItemType Directory -Path $Dir | Out-Null }
        
        Set-Content -Path $Path -Value $Content
        Write-Log "FIXED: File created." "Green"
    } 
    # 2. Check content (Idempotency)
    else {
        $CurrentContent = Get-Content $Path -Raw
        if ($CurrentContent.Trim() -ne $Content.Trim()) {
            Write-Log "DRIFT: File '$Path' content mismatch. Overwriting..." "Yellow"
            Set-Content -Path $Path -Value $Content
            Write-Log "FIXED: File content corrected." "Green"
        } else {
            Write-Log "OK: File '$Path' is compliant" "Green"
        }
    }
}

function Assert-Registry {
    param($Path, $Name, $Value)
    
    # Check if Key exists
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }

    $CurrentValue = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
    
    if (-not $CurrentValue) {
        Write-Log "DRIFT: Registry Key '$Name' missing. Creating..." "Yellow"
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType String | Out-Null
        Write-Log "FIXED: Registry Key created." "Green"
    }
    elseif ($CurrentValue.$Name -ne $Value) {
        Write-Log "DRIFT: Registry '$Name' value incorrect. Fix -> $Value" "Yellow"
        Set-ItemProperty -Path $Path -Name $Name -Value $Value
        Write-Log "FIXED: Registry value corrected." "Green"
    }
    else {
        Write-Log "OK: Registry '$Name' is compliant" "Green"
    }
}

# main script

Write-Host "`n=== OPSMASTER ENGINE v1.0 ===" -ForegroundColor Cyan

if (-not (Test-Path $BlueprintFile)) {
    Write-Error "Blueprint not found at: $BlueprintFile"
    exit
}

try {
    $Blueprint = Get-Content $BlueprintFile | ConvertFrom-Json
} catch {
    Write-Error "CRITICAL: Blueprint JSON is invalid."
    exit
}

Write-Log "Loaded Configuration: $($Blueprint.ServerName)" "Cyan"
Write-Log "Starting Compliance Scan...`n"

# 1. Services
if ($Blueprint.Config.Services) {
    foreach ($svc in $Blueprint.Config.Services) {
        Assert-Service -Name $svc.Name -DesiredState $svc.State
    }
}

# 2. Files
if ($Blueprint.Config.Files) {
    foreach ($file in $Blueprint.Config.Files) {
        Assert-File -Path $file.Path -Content $file.Content
    }
}

# 3. Registry
if ($Blueprint.Config.Registry) {
    foreach ($reg in $Blueprint.Config.Registry) {
        Assert-Registry -Path $reg.Path -Name $reg.Name -Value $reg.Value
    }
}

Write-Log "`nScan Complete." "Cyan"