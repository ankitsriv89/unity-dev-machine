# Run as Administrator
# Installs NVIDIA GRID driver for EC2 G4dn instances

Write-Host "Downloading NVIDIA driver from AWS S3..." -ForegroundColor Cyan

$Bucket = "ec2-windows-nvidia-drivers"
$KeyPrefix = "latest"
$LocalPath = "C:\nvidia_driver"

New-Item -Path $LocalPath -ItemType Directory -Force | Out-Null

$Objects = Get-S3Object -BucketName $Bucket -KeyPrefix $KeyPrefix -Region us-east-1
foreach ($Object in $Objects) {
    $FileName = $Object.Key.Substring($KeyPrefix.Length + 1)
    if ($FileName -and $FileName -ne "") {
        Write-Host "Downloading $FileName..."
        Read-S3Object -BucketName $Bucket -Key $Object.Key -File "$LocalPath\$FileName" -Region us-east-1
    }
}

Write-Host "Installing driver silently..." -ForegroundColor Cyan
$Installer = Get-ChildItem -Path $LocalPath -Filter "*.exe" | Select-Object -First 1
& $Installer.FullName -s -noreboot

Write-Host "Done! Rebooting in 10 seconds..." -ForegroundColor Green
Start-Sleep -Seconds 10
Restart-Computer -Force
