#!/bin/bash
# Dev Machine Manager
# Usage: ./manage.sh [start|stop|status|ip|password|update-ip|extend]
#
# Configure via environment variables or edit defaults below:
#   INSTANCE_NAME - EC2 instance Name tag (default: unity-dev-machine)
#   AWS_REGION    - AWS region (default: ap-south-1)

INSTANCE_NAME="${INSTANCE_NAME:-unity-dev-machine}"
REGION="${AWS_REGION:-ap-south-1}"

get_instance_id() {
  aws ec2 describe-instances \
    --region "$REGION" \
    --filters "Name=tag:Name,Values=$INSTANCE_NAME" "Name=instance-state-name,Values=running,stopped" \
    --query "Reservations[0].Instances[0].InstanceId" \
    --output text
}

case "$1" in
  start)
    echo "Starting $INSTANCE_NAME..."
    INSTANCE_ID=$(get_instance_id)
    aws ec2 start-instances --region "$REGION" --instance-ids "$INSTANCE_ID"
    echo "Waiting for instance to be running..."
    aws ec2 wait instance-running --region "$REGION" --instance-ids "$INSTANCE_ID"
    IP=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE_ID" \
      --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
    echo "Machine is running at: $IP"
    echo "Connect via RDP: $IP:3389 or DCV: https://$IP:8443"
    ;;

  stop)
    echo "Stopping $INSTANCE_NAME (EBS data preserved)..."
    INSTANCE_ID=$(get_instance_id)
    aws ec2 stop-instances --region "$REGION" --instance-ids "$INSTANCE_ID"
    echo "Machine stopped. Compute billing stopped."
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
    echo "  start      - Start the machine"
    echo "  stop       - Stop (preserves data, stops billing compute)"
    echo "  status     - Show current state and IP"
    echo "  ip         - Get public IP"
    echo "  password   - Decrypt Windows admin password"
    echo "  update-ip  - Show your IP for terraform apply"
    echo "  extend     - Extend auto-stop/terminate (e.g., extend 3h, extend off)"
    echo ""
    echo "Environment variables:"
    echo "  INSTANCE_NAME  - EC2 Name tag (default: unity-dev-machine)"
    echo "  AWS_REGION     - AWS region (default: ap-south-1)"
    ;;
esac
