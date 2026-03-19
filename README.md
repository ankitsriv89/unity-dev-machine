# Unity Dev Machine on AWS

GPU-accelerated Unity development machine on AWS EC2 with automatic cost controls.

Spin up a Windows EC2 instance with a GPU, develop in Unity, and shut it down when you're done. Built-in safety nets prevent forgotten instances from running up your bill.

## Features

- **Terraform-managed** — one `terraform apply` to deploy everything
- **Auto-stop** — instance stops after 1 hour of keyboard/mouse inactivity
- **Auto-terminate** — instance terminates after 4 hours runtime (configurable)
- **SNS alerts** — email + SMS warning 15 minutes before auto-stop/terminate
- **Keep-alive** — extend timers for long renders/builds (PIN-authenticated)
- **Persistent storage** — D: drive (EBS volume) survives termination
- **manage.sh** — CLI for start/stop/status/extend

## Architecture

```
┌─────────────────────────────────────────────────┐
│  EC2 Instance (Windows + GPU)                   │
│  ┌─────────────────────────────────────────┐    │
│  │ Scheduled Task (every 5 min)            │    │
│  │ → idle-shutdown.ps1                     │    │
│  │ → Detects input idle via Win32 API      │    │
│  │ → Warns at 45 min, stops at 60 min     │    │
│  └─────────────────────────────────────────┘    │
│  ┌─────────────────────────────────────────┐    │
│  │ keep-alive.ps1 (PIN-protected)          │    │
│  │ → Pauses idle + terminate timers        │    │
│  └─────────────────────────────────────────┘    │
├─────────────────────────────────────────────────┤
│  C: drive (from AMI)  │  D: drive (persistent)  │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│  AWS (external safety net)                      │
│  EventBridge (every 15 min) → Lambda            │
│  → Checks runtime via LaunchTime                │
│  → Warns at 3h45m, terminates at 4h             │
│  → Respects KeepAliveUntil EC2 tag              │
│                                                 │
│  SNS Topic → Email + SMS alerts                 │
│  SSM Parameter Store → keep-alive PIN           │
└─────────────────────────────────────────────────┘
```

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.0
- An SSH key pair

## Quick Start

1. **Clone and configure:**
   ```bash
   git clone https://github.com/ankitsriv89/unitydev.git
   cd unity-dev-machine
   cp terraform.tfvars.example terraform/terraform.tfvars
   ```

2. **Edit `terraform/terraform.tfvars`** — fill in your values (region, IP, password, email, phone, PIN)

3. **Edit the backend in `terraform/main.tf`** — set your S3 bucket, key, and region for Terraform state

4. **Deploy:**
   ```bash
   cd terraform
   terraform init
   terraform apply
   ```

5. **Confirm SNS subscriptions** — check your email and phone for confirmation links

6. **Connect to the instance** via RDP or Parsec, then run the idle-shutdown setup:
   ```powershell
   # Run as Administrator
   .\setup-idle-task.ps1 -Region <your-region> -ProjectName <your-project-name>
   ```

## Usage

### manage.sh

```bash
./manage.sh start       # Start the instance
./manage.sh stop        # Stop (preserves data)
./manage.sh status      # Show state and IP
./manage.sh ip          # Get public IP
./manage.sh password    # Decrypt Windows admin password
./manage.sh update-ip   # Show your IP for security group update
./manage.sh extend 3h   # Extend auto-terminate by 3 hours
./manage.sh extend off  # Cancel keep-alive
```

### Keep-alive (on the VM)

```powershell
keep-alive 3h --pin 1234       # Extend for 3 hours
keep-alive 90m --pin 1234      # Extend for 90 minutes
keep-alive 2h30m --pin 1234    # Extend for 2.5 hours
keep-alive off --pin 1234      # Cancel
```

### Environment Variables

```bash
export INSTANCE_NAME="my-dev-machine"  # Required
export AWS_REGION="us-east-1"          # Required
```

## Cost Estimates

See [COST-PROJECTIONS.md](COST-PROJECTIONS.md) for detailed pricing.

| Scenario | ~$/month |
|---|---|
| 2 hrs/day, spot g4dn.xlarge | $12 |
| 2 hrs/day, spot g4dn.2xlarge | $17 |
| When not using (snapshot only) | $2-8 |

## File Structure

```
├── terraform/
│   ├── main.tf              # EC2, security group, IAM, EBS
│   ├── auto-stop.tf         # Lambda, EventBridge, SNS, SSM
│   ├── variables.tf         # All configurable variables
│   └── outputs.tf           # Instance ID, IP, etc.
├── lambda/
│   └── auto_terminate.py    # Lambda: 4hr runtime cap
├── scripts/
│   ├── idle-shutdown.ps1    # Idle detection (Win32 API)
│   ├── keep-alive.ps1       # PIN-protected timer extension
│   └── setup-idle-task.ps1  # One-time installer
├── manage.sh                # CLI for instance management
├── install-nvidia-driver.ps1 # NVIDIA driver installer
├── terraform.tfvars.example  # Template for your config
└── COST-PROJECTIONS.md      # Detailed cost analysis
```

## How Auto-Stop Works

**Idle detection (1 hour):**
- PowerShell scheduled task runs every 5 minutes
- Uses `GetLastInputInfo` Win32 API to detect real keyboard/mouse activity
- Works with RDP, Parsec, and NICE DCV (they inject input events)
- Sends SNS warning at 45 min idle, stops at 60 min

**Runtime cap (4 hours):**
- Lambda function runs every 15 minutes via EventBridge
- Checks instance `LaunchTime` to calculate runtime
- Sends SNS warning at 3h45m, **terminates** at 4h
- External to the instance — works even if the OS hangs

**Keep-alive:**
- Sets a local file (for idle detection) and an EC2 tag `KeepAliveUntil` (for Lambda)
- Both mechanisms check and respect the keep-alive before acting
- PIN stored in SSM Parameter Store (SecureString), not on disk

## License

MIT
