"""
Account-wide AWS cost watchdog.

Runs every hour via EventBridge. Checks ALL regions for running EC2 instances
and sends an SNS alert with instance details, runtime, and estimated cost.
Also checks for unattached EBS volumes.

This is a safety net — catches any forgotten instance regardless of project or tags.
"""

import boto3
import os
from datetime import datetime, timezone


# On-demand prices for common instance types in ap-south-1 (USD/hr).
# Add more as needed.
PRICES = {
    "t2.micro": 0.0116,
    "t3.micro": 0.0104,
    "t3.medium": 0.0416,
    "t3.large": 0.0832,
    "m5.large": 0.096,
    "g4dn.xlarge": 0.71,
    "g4dn.2xlarge": 1.12,
    "g5.xlarge": 1.006,
    "p3.2xlarge": 3.06,
}

# EBS cost per GB per month (gp3 in ap-south-1).
EBS_PER_GB_MONTH = 0.08


def get_all_regions(ec2_client):
    """Get all enabled regions for this account."""
    response = ec2_client.describe_regions(
        Filters=[{"Name": "opt-in-status", "Values": ["opt-in-not-required", "opted-in"]}]
    )
    return [r["RegionName"] for r in response["Regions"]]


def scan_instances(regions):
    """Scan all regions for running EC2 instances."""
    running = []
    for region in regions:
        ec2 = boto3.client("ec2", region_name=region)
        response = ec2.describe_instances(
            Filters=[{"Name": "instance-state-name", "Values": ["running"]}]
        )
        for reservation in response.get("Reservations", []):
            for inst in reservation.get("Instances", []):
                tags = {t["Key"]: t["Value"] for t in inst.get("Tags", [])}
                launch = inst["LaunchTime"]
                now = datetime.now(timezone.utc)
                runtime_hrs = (now - launch).total_seconds() / 3600
                itype = inst["InstanceType"]
                hourly_rate = PRICES.get(itype, 0)
                est_cost = runtime_hrs * hourly_rate
                is_spot = inst.get("InstanceLifecycle") == "spot"

                running.append({
                    "id": inst["InstanceId"],
                    "type": itype,
                    "region": region,
                    "name": tags.get("Name", "unnamed"),
                    "project": tags.get("Project", "untagged"),
                    "launch": launch.strftime("%Y-%m-%d %H:%M UTC"),
                    "runtime_hrs": runtime_hrs,
                    "hourly_rate": hourly_rate,
                    "est_cost": est_cost,
                    "spot": is_spot,
                })
    return running


def scan_unattached_volumes(regions):
    """Scan all regions for unattached EBS volumes."""
    volumes = []
    for region in regions:
        ec2 = boto3.client("ec2", region_name=region)
        response = ec2.describe_volumes(
            Filters=[{"Name": "status", "Values": ["available"]}]
        )
        for vol in response.get("Volumes", []):
            size = vol["Size"]
            monthly_cost = size * EBS_PER_GB_MONTH
            volumes.append({
                "id": vol["VolumeId"],
                "size": size,
                "region": region,
                "monthly_cost": monthly_cost,
                "created": vol["CreateTime"].strftime("%Y-%m-%d"),
            })
    return volumes


def handler(event, context):
    sns_topic_arn = os.environ["SNS_TOPIC_ARN"]
    home_region = os.environ.get("REGION", "ap-south-1")

    ec2 = boto3.client("ec2", region_name=home_region)
    sns = boto3.client("sns", region_name=home_region)

    regions = get_all_regions(ec2)
    instances = scan_instances(regions)
    volumes = scan_unattached_volumes(regions)

    # Nothing running and no orphan volumes — stay silent.
    if not instances and not volumes:
        return {"status": "all_clear", "instances": 0, "volumes": 0}

    # Build alert message.
    lines = []

    if instances:
        total_cost = sum(i["est_cost"] for i in instances)
        lines.append(f"=== {len(instances)} RUNNING INSTANCE(S) ===\n")
        for i in instances:
            spot_tag = " [SPOT]" if i["spot"] else ""
            price_str = f"${i['hourly_rate']:.2f}/hr" if i["hourly_rate"] > 0 else "price unknown"
            lines.append(
                f"  {i['name']} ({i['id']})\n"
                f"    Type: {i['type']}{spot_tag}  |  Region: {i['region']}\n"
                f"    Running: {i['runtime_hrs']:.1f}h  |  Rate: {price_str}\n"
                f"    Est cost so far: ${i['est_cost']:.2f}\n"
            )
        lines.append(f"  TOTAL estimated cost: ${total_cost:.2f}\n")

    if volumes:
        total_monthly = sum(v["monthly_cost"] for v in volumes)
        lines.append(f"\n=== {len(volumes)} UNATTACHED EBS VOLUME(S) ===\n")
        for v in volumes:
            lines.append(
                f"  {v['id']}  |  {v['size']}GB  |  {v['region']}\n"
                f"    Created: {v['created']}  |  Wasting: ${v['monthly_cost']:.2f}/mo\n"
            )
        lines.append(f"  TOTAL monthly waste: ${total_monthly:.2f}/mo\n")

    lines.append("\nTerminate via: aws ec2 terminate-instances --instance-ids <id>")
    lines.append("Delete volume: aws ec2 delete-volume --volume-id <id>")

    message = "\n".join(lines)

    # Determine severity for subject line.
    total_hourly = sum(PRICES.get(i["type"], 0) for i in instances)
    if total_hourly >= 0.50:
        subject = f"AWS ALERT: ${total_hourly:.2f}/hr burning — {len(instances)} instance(s) running"
    elif instances:
        subject = f"AWS: {len(instances)} instance(s) running — ${total_hourly:.2f}/hr"
    else:
        subject = f"AWS: {len(volumes)} unattached EBS volume(s) wasting money"

    sns.publish(
        TopicArn=sns_topic_arn,
        Subject=subject[:100],  # SNS subject max 100 chars
        Message=message,
    )

    return {
        "status": "alert_sent",
        "instances": len(instances),
        "volumes": len(volumes),
    }
