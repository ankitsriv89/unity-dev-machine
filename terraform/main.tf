terraform {
  backend "s3" {
    bucket  = ""  # Your S3 bucket for Terraform state
    key     = ""  # e.g., "unity-dev/terraform.tfstate"
    region  = ""  # e.g., "ap-south-1"
    encrypt = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

locals {
  instance_name = "${var.project_name}-machine"
}

# --- Data sources ---

data "aws_ami" "windows_nvidia" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# --- Security Group ---

resource "aws_security_group" "unity_dev" {
  name        = "${var.project_name}-sg"
  description = "Allow RDP, NICE DCV, and Parsec for ${local.instance_name}"

  # RDP
  ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["${var.my_ip}/32"]
    description = "RDP from my IP"
  }

  # NICE DCV
  ingress {
    from_port   = 8443
    to_port     = 8443
    protocol    = "tcp"
    cidr_blocks = ["${var.my_ip}/32"]
    description = "NICE DCV from my IP"
  }

  # Parsec
  ingress {
    from_port   = 8000
    to_port     = 8100
    protocol    = "udp"
    cidr_blocks = ["${var.my_ip}/32"]
    description = "Parsec from my IP"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound"
  }

  tags = {
    Name    = "${var.project_name}-sg"
    Project = var.project_name
  }
}

# --- Key Pair ---

resource "aws_key_pair" "unity_dev" {
  key_name   = "${var.project_name}-key"
  public_key = file(var.public_key_path)

  tags = {
    Project = var.project_name
  }
}

# --- IAM Role (allows instance to read NVIDIA driver bucket) ---

resource "aws_iam_role" "unity_dev" {
  name = "${var.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = { Project = var.project_name }
}

resource "aws_iam_role_policy" "nvidia_s3_read" {
  name = "nvidia-driver-s3-read"
  role = aws_iam_role.unity_dev.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:ListBucket"]
      Resource = [
        "arn:aws:s3:::ec2-windows-nvidia-drivers",
        "arn:aws:s3:::ec2-windows-nvidia-drivers/*"
      ]
    }]
  })
}

resource "aws_iam_role_policy" "idle_shutdown" {
  name = "idle-shutdown-permissions"
  role = aws_iam_role.unity_dev.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["ssm:GetParameter"]
        Resource = [
          "arn:aws:ssm:${var.region}:*:parameter/${var.project_name}/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:CreateTags", "ec2:DeleteTags"]
        Resource = "arn:aws:ec2:${var.region}:*:instance/*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/Project" = var.project_name
          }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = "arn:aws:sns:${var.region}:*:${var.project_name}-auto-stop-alerts"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "unity_dev" {
  name = "${var.project_name}-profile"
  role = aws_iam_role.unity_dev.name
}

# --- EBS Volume (persistent, survives instance stop/terminate) ---

resource "aws_ebs_volume" "unity_data" {
  availability_zone = "${var.region}a"
  size              = 100
  type              = "gp3"
  iops              = 3000
  throughput        = 125

  tags = {
    Name    = "${var.project_name}-data"
    Project = var.project_name
  }
}

# --- EC2 Instance ---

resource "aws_instance" "unity_dev" {
  ami                    = var.ami_id != "" ? var.ami_id : data.aws_ami.windows_nvidia.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.unity_dev.key_name
  vpc_security_group_ids = [aws_security_group.unity_dev.id]
  availability_zone      = "${var.region}a"
  iam_instance_profile   = aws_iam_instance_profile.unity_dev.name

  # Set admin password and install idle-shutdown at boot
  user_data = <<-EOF
    <powershell>
    net user Administrator "${var.windows_password}"

    # --- Idle Shutdown Setup ---
    $installDir = "C:\idle-shutdown"
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null

    # Write idle-shutdown.ps1
    @'
${file("${path.module}/../scripts/idle-shutdown.ps1")}
'@ | Out-File -FilePath "$installDir\idle-shutdown.ps1" -Encoding UTF8 -Force

    # Write keep-alive.ps1
    @'
${file("${path.module}/../scripts/keep-alive.ps1")}
'@ | Out-File -FilePath "$installDir\keep-alive.ps1" -Encoding UTF8 -Force

    # Create keep-alive.cmd wrapper
    '@echo off
    powershell.exe -ExecutionPolicy Bypass -File "C:\idle-shutdown\keep-alive.ps1" %*' | Out-File -FilePath "$installDir\keep-alive.cmd" -Encoding ASCII -Force

    # Add to PATH
    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
    if ($currentPath -notlike "*$installDir*") {
        [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$installDir", "Machine")
    }

    # Register scheduled task
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$installDir\idle-shutdown.ps1`""
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $trigger.Repetition = (New-ScheduledTaskTrigger -Once -At "00:00" -RepetitionInterval (New-TimeSpan -Minutes 5)).Repetition
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
    Register-ScheduledTask -TaskName "IdleShutdown" -Action $action -Trigger $trigger -Settings $settings -User "SYSTEM" -RunLevel Highest -Description "Auto-stop after 1hr idle" -Force | Out-Null
    </powershell>
  EOF

  # Root volume (Windows OS)
  root_block_device {
    volume_size = 80
    volume_type = "gp3"
    encrypted   = true
  }

  lifecycle {
    ignore_changes = [user_data, tags]
  }

  tags = {
    Name    = local.instance_name
    Project = var.project_name
  }
}

# Attach persistent data volume
resource "aws_volume_attachment" "unity_data" {
  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.unity_data.id
  instance_id = aws_instance.unity_dev.id
}

# --- Spot Instance Alternative (uncomment to use instead of on-demand) ---

# resource "aws_spot_instance_request" "unity_dev_spot" {
#   ami                    = data.aws_ami.windows_nvidia.id
#   instance_type          = var.instance_type
#   key_name               = aws_key_pair.unity_dev.key_name
#   vpc_security_group_ids = [aws_security_group.unity_dev.id]
#   availability_zone      = "${var.region}a"
#   spot_price             = var.spot_max_price
#   wait_for_fulfillment   = true
#   spot_type              = "one-time"
#
#   root_block_device {
#     volume_size = 50
#     volume_type = "gp3"
#     encrypted   = true
#   }
#
#   tags = {
#     Name    = "${var.project_name}-spot"
#     Project = var.project_name
#   }
# }
