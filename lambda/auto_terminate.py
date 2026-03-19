import boto3
import os
from datetime import datetime, timezone, timedelta


def get_instance(ec2, project_tag, instance_name):
    """Find instance by tags instead of hardcoded ID."""
    response = ec2.describe_instances(
        Filters=[
            {"Name": "tag:Project", "Values": [project_tag]},
            {"Name": "tag:Name", "Values": [instance_name]},
            {"Name": "instance-state-name", "Values": ["running"]},
        ]
    )
    for reservation in response.get("Reservations", []):
        for instance in reservation.get("Instances", []):
            return instance
    return None


def handler(event, context):
    region = os.environ["REGION"]
    project_tag = os.environ["PROJECT_TAG"]
    instance_name = os.environ["INSTANCE_NAME"]
    max_hours = int(os.environ.get("MAX_RUNTIME_HOURS", "4"))
    sns_topic_arn = os.environ["SNS_TOPIC_ARN"]
    warning_minutes = 15

    ec2 = boto3.client("ec2", region_name=region)
    sns = boto3.client("sns", region_name=region)

    instance = get_instance(ec2, project_tag, instance_name)
    if not instance:
        return {"status": "no_running_instance", "action": "none"}

    instance_id = instance["InstanceId"]
    tags = {t["Key"]: t["Value"] for t in instance.get("Tags", [])}

    # Check keep-alive tag
    keep_alive_until = tags.get("KeepAliveUntil")
    if keep_alive_until:
        try:
            expiry = datetime.fromisoformat(keep_alive_until)
            if datetime.now(timezone.utc) < expiry:
                return {
                    "status": "keep_alive_active",
                    "instance_id": instance_id,
                    "until": keep_alive_until,
                    "action": "none",
                }
        except ValueError:
            pass  # Invalid tag value, ignore and proceed

    # Calculate runtime
    launch_time = instance["LaunchTime"]
    now = datetime.now(timezone.utc)
    runtime = now - launch_time
    runtime_hours = runtime.total_seconds() / 3600
    max_runtime = timedelta(hours=max_hours)
    warning_threshold = max_runtime - timedelta(minutes=warning_minutes)

    # Past max runtime -> terminate
    if runtime >= max_runtime:
        sns.publish(
            TopicArn=sns_topic_arn,
            Subject="Unity Dev Machine TERMINATED",
            Message=(
                f"Instance {instance_id} has been TERMINATED after "
                f"{runtime_hours:.1f} hours of runtime (max: {max_hours}h).\n\n"
                f"Your D: drive (EBS) is preserved. "
                f"Recreate the instance from AMI when ready."
            ),
        )
        ec2.terminate_instances(InstanceIds=[instance_id])
        return {
            "status": "terminated",
            "runtime_hours": runtime_hours,
            "instance_id": instance_id,
        }

    # In warning window -> send warning
    if runtime >= warning_threshold:
        remaining = (max_runtime - runtime).total_seconds() / 60
        sns.publish(
            TopicArn=sns_topic_arn,
            Subject="Unity Dev Machine will TERMINATE soon",
            Message=(
                f"Instance {instance_id} will be TERMINATED in "
                f"~{remaining:.0f} minutes (4hr runtime cap).\n\n"
                f"To extend, run one of:\n"
                f"  On VM:    keep-alive 2h --pin <your-pin>\n"
                f"  Locally:  ./manage.sh extend 2h"
            ),
        )
        return {
            "status": "warning_sent",
            "instance_id": instance_id,
            "runtime_hours": runtime_hours,
            "remaining_minutes": remaining,
        }

    return {
        "status": "running",
        "instance_id": instance_id,
        "runtime_hours": runtime_hours,
        "remaining_hours": (max_runtime - runtime).total_seconds() / 3600,
    }
