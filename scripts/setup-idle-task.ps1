# setup-idle-task.ps1
# One-time setup script. Run as Administrator on the dev VM.
# Creates the idle-shutdown directory, copies scripts, and registers the scheduled task.
#
# Usage: .\setup-idle-task.ps1 -Region ap-south-1 -ProjectName unity-dev

param(
    [Parameter(Mandatory=$true)]
    [string]$Region,

    [Parameter(Mandatory=$true)]
    [string]$ProjectName
)

$InstallDir = "C:\idle-shutdown"
$ScriptSource = $PSScriptRoot  # Assumes scripts are in the same directory

Write-Host "=== Dev Machine: Idle Shutdown Setup ===" -ForegroundColor Cyan
Write-Host "  Region:  $Region"
Write-Host "  Project: $ProjectName"
Write-Host ""

# Create install directory
if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Write-Host "Created $InstallDir" -ForegroundColor Green
}

# Write config file
$config = @{
    Region      = $Region
    ProjectName = $ProjectName
} | ConvertTo-Json
$config | Out-File -FilePath "$InstallDir\config.json" -Encoding UTF8 -Force
Write-Host "Wrote config to $InstallDir\config.json" -ForegroundColor Green

# Copy scripts
Copy-Item "$ScriptSource\idle-shutdown.ps1" "$InstallDir\idle-shutdown.ps1" -Force
Copy-Item "$ScriptSource\keep-alive.ps1" "$InstallDir\keep-alive.ps1" -Force
Write-Host "Copied scripts to $InstallDir" -ForegroundColor Green

# Create keep-alive.cmd wrapper for easy CLI use
$wrapperContent = @"
@echo off
powershell.exe -ExecutionPolicy Bypass -File "C:\idle-shutdown\keep-alive.ps1" %*
"@
$wrapperContent | Out-File -FilePath "$InstallDir\keep-alive.cmd" -Encoding ASCII -Force
Write-Host "Created keep-alive.cmd wrapper" -ForegroundColor Green

# Add to system PATH if not already there
$currentPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
if ($currentPath -notlike "*$InstallDir*") {
    [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$InstallDir", "Machine")
    Write-Host "Added $InstallDir to system PATH" -ForegroundColor Green
} else {
    Write-Host "$InstallDir already in PATH" -ForegroundColor Yellow
}

# Remove existing scheduled task if it exists
$taskName = "IdleShutdown"
$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Host "Removed existing $taskName task" -ForegroundColor Yellow
}

# Create scheduled task that runs every 5 minutes
$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$InstallDir\idle-shutdown.ps1`""

$trigger = New-ScheduledTaskTrigger -AtStartup
# Set repetition to every 5 minutes indefinitely
$trigger.Repetition = (New-ScheduledTaskTrigger -Once -At "00:00" -RepetitionInterval (New-TimeSpan -Minutes 5)).Repetition

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

Register-ScheduledTask `
    -TaskName $taskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -User "SYSTEM" `
    -RunLevel Highest `
    -Description "Checks for user inactivity and stops the machine after 1 hour idle" | Out-Null

Write-Host "Registered scheduled task: $taskName (runs every 5 minutes)" -ForegroundColor Green

# Initialize log
"$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Idle shutdown setup completed. Region=$Region, Project=$ProjectName" | Out-File -FilePath "$InstallDir\idle-shutdown.log" -Force

Write-Host ""
Write-Host "=== Setup Complete ===" -ForegroundColor Cyan
Write-Host "  Idle detection: Machine stops after 1 hour of inactivity"
Write-Host "  Keep-alive:     keep-alive 3h --pin <your-pin>"
Write-Host "  Cancel:         keep-alive off --pin <your-pin>"
Write-Host "  Logs:           $InstallDir\idle-shutdown.log"
Write-Host ""
Write-Host "NOTE: Open a new terminal for keep-alive command to work (PATH updated)." -ForegroundColor Yellow
