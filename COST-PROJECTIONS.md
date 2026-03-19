# Unity Dev Machine — Cost Projections

Prices vary by region. Below are approximate USD costs based on typical AWS pricing. Check [AWS Pricing](https://aws.amazon.com/ec2/pricing/) for your region.

---

## Instance Options (Windows)

| Instance | GPU | VRAM | vCPU | RAM | On-demand ~$/hr | Spot ~$/hr |
|---|---|---|---|---|---|---|
| **g4dn.xlarge** | T4 | 16GB | 4 | 16GB | ~$0.71–0.82 | ~$0.15–0.25 |
| **g4dn.2xlarge** | T4 | 16GB | 8 | 32GB | ~$1.06–1.30 | ~$0.20–0.35 |
| g5.xlarge | A10G | 24GB | 4 | 16GB | ~$1.20–1.50 | ~$0.35–0.55 |
| g5.2xlarge | A10G | 24GB | 8 | 32GB | ~$1.60–2.00 | ~$0.45–0.70 |

---

## Storage Pricing

| Component | Rate |
|---|---|
| gp3 storage | ~$0.08–0.10/GB/month |
| gp3 IOPS (above 3,000 free) | ~$0.005–0.006/IOPS/month |
| gp3 throughput (above 125 MB/s free) | ~$0.04–0.05/MiBps/month |
| **EBS Snapshot (AMI)** | **~$0.05/GB/month** |

---

## Example: 2 hrs/day, 30 days, Spot

### g4dn.xlarge (spot)

| Item | Calculation | ~$/month |
|---|---|---|
| Compute | 60 hrs x ~$0.16 | ~$10 |
| AMI snapshot (~40GB used) | 40 x $0.05 | ~$2 |
| **Total** | | **~$12** |

### g4dn.2xlarge (spot)

| Item | Calculation | ~$/month |
|---|---|---|
| Compute | 60 hrs x ~$0.25 | ~$15 |
| AMI snapshot (~40GB used) | 40 x $0.05 | ~$2 |
| **Total** | | **~$17** |

---

## Scenarios Summary

| Scenario | ~$/month |
|---|---|
| Snapshot only (not using) | $2–8 |
| 2 hrs/day spot g4dn.xlarge | ~$12 |
| 2 hrs/day spot g4dn.2xlarge | ~$17 |
| 2 hrs/day on-demand g4dn.xlarge | ~$50 |
| 2 hrs/day on-demand g4dn.2xlarge | ~$75 |

---

## Workflow

1. **Start session:** Launch from AMI → spot instance → `git pull`
2. **Work:** Unity development (2 hrs)
3. **End session:** `git push` → create AMI → terminate instance
4. **Cost when not working:** Snapshot storage only (~$2–8/month)

## Key Notes

- Spot instances can be interrupted with 2 min warning — always `git push` regularly
- Instance type can be changed without destroying (stop → change type → start)
- AMI captures both C: (OS+Unity+drivers) and D: (projects) drives
- Git is the real persistence layer; snapshots are for environment convenience
- GPU power ranking: T4 (g4dn) < L4 (g6) < A10G (g5)

---

*Prices are approximate and vary by region. Always verify with [AWS Pricing](https://aws.amazon.com/ec2/pricing/).*
