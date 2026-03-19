# Unity Dev Machine — Cost Projections (ap-south-1)

All prices from AWS Pricing API (2026-03-17). INR calculated at $1 = ₹85.

---

## Instance Options (Windows, ap-south-1)

| Instance | GPU | VRAM | vCPU | RAM | On-demand $/hr | On-demand ₹/hr | Spot ~$/hr | Spot ~₹/hr |
|---|---|---|---|---|---|---|---|---|
| **g4dn.xlarge** | T4 | 16GB | 4 | 16GB | $0.76 | ₹65 | ~$0.16 | ~₹14 |
| **g4dn.2xlarge** | T4 | 16GB | 8 | 32GB | $1.20 | ₹102 | ~$0.25 | ~₹21 |
| g5.xlarge | A10G | 24GB | 4 | 16GB | $1.39 | ₹118 | ~$0.45 | ~₹38 |
| g5.2xlarge | A10G | 24GB | 8 | 32GB | $1.82 | ₹155 | ~$0.55 | ~₹47 |

**Current plan: g4dn.2xlarge on spot — ₹21/hr**

---

## Storage Pricing

| Component | Rate |
|---|---|
| gp3 storage | $0.0912/GB/month (₹7.75/GB/month) |
| gp3 IOPS (above 3,000 free) | $0.0057/IOPS/month |
| gp3 throughput (above 125 MB/s free) | $0.0456/MiBps/month |
| **EBS Snapshot (AMI)** | **$0.05/GB/month (₹4.25/GB/month)** |

---

## Your Plan: 2 hrs/day, 30 days, Snapshot Workflow, Spot

### g4dn.xlarge (spot)

| Item | Calculation | $/month | ₹/month |
|---|---|---|---|
| Compute | 60 hrs x ~$0.16 | $9.60 | ₹816 |
| AMI snapshot (~40GB used) | 40 x $0.05 | $2.00 | ₹170 |
| **Total** | | **$11.60** | **₹986** |

### g4dn.2xlarge (spot) — RECOMMENDED

| Item | Calculation | $/month | ₹/month |
|---|---|---|---|
| Compute | 60 hrs x ~$0.25 | $15.00 | ₹1,275 |
| AMI snapshot (~40GB used) | 40 x $0.05 | $2.00 | ₹170 |
| **Total** | | **$17.00** | **₹1,445** |

### g4dn.2xlarge (on-demand)

| Item | Calculation | $/month | ₹/month |
|---|---|---|---|
| Compute | 60 hrs x $1.20 | $72.00 | ₹6,120 |
| AMI snapshot (~40GB used) | 40 x $0.05 | $2.00 | ₹170 |
| **Total** | | **$74.00** | **₹6,290** |

---

## All Scenarios Summary

| Scenario | ₹/month |
|---|---|
| **Snapshot only (not using)** | **₹170 — ₹638** |
| 2 hrs/day spot xlarge (snapshot) | **₹986** |
| **2 hrs/day spot 2xlarge (snapshot)** | **₹1,445** |
| 2 hrs/day on-demand xlarge (snapshot) | **₹4,070** |
| 2 hrs/day on-demand 2xlarge (snapshot) | **₹6,290** |
| Idle (stopped, volumes kept) | **₹1,040** |
| 4 hrs/day on-demand xlarge | **₹6,353** |
| 8 hrs/day on-demand xlarge | **₹14,134** |

---

## vs. Laptop (₹2,00,000)

| Option | Monthly cost | Break-even |
|---|---|---|
| Cloud 2hr/day spot 2xlarge | ₹1,445 | **138 months (11.5 years)** |
| Cloud 2hr/day on-demand 2xlarge | ₹6,290 | **32 months (2.6 years)** |
| Cloud 4hr/day on-demand xlarge | ₹6,353 | **31 months (2.6 years)** |
| Cloud 8hr/day on-demand xlarge | ₹14,134 | **14 months (1.2 years)** |

**Cloud wins decisively for part-time / project-based work.**

---

## Workflow

1. **Start session:** Restore AMI → spot g4dn.2xlarge → `git pull`
2. **Work:** Unity development (2 hrs)
3. **End session:** `git push` → create AMI → `terraform destroy`
4. **Cost when not working:** Snapshot storage only (~₹170-638/month)

## Key Notes

- Spot instances can be interrupted with 2 min warning — always `git push` regularly
- Instance type can be changed without destroying (stop → change type → start)
- AMI captures both C: (OS+Unity+drivers) and D: (projects) drives
- Git is the real persistence layer; snapshots are for environment convenience
- GPU power ranking: T4 (g4dn) < L4 (g6) < A10G (g5)

---

*Source: AWS Pricing API, ap-south-1, retrieved 2026-03-17*
