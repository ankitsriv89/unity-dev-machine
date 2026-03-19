#!/bin/bash
# Dev Machine Manager
# Usage: ./manage.sh [start|stop|status|ip|password|update-ip|extend]
#
# Configure via environment variables or edit defaults below:
#   INSTANCE_NAME - EC2 instance Name tag (e.g., unity-dev-machine)
#   AWS_REGION    - AWS region (e.g., us-east-1)

INSTANCE_NAME="${INSTANCE_NAME:?Set INSTANCE_NAME env var (e.g., unity-dev-machine)}"
REGION="${AWS_REGION:?Set AWS_REGION env var (e.g., us-east-1)}"

get_instance_id() {
  aws ec2 describe-instances \
    --region "$REGION" \
    --filters "Name=tag:Name,Values=$INSTANCE_NAME" "Name=instance-state-name,Values=running,stopped" \
    --query "Reservations[0].Instances[0].InstanceId" \
    --output text
}

case "$1" in
  start)
    echo "Launch via Terraform:"
    echo "  cd terraform && terraform apply"
    ;;

  stop)
    INSTANCE_ID=$(get_instance_id)
    if [ "$INSTANCE_ID" = "None" ] || [ -z "$INSTANCE_ID" ]; then
      echo "No running instance found."
      exit 1
    fi
    # Check if spot or on-demand
    LIFECYCLE=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE_ID" \
      --query "Reservations[0].Instances[0].InstanceLifecycle" --output text 2>/dev/null)
    if [ "$LIFECYCLE" = "spot" ]; then
      echo "Terminating $INSTANCE_NAME (spot — cannot be stopped, only terminated)..."
      aws ec2 terminate-instances --region "$REGION" --instance-ids "$INSTANCE_ID"
      echo "Instance terminated. D: drive (EBS) preserved."
    else
      echo "Stopping $INSTANCE_NAME (on-demand — EBS data preserved)..."
      aws ec2 stop-instances --region "$REGION" --instance-ids "$INSTANCE_ID"
      echo "Instance stopped. Compute billing stopped."
    fi
    ;;

  status)
    INSTANCE_ID=$(get_instance_id)
    aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE_ID" \
      --query "Reservations[0].Instances[0].{State:State.Name,IP:PublicIpAddress,Type:InstanceType}" \
      --output table
    ;;

  ip)
    INSTANCE_ID=$(get_instance_id)
    aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE_ID" \
      --query "Reservations[0].Instances[0].PublicIpAddress" --output text
    ;;

  password)
    INSTANCE_ID=$(get_instance_id)
    echo "Decrypting Windows admin password..."
    aws ec2 get-password-data --region "$REGION" --instance-id "$INSTANCE_ID" \
      --priv-launch-key ~/.ssh/id_rsa --query "PasswordData" --output text
    ;;

  update-ip)
    MY_IP=$(curl -s https://checkip.amazonaws.com)
    echo "Your current IP: $MY_IP"
    echo "Run: cd terraform && terraform apply -var=\"my_ip=$MY_IP\""
    ;;

  extend)
    DURATION="$2"
    if [ -z "$DURATION" ]; then
      echo "Usage: ./manage.sh extend <duration|off>"
      echo "  Examples: ./manage.sh extend 3h"
      echo "           ./manage.sh extend 90m"
      echo "           ./manage.sh extend off"
      exit 1
    fi

    INSTANCE_ID=$(get_instance_id)
    if [ "$INSTANCE_ID" = "None" ] || [ -z "$INSTANCE_ID" ]; then
      echo "No running/stopped instance found."
      exit 1
    fi

    if [ "$DURATION" = "off" ]; then
      aws ec2 delete-tags --region "$REGION" --resources "$INSTANCE_ID" \
        --tags "Key=KeepAliveUntil"
      echo "Keep-alive cancelled. Normal auto-stop/terminate timers restored."
      exit 0
    fi

    # Parse duration to minutes
    MINUTES=0
    if [[ "$DURATION" =~ ^([0-9]+)h$ ]]; then
      MINUTES=$(( ${BASH_REMATCH[1]} * 60 ))
    elif [[ "$DURATION" =~ ^([0-9]+)m$ ]]; then
      MINUTES=${BASH_REMATCH[1]}
    elif [[ "$DURATION" =~ ^([0-9]+)h([0-9]+)m$ ]]; then
      MINUTES=$(( ${BASH_REMATCH[1]} * 60 + ${BASH_REMATCH[2]} ))
    else
      echo "Invalid duration format. Use: 3h, 90m, or 2h30m"
      exit 1
    fi

    EXPIRY=$(date -u -d "+${MINUTES} minutes" +"%Y-%m-%dT%H:%M:%SZ")
    aws ec2 create-tags --region "$REGION" --resources "$INSTANCE_ID" \
      --tags "Key=KeepAliveUntil,Value=$EXPIRY"
    echo "Keep-alive set until $EXPIRY ($MINUTES minutes)."
    echo "Auto-stop and auto-terminate are paused until then."
    echo "To cancel: ./manage.sh extend off"
    ;;

  *)
    echo "Usage: ./manage.sh [start|stop|status|ip|password|update-ip|extend]"
    echo ""
    echo "  start      - Show how to launch (via terraform apply)"
    echo "  stop       - Stop (on-demand) or terminate (spot). D: drive preserved."
    echo "  status     - Show current state and IP"
    echo "  ip         - Get public IP"
    echo "  password   - Decrypt Windows admin password"
    echo "  update-ip  - Show your IP for terraform apply"
    echo "  extend     - Extend auto-stop/terminate (e.g., extend 3h, extend off)"
    echo ""
    echo "Environment variables (required):"
    echo "  INSTANCE_NAME  - EC2 Name tag (e.g., unity-dev-machine)"
    echo "  AWS_REGION     - AWS region (e.g., us-east-1)"
    ;;
esac
