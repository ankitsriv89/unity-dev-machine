variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "unity-dev"
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type (g4dn.xlarge for T4, g5.xlarge for A10G)"
  type        = string
  default     = "g4dn.xlarge"
}

variable "public_key_path" {
  description = "Path to SSH public key for key pair (Windows: C:/Users/YourName/.ssh/id_ed25519.pub)"
  type        = string
}

variable "my_ip" {
  description = "Your public IP (leave empty to allow all IPs). Run: curl -s https://checkip.amazonaws.com"
  type        = string
  default     = ""
}

variable "windows_password" {
  description = "Windows Administrator password (leave empty if AMI already has password set)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "ami_id" {
  description = "Specific AMI ID (leave empty to auto-select latest Windows Server 2022)"
  type        = string
  default     = ""
}

variable "spot_max_price" {
  description = "Override spot max price. Leave empty to use the default per instance_type (xlarge=0.35, 2xlarge=0.55)"
  type        = string
  default     = ""
}

variable "on_demand" {
  description = "Set to true to use on-demand instead of spot. Pass via CLI: -var='on_demand=true'"
  type        = bool
  default     = false
}

variable "max_runtime_hours" {
  description = "Max hours before instance is auto-terminated (hard cap)"
  type        = number
  default     = 4
}

variable "alert_email" {
  description = "Email address for auto-stop/terminate alerts"
  type        = string
}

variable "alert_phone" {
  description = "Phone number for SMS alerts (E.164 format, e.g., +919876543210)"
  type        = string
}

variable "keep_alive_pin" {
  description = "PIN for the keep-alive command on the VM"
  type        = string
  sensitive   = true
}
