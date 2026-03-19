# keep-alive.ps1
# Extends auto-stop/terminate timers. Requires PIN authentication.
# Usage: keep-alive 3h --pin 1234
#        keep-alive off --pin 1234

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$Duration,

    [Parameter(Mandatory=$true)]
    [string]$Pin
)

$KeepAliveFile = "C:\idle-shutdown\KEEP_ALIVE"
$LogFile = "C:\idle-shutdown\idle-shutdown.log"
$ConfigFile = "C:\idle-shutdown\config.json"

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -Append -FilePath $LogFile
}

# Load config
if (-not (Test-Path $ConfigFile)) {
    Write-Host "ERROR: Config file not found. Run setup-idle-task.ps1 first." -ForegroundColor Red
    exit 1
}
$config = Get-Content $ConfigFile -Raw | ConvertFrom-Json
$Region = $config.Region
$ProjectName = $config.ProjectName

# Validate PIN against SSM Parameter Store
function Test-Pin {
    param([string]$InputPin)
    try {
        $storedPin = aws ssm get-parameter --name "/$ProjectName/keep-alive-pin" --with-decryption --region $Region --query "Parameter.Value" --output text 2>$null
        return ($InputPin -eq $storedPin)
    } catch {
        Write-Host "ERROR: Could not verify PIN. Check AWS connectivity and IAM permissions." -ForegroundColor Red
        return $false
    }
}

# Get this instance's ID from metadata
function Get-InstanceId {
    try {
        $token = Invoke-RestMethod -Uri "http://169.254.169.254/latest/api/token" -Method PUT -Headers @{"X-aws-ec2-metadata-token-ttl-seconds"="21600"} -TimeoutSec 2
        $instanceId = Invoke-RestMethod -Uri "http://169.254.169.254/latest/meta-data/instance-id" -Headers @{"X-aws-ec2-metadata-token"=$token} -TimeoutSec 2
        return $instanceId
    } catch {
        Write-Host "ERROR: Could not get instance ID from metadata." -ForegroundColor Red
        return $null
    }
}

# Validate PIN
if (-not (Test-Pin $Pin)) {
    Write-Host "ERROR: Invalid PIN." -ForegroundColor Red
    Write-Log "Keep-alive REJECTED: invalid PIN attempt."
    exit 1
}

$instanceId = Get-InstanceId
if (-not $instanceId) { exit 1 }

# Handle "off" command
if ($Duration -eq "off") {
    if (Test-Path $KeepAliveFile) {
        Remove-Item $KeepAliveFile -Force
    }
    aws ec2 delete-tags --resources $instanceId --tags "Key=KeepAliveUntil" --region $Region 2>$null
    Write-Host "Keep-alive cancelled. Normal auto-stop/terminate timers restored." -ForegroundColor Yellow
    Write-Log "Keep-alive cancelled by user."
    exit 0
}

# Parse duration (e.g., "3h", "90m", "2h30m")
$totalMinutes = 0
if ($Duration -match "^(\d+)h$") {
    $totalMinutes = [int]$Matches[1] * 60
} elseif ($Duration -match "^(\d+)m$") {
    $totalMinutes = [int]$Matches[1]
} elseif ($Duration -match "^(\d+)h(\d+)m$") {
    $totalMinutes = [int]$Matches[1] * 60 + [int]$Matches[2]
} else {
    Write-Host "ERROR: Invalid duration format. Use: 3h, 90m, or 2h30m" -ForegroundColor Red
    exit 1
}

if ($totalMinutes -lt 1 -or $totalMinutes -gt 720) {
    Write-Host "ERROR: Duration must be between 1m and 12h (720m)." -ForegroundColor Red
    exit 1
}

# Set keep-alive expiry
$expiry = (Get-Date).ToUniversalTime().AddMinutes($totalMinutes)
$expiryIso = $expiry.ToString("yyyy-MM-ddTHH:mm:ssZ")

# Write local file (for idle-shutdown.ps1)
$expiryIso | Out-File -FilePath $KeepAliveFile -Force

# Set EC2 tag (for Lambda hard cap)
aws ec2 create-tags --resources $instanceId --tags "Key=KeepAliveUntil,Value=$expiryIso" --region $Region 2>$null

Write-Host "Keep-alive activated until $expiryIso ($totalMinutes minutes)." -ForegroundColor Green
Write-Host "Auto-stop and auto-terminate are paused until then." -ForegroundColor Green
Write-Host "To cancel: keep-alive off --pin <your-pin>" -ForegroundColor Cyan
Write-Log "Keep-alive activated until $expiryIso ($totalMinutes minutes)."
