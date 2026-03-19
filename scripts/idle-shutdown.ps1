# idle-shutdown.ps1
# Checks for keyboard/mouse inactivity and stops the machine after 1 hour idle.
# Runs as a scheduled task every 5 minutes.
# Region and project name are read from instance tags via metadata.

$IdleThresholdMinutes = 60
$WarningThresholdMinutes = 45
$LogFile = "C:\idle-shutdown\idle-shutdown.log"
$KeepAliveFile = "C:\idle-shutdown\KEEP_ALIVE"
$ConfigFile = "C:\idle-shutdown\config.json"

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -Append -FilePath $LogFile
}

# Load config (written by setup script)
function Get-Config {
    if (Test-Path $ConfigFile) {
        return Get-Content $ConfigFile -Raw | ConvertFrom-Json
    }
    Write-Log "ERROR: Config file not found at $ConfigFile"
    exit 1
}

$config = Get-Config
$Region = $config.Region
$ProjectName = $config.ProjectName

# Get SNS topic ARN from SSM
function Get-SnsTopicArn {
    try {
        $arn = aws ssm get-parameter --name "/$ProjectName/sns-topic-arn" --region $Region --query "Parameter.Value" --output text 2>$null
        return $arn
    } catch {
        Write-Log "WARNING: Could not fetch SNS topic ARN from SSM"
        return $null
    }
}

# Use Win32 API to detect actual user input idle time
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class IdleDetector {
    [DllImport("user32.dll")]
    static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);

    [StructLayout(LayoutKind.Sequential)]
    struct LASTINPUTINFO {
        public uint cbSize;
        public uint dwTime;
    }

    public static uint GetIdleTimeMs() {
        LASTINPUTINFO lii = new LASTINPUTINFO();
        lii.cbSize = (uint)Marshal.SizeOf(typeof(LASTINPUTINFO));
        GetLastInputInfo(ref lii);
        return ((uint)Environment.TickCount - lii.dwTime);
    }
}
"@

# Check keep-alive file
if (Test-Path $KeepAliveFile) {
    $expiry = Get-Content $KeepAliveFile -Raw | Out-String
    $expiry = $expiry.Trim()
    try {
        $expiryTime = [DateTime]::Parse($expiry).ToUniversalTime()
        $now = (Get-Date).ToUniversalTime()
        if ($now -lt $expiryTime) {
            Write-Log "Keep-alive active until $expiry. Skipping idle check."
            exit 0
        } else {
            Write-Log "Keep-alive expired ($expiry). Removing file."
            Remove-Item $KeepAliveFile -Force
        }
    } catch {
        Write-Log "Invalid keep-alive file content: $expiry. Removing."
        Remove-Item $KeepAliveFile -Force
    }
}

# Get idle time
$idleMs = [IdleDetector]::GetIdleTimeMs()
$idleMinutes = [math]::Round($idleMs / 60000, 1)

Write-Log "Idle time: $idleMinutes minutes"

# Check if past idle threshold -> stop
if ($idleMinutes -ge $IdleThresholdMinutes) {
    Write-Log "IDLE THRESHOLD REACHED ($idleMinutes min >= $IdleThresholdMinutes min). Stopping machine."

    $snsArn = Get-SnsTopicArn
    if ($snsArn) {
        aws sns publish --topic-arn $snsArn --region $Region `
            --subject "Dev Machine STOPPED (idle)" `
            --message "Machine stopped after $idleMinutes minutes of inactivity." 2>$null
    }

    Stop-Computer -Force
    exit 0
}

# Check if in warning window -> send warning
if ($idleMinutes -ge $WarningThresholdMinutes) {
    $warningFile = "C:\idle-shutdown\WARNING_SENT"
    # Only send warning once per idle period
    if (-not (Test-Path $warningFile)) {
        $remaining = $IdleThresholdMinutes - $idleMinutes
        Write-Log "WARNING: Machine will stop in ~$remaining minutes due to inactivity."

        $snsArn = Get-SnsTopicArn
        if ($snsArn) {
            $msg = "Machine will STOP in ~$([math]::Round($remaining)) minutes due to inactivity.`n`nTo extend, run:`n  On VM:    keep-alive 2h --pin <your-pin>`n  Locally:  ./manage.sh extend 2h"
            aws sns publish --topic-arn $snsArn --region $Region `
                --subject "Dev Machine will STOP soon (idle)" `
                --message $msg 2>$null
        }

        # Mark that we sent the warning
        "sent" | Out-File -FilePath $warningFile
    }
} else {
    # User became active again, reset warning
    $warningFile = "C:\idle-shutdown\WARNING_SENT"
    if (Test-Path $warningFile) {
        Remove-Item $warningFile -Force
        Write-Log "User activity detected. Warning reset."
    }
}
