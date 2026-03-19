# Spot Instance — cheaper (~80% savings), but can be interrupted with 2 min warning.
# To use on-demand instead: rename this to instance-spot.tf.disabled
# and rename instance-ondemand.tf.disabled to instance-ondemand.tf

resource "aws_spot_instance_request" "unity_dev" {
  ami                    = local.selected_ami
  instance_type          = var.instance_type
  key_name               = aws_key_pair.unity_dev.key_name
  vpc_security_group_ids = [aws_security_group.unity_dev.id]
  availability_zone      = "${var.region}a"
  iam_instance_profile   = aws_iam_instance_profile.unity_dev.name
  spot_price             = var.spot_max_price
  wait_for_fulfillment   = true
  spot_type              = "one-time"

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

# Spot requests don't auto-tag the actual instance — propagate tags manually
resource "aws_ec2_tag" "spot_name" {
  resource_id = aws_spot_instance_request.unity_dev.spot_instance_id
  key         = "Name"
  value       = local.instance_name
}

resource "aws_ec2_tag" "spot_project" {
  resource_id = aws_spot_instance_request.unity_dev.spot_instance_id
  key         = "Project"
  value       = var.project_name
}

# Attach persistent data volume
resource "aws_volume_attachment" "unity_data" {
  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.unity_data.id
  instance_id = aws_spot_instance_request.unity_dev.spot_instance_id
}

# --- Outputs ---

output "spot_request_id" {
  description = "Spot instance request ID"
  value       = aws_spot_instance_request.unity_dev.id
}

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_spot_instance_request.unity_dev.spot_instance_id
}

output "public_ip" {
  description = "Public IP address (connect via RDP/DCV/Parsec)"
  value       = aws_spot_instance_request.unity_dev.public_ip
}

output "spot_price" {
  description = "Max spot price configured"
  value       = var.spot_max_price
}
