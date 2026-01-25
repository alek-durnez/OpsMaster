param (
    [string]$BlueprintFile = "$PSScriptRoot\blueprint.json"
)

$SecretFile = "$PSScriptRoot\secrets.json"

if (Test-Path $SecretFile) {
    $Secrets = Get-Content $SecretFile | ConvertFrom-Json
    $WebhookURL = $Secrets.DiscordWebhook
} else {
    Write-Warning "secrets.json not found! Discord alerts will be disabled."
    $WebhookURL = ""
}


function Send-Notification {
    param($Message)
    
    if ($WebhookURL -match "discord") {
        try {
            $Payload = @{ content = "🤖 **OpsMaster Action:** $Message" }
            
            Invoke-RestMethod -Uri $WebhookURL `
                              -Method Post `
                              -Body ($Payload | ConvertTo-Json) `
                              -ContentType 'application/json'
        } catch {
            Write-Warning "Failed to send Discord alert. Check your Internet or URL."
        }
    }
}

function Write-Log {
    param($Message, $Color="White", $Alert=$false)
    
    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$TimeStamp] $Message" -ForegroundColor $Color
    
    # If this is a FIX ($Alert is true), tell Discord
    if ($Alert) {
        Send-Notification -Message $Message
    }
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
        
        try {
            if ($DesiredState -eq "Running") { Start-Service $Name -ErrorAction Stop }
            elseif ($DesiredState -eq "Stopped") { Stop-Service $Name -ErrorAction Stop }
            
            # $true triggers the Discord Alert
            Write-Log "FIXED: Service '$Name' is now $DesiredState" "Green" $true
        } catch {
            Write-Log "ERROR: Failed to change service '$Name'. Run as Admin!" "Red"
        }
    } else {
        Write-Log "OK: Service '$Name' is $DesiredState" "Green"
    }
}

function Assert-File {
    param($Path, $Content)
    
    if (-not (Test-Path $Path)) {
        Write-Log "DRIFT: File '$Path' is missing. Creating..." "Yellow"
        
        $Dir = Split-Path $Path
        if (-not (Test-Path $Dir)) { New-Item -ItemType Directory -Path $Dir | Out-Null }
        Set-Content -Path $Path -Value $Content
        
        Write-Log "FIXED: File created at $Path" "Green" $true
    } 
    else {
        $CurrentContent = Get-Content $Path -Raw
        if ($CurrentContent.Trim() -ne $Content.Trim()) {
            Write-Log "DRIFT: File '$Path' content mismatch. Overwriting..." "Yellow"
            Set-Content -Path $Path -Value $Content
            
            Write-Log "FIXED: File content corrected." "Green" $true
        } else {
            Write-Log "OK: File '$Path' is compliant" "Green"
        }
    }
}

function Assert-Registry {
    param($Path, $Name, $Value)
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }

    $CurrentValue = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
    
    if (-not $CurrentValue) {
        Write-Log "DRIFT: Registry Key '$Name' missing. Creating..." "Yellow"
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType String | Out-Null
        
        Write-Log "FIXED: Registry Key '$Name' created." "Green" $true
    }
    elseif ($CurrentValue.$Name -ne $Value) {
        Write-Log "DRIFT: Registry '$Name' value incorrect. Fix -> $Value" "Yellow"
        Set-ItemProperty -Path $Path -Name $Name -Value $Value
        
        Write-Log "FIXED: Registry '$Name' value corrected." "Green" $true
    }
    else {
        Write-Log "OK: Registry '$Name' is compliant" "Green"
    }
}

# Main script

Write-Host "`n PSMASTER v2.0" -ForegroundColor Cyan

if (-not (Test-Path $BlueprintFile)) {
    Write-Error "Blueprint not found at: $BlueprintFile"
    exit
}

$Blueprint = Get-Content $BlueprintFile | ConvertFrom-Json
Write-Log "Loaded Configuration: $($Blueprint.ServerName)" "Cyan"
Write-Log "Starting Compliance Scan...`n"

if ($Blueprint.Config.Services) { foreach ($s in $Blueprint.Config.Services) { Assert-Service $s.Name $s.State } }
if ($Blueprint.Config.Files) { foreach ($f in $Blueprint.Config.Files) { Assert-File $f.Path $f.Content } }
if ($Blueprint.Config.Registry) { foreach ($r in $Blueprint.Config.Registry) { Assert-Registry $r.Path $r.Name $r.Value } }

Write-Log "`nScan Complete." "Cyan"