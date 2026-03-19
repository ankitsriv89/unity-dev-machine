output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.unity_dev.id
}

output "public_ip" {
  description = "Public IP address (connect via RDP/DCV/Parsec)"
  value       = aws_instance.unity_dev.public_ip
}

output "windows_password" {
  description = "Encrypted Windows admin password (decrypt with private key)"
  value       = aws_instance.unity_dev.password_data
  sensitive   = true
}

output "ami_id" {
  description = "AMI used for this instance"
  value       = data.aws_ami.windows_nvidia.id
}
