# Single instance resource — spot by default, on-demand with -var="on_demand=true"

resource "aws_instance" "unity_dev" {
  ami                    = local.selected_ami
  instance_type          = var.instance_type
  key_name               = aws_key_pair.unity_dev.key_name
  vpc_security_group_ids = [aws_security_group.unity_dev.id]
  availability_zone      = "${var.region}a"
  iam_instance_profile   = aws_iam_instance_profile.unity_dev.name

  dynamic "instance_market_options" {
    for_each = var.on_demand ? [] : [1]
    content {
      market_type = "spot"
      spot_options {
        max_price                      = local.effective_spot_price
        spot_instance_type             = "one-time"
        instance_interruption_behavior = "terminate"
      }
    }
  }

  user_data = local.user_data

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

# --- Outputs ---

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.unity_dev.id
}

output "public_ip" {
  description = "Public IP address (connect via RDP/DCV/Parsec)"
  value       = aws_instance.unity_dev.public_ip
}

output "spot_price" {
  description = "Effective spot price bid (null if on-demand)"
  value       = var.on_demand ? null : local.effective_spot_price
}
