terraform {
  # Local backend by default. Uncomment below for S3 backend:
  # backend "s3" {
  #   bucket  = ""  # Your S3 bucket for Terraform state
  #   key     = ""  # e.g., "unity-dev/terraform.tfstate"
  #   region  = ""  # e.g., "us-east-1"
  #   encrypt = true
  # }

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
  selected_ami  = var.ami_id != "" ? var.ami_id : data.aws_ami.windows_nvidia.id

  # Default spot prices per instance type; override by setting spot_max_price in tfvars
  spot_price_defaults = {
    "g4dn.xlarge"  = "0.35"
    "g4dn.2xlarge" = "0.55"
  }
  effective_spot_price = var.spot_max_price != "" ? var.spot_max_price : lookup(local.spot_price_defaults, var.instance_type, "0.50")

  user_data = templatefile("${path.module}/userdata.ps1.tftpl", {
    windows_password     = var.windows_password
    idle_shutdown_script = file("${path.module}/../scripts/idle-shutdown.ps1")
    keep_alive_script    = file("${path.module}/../scripts/keep-alive.ps1")
  })
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
    cidr_blocks = [var.my_ip != "" ? "${var.my_ip}/32" : "0.0.0.0/0"]
    description = "RDP from my IP"
  }

  # NICE DCV
  ingress {
    from_port   = 8443
    to_port     = 8443
    protocol    = "tcp"
    cidr_blocks = [var.my_ip != "" ? "${var.my_ip}/32" : "0.0.0.0/0"]
    description = "NICE DCV from my IP"
  }

  # Parsec
  ingress {
    from_port   = 8000
    to_port     = 8100
    protocol    = "udp"
    cidr_blocks = [var.my_ip != "" ? "${var.my_ip}/32" : "0.0.0.0/0"]
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
  size              = 20
  type              = "gp3"
  iops              = 3000
  throughput        = 125

  tags = {
    Name    = "${var.project_name}-data"
    Project = var.project_name
  }
}

# --- EC2 Instance ---
# Choose ONE of the following instance configurations:
#   instance-spot.tf     — Spot instance (cheaper, can be interrupted)
#   instance-ondemand.tf — On-demand instance (reliable, can be stopped/started)
#
# Enable one by renaming it to .tf, disable the other by renaming to .tf.disabled
# By default, spot is enabled.
