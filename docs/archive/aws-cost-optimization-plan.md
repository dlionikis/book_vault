# AWS Cost Optimization Plan

> **Created**: January 1, 2026  
> **Completed**: January 2, 2026  
> **Status**: ✅ COMPLETE - All phases implemented successfully  
> **Goal**: Minimize AWS costs for personal/family use (3-5 users)  
> **Original Cost**: ~$65-75/month  
> **Optimized Cost**: ~$47-52/month  
> **Monthly Savings**: ~$35-40 (40-45% reduction)  
> **Annual Savings**: ~$420-480

---

## ✅ Implementation Summary

All four optimization phases were successfully completed on January 2, 2026:

1. **✅ Billing Alerts** - AWS Budget created with $75/month limit and email alerts at 50%, 80%, 100%
2. **✅ S3 Intelligent-Tiering** - Configured with Archive Access tier (90 days), no Deep Archive
3. **✅ Right-Size Fargate** - Reduced from 1 vCPU/2GB to 0.25 vCPU/512MB (task-definition revision 3)
4. **✅ Fargate Spot (2 Tasks)** - Migrated to 100% Spot instances with 2 tasks for zero-downtime failover

**Current Configuration**:

- 2 Fargate Spot tasks × 0.25 vCPU × 512MB = ~$5-6/month compute
- S3 Intelligent-Tiering with 90-day Archive Access = ~$8-12/month storage
- Total infrastructure: ~$47-52/month (vs ~$87 original)

**Next Steps**:

- Monitor performance over next few days
- Confirm AWS Budget email alerts
- Check S3 storage distribution after 24-48 hours
- Review February 2026 bill to verify savings
- See [s3-archive-restore-workflow.md](../s3-archive-restore-workflow.md) for handling archived files (future enhancement)

---

## TL;DR

Four optimizations to cut costs by ~40-50%:

1. **Billing Alerts** - Set up budget monitoring (free)
2. **S3 Intelligent-Tiering** - Auto-optimize storage costs (~$10-15/month savings)
3. **Right-size Fargate** - Reduce from 1 vCPU to 0.25 vCPU (~$20/month savings)
4. **Fargate Spot (2 tasks)** - 100% Spot with 2 tasks for zero-downtime failover (~$24/month savings)

**Implementation time**: ~30 minutes total

**Final configuration**: 2 Spot tasks (0.25 vCPU, 512MB each) = ~$5-6/month compute (vs ~$30 current)

---

## Table of Contents

1. [Current Cost Breakdown](#1-current-cost-breakdown)
2. [Phase 1: Billing Alerts](#phase-1-billing-alerts-do-first)
3. [Phase 2: S3 Intelligent-Tiering](#phase-2-s3-intelligent-tiering)
4. [Phase 3: Right-Size Fargate Task](#phase-3-right-size-fargate-task)
5. [Phase 4: Fargate Spot with 2 Tasks](#phase-4-fargate-spot-with-2-tasks-recommended)
6. [Projected Savings](#projected-savings)
7. [Monitoring & Verification](#monitoring--verification)
8. [Rollback Procedures](#rollback-procedures)

---

## 1. Current Cost Breakdown

| Component                 | Specification               | Monthly Cost |
| ------------------------- | --------------------------- | ------------ |
| ECS Fargate               | 1 vCPU, 2GB RAM (always-on) | ~$30         |
| Application Load Balancer | Fixed cost + LCU            | ~$18         |
| RDS PostgreSQL            | db.t3.micro, 20GB           | ~$15         |
| S3 Storage                | ~514GB (Standard class)     | ~$12         |
| S3 Data Transfer          | ~10GB/month                 | ~$1          |
| **Total**                 |                             | **~$76**     |

### Usage Profile

- **Users**: 3-5 occasional users (personal/family)
- **S3 Storage**: 600GB - 1TB expected
- **Traffic**: Low (< 1000 requests/day typical)
- **Availability needs**: Low (brief outages acceptable)

---

## Phase 1: Billing Alerts (Do First)

**Purpose**: Get notified before costs spiral out of control

**Time to implement**: 5 minutes

**Cost**: Free

### Step 1.1: Get Your AWS Account ID

```bash
# Get account ID (save this for later steps)
AWS_PROFILE=book_vault aws sts get-caller-identity --query 'Account' --output text
```

### Step 1.2: Create Budget via AWS Console (Recommended)

The AWS Console is easier for budgets than CLI:

1. Go to: https://console.aws.amazon.com/billing/home#/budgets
2. Click **Create budget**
3. Select **Cost budget - Recommended**
4. Configure:
   - **Budget name**: `BookVault-Monthly`
   - **Budget amount**: `$75` (or your preferred limit)
   - **Budget scope**: All AWS services
5. Add alert thresholds:
   - **Alert 1**: 50% of budgeted amount (Actual cost)
   - **Alert 2**: 80% of budgeted amount (Actual cost)
   - **Alert 3**: 100% of budgeted amount (Actual cost)
   - **Alert 4**: 100% of budgeted amount (Forecasted cost)
6. Add your email address for notifications
7. Click **Create budget**

### Step 1.3: Alternative - Create Budget via CLI

If you prefer CLI (replace `YOUR_EMAIL` and `YOUR_ACCOUNT_ID`):

```bash
# Create the budget
aws budgets create-budget \
  --account-id YOUR_ACCOUNT_ID \
  --budget '{
    "BudgetName": "BookVault-Monthly",
    "BudgetLimit": {
      "Amount": "75",
      "Unit": "USD"
    },
    "TimeUnit": "MONTHLY",
    "BudgetType": "COST",
    "CostFilters": {},
    "CostTypes": {
      "IncludeTax": true,
      "IncludeSubscription": true,
      "UseBlended": false,
      "IncludeRefund": false,
      "IncludeCredit": false,
      "IncludeUpfront": true,
      "IncludeRecurring": true,
      "IncludeOtherSubscription": true,
      "IncludeSupport": true,
      "IncludeDiscount": true,
      "UseAmortized": false
    }
  }' \
  --notifications-with-subscribers '[
    {
      "Notification": {
        "NotificationType": "ACTUAL",
        "ComparisonOperator": "GREATER_THAN",
        "Threshold": 50,
        "ThresholdType": "PERCENTAGE",
        "NotificationState": "ALARM"
      },
      "Subscribers": [
        {
          "SubscriptionType": "EMAIL",
          "Address": "YOUR_EMAIL"
        }
      ]
    },
    {
      "Notification": {
        "NotificationType": "ACTUAL",
        "ComparisonOperator": "GREATER_THAN",
        "Threshold": 80,
        "ThresholdType": "PERCENTAGE",
        "NotificationState": "ALARM"
      },
      "Subscribers": [
        {
          "SubscriptionType": "EMAIL",
          "Address": "YOUR_EMAIL"
        }
      ]
    },
    {
      "Notification": {
        "NotificationType": "ACTUAL",
        "ComparisonOperator": "GREATER_THAN",
        "Threshold": 100,
        "ThresholdType": "PERCENTAGE",
        "NotificationState": "ALARM"
      },
      "Subscribers": [
        {
          "SubscriptionType": "EMAIL",
          "Address": "YOUR_EMAIL"
        }
      ]
    },
    {
      "Notification": {
        "NotificationType": "FORECASTED",
        "ComparisonOperator": "GREATER_THAN",
        "Threshold": 100,
        "ThresholdType": "PERCENTAGE",
        "NotificationState": "ALARM"
      },
      "Subscribers": [
        {
          "SubscriptionType": "EMAIL",
          "Address": "YOUR_EMAIL"
        }
      ]
    }
  ]' \
  --profile book_vault
```

### Step 1.4: Verify Budget Created

```bash
aws budgets describe-budgets \
  --account-id YOUR_ACCOUNT_ID \
  --profile book_vault \
  --query 'Budgets[*].{Name:BudgetName,Limit:BudgetLimit.Amount,Spent:CalculatedSpend.ActualSpend.Amount}'
```

### Verification Checklist

- [ ] Budget created with $75 limit
- [ ] Email alerts configured at 50%, 80%, 100%
- [ ] Forecasted alert at 100%
- [ ] Received confirmation email from AWS

---

## Phase 2: S3 Intelligent-Tiering

**Purpose**: Automatically move infrequently accessed audiobooks to cheaper storage tiers

**Time to implement**: 5 minutes

**Estimated savings**: $8-15/month (depending on access patterns)

### How It Works

S3 Intelligent-Tiering automatically moves objects between tiers:

| Tier              | Access Pattern       | Cost/GB/month | Your 1TB Cost |
| ----------------- | -------------------- | ------------- | ------------- |
| Frequent Access   | Accessed recently    | $0.023        | $23.55        |
| Infrequent Access | Not accessed 30 days | $0.0125       | $12.80        |
| Archive Access    | Not accessed 90 days | $0.0036       | $3.69         |

**Monitoring fee**: $0.0025 per 1,000 objects (~$0.07/month for 2,781 files)

**Implementation Notes**:

- We configured only Archive Access (90 days), not Deep Archive (180 days), to keep maximum restore time at 3-5 hours instead of 12 hours
- **Only files > 5MB are moved to Intelligent-Tiering** - this keeps cover images, metadata JSON, and cue files in S3 Standard so they're always instantly accessible when browsing the library
- See [s3-archive-restore-workflow.md](../s3-archive-restore-workflow.md) for handling archived audio files

For an audiobook library where you likely listen to 10-20% of books regularly and 80% sit untouched, this is ideal.

### Step 2.1: Enable Intelligent-Tiering Lifecycle Rule

This rule transitions objects > 5MB to Intelligent-Tiering (keeping small files like cover art in Standard):

```bash
aws s3api put-bucket-lifecycle-configuration \
  --bucket book-vault-media \
  --lifecycle-configuration '{
    "Rules": [
      {
        "ID": "MoveToIntelligentTiering",
        "Status": "Enabled",
        "Filter": {
          "ObjectSizeGreaterThan": 5242880
        },
        "Transitions": [
          {
            "Days": 0,
            "StorageClass": "INTELLIGENT_TIERING"
          }
        ]
      }
    ]
  }' \
  --profile book_vault \
  --region us-east-1
```

### Step 2.2: Configure Archive Access Tier

**Implementation Note**: We configured only Archive Access tier (90 days), not Deep Archive, to keep maximum restore time at 3-5 hours.

Enable automatic archiving for objects not accessed in 90+ days:

```bash
aws s3api put-bucket-intelligent-tiering-configuration \
  --bucket book-vault-media \
  --id "ArchiveConfig" \
  --intelligent-tiering-configuration '{
    "Id": "ArchiveConfig",
    "Status": "Enabled",
    "Filter": {},
    "Tierings": [
      {
        "Days": 90,
        "AccessTier": "ARCHIVE_ACCESS"
      }
    ]
  }' \
  --profile book_vault \
  --region us-east-1
```

**Note**: Archive Access tier has a 3-5 hour retrieval time if you need to access a file that hasn't been played in 90+ days. See [s3-archive-restore-workflow.md](./s3-archive-restore-workflow.md) for implementation details on handling archived files.

### Step 2.3: Verify Configuration

```bash
# Check lifecycle rule
aws s3api get-bucket-lifecycle-configuration \
  --bucket book-vault-media \
  --profile book_vault \
  --region us-east-1

# Check Intelligent-Tiering configuration
aws s3api list-bucket-intelligent-tiering-configurations \
  --bucket book-vault-media \
  --profile book_vault \
  --region us-east-1
```

### Step 2.4: Monitor Transition Progress

Objects transition gradually. Check storage class distribution after a few days:

```bash
# Get storage metrics from S3 (available after 24-48 hours)
aws s3api list-objects-v2 \
  --bucket book-vault-media \
  --query 'Contents[].StorageClass' \
  --profile book_vault \
  --region us-east-1 | sort | uniq -c

# Or use S3 Storage Lens in console for detailed analytics
# https://console.aws.amazon.com/s3/storage-lens
```

### Verification Checklist

- [x] Lifecycle rule created (MoveToIntelligentTiering) with 5MB size filter
- [x] Archive tier configured (90-day only, no Deep Archive)
- [x] Verified with get-bucket-lifecycle-configuration
- [ ] Wait 24-48 hours, then check storage class distribution

### Important Notes

- **No retrieval fees** for Frequent and Infrequent Access tiers
- **Retrieval fees apply** for Archive tier ($0.03/GB to restore)
- **Restore time**: 3-5 hours for Archive Access tier
- **Only files > 5MB** are moved to Intelligent-Tiering (audio files)
- **Files ≤ 5MB** stay in S3 Standard permanently (cover art, metadata, cue files)
- Objects < 128KB within Intelligent-Tiering stay in Frequent Access tier
- Transition happens automatically—no action needed after setup
- **Configuration**: Only Archive Access tier enabled (90 days), no Deep Archive

---

## Phase 3: Right-Size Fargate Task

**Purpose**: Reduce compute resources to match actual usage

**Time to implement**: 10 minutes

**Estimated savings**: $20-25/month

### Current vs Recommended Sizing

| Resource     | Current       | Recommended     | Cost Reduction |
| ------------ | ------------- | --------------- | -------------- |
| vCPU         | 1024 (1 vCPU) | 256 (0.25 vCPU) | 75%            |
| Memory       | 2048 MB       | 512 MB          | 75%            |
| Monthly Cost | ~$30          | ~$7.50          | ~$22.50        |

### Why This Is Safe

- Next.js is efficient—0.25 vCPU handles light traffic easily
- 512MB is plenty for a Next.js app with no heavy processing
- 3-5 occasional users won't stress this configuration
- You can always scale back up if needed

### Step 3.1: Get Current Task Definition

```bash
# Export current task definition (for reference/backup)
aws ecs describe-task-definition \
  --task-definition book-vault \
  --profile book_vault \
  --region us-east-1 \
  --query 'taskDefinition' > /tmp/task-def-backup.json

# View current CPU/memory
aws ecs describe-task-definition \
  --task-definition book-vault \
  --profile book_vault \
  --region us-east-1 \
  --query 'taskDefinition.{cpu:cpu,memory:memory}'
```

### Step 3.2: Create Updated Task Definition

```bash
# Create new task definition with reduced resources
aws ecs describe-task-definition \
  --task-definition book-vault \
  --profile book_vault \
  --region us-east-1 \
  --query 'taskDefinition' | \
  jq 'del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy) |
      .cpu = "256" |
      .memory = "512"' > /tmp/task-def-optimized.json

# Review the changes
cat /tmp/task-def-optimized.json | jq '{cpu, memory}'
```

### Step 3.3: Register New Task Definition

```bash
aws ecs register-task-definition \
  --cli-input-json file:///tmp/task-def-optimized.json \
  --profile book_vault \
  --region us-east-1

# Note the new revision number from output (e.g., book-vault:3)
```

### Step 3.4: Deploy the New Task Definition

```bash
# Update service to use new task definition
aws ecs update-service \
  --cluster book-vault \
  --service book-vault-service \
  --task-definition book-vault \
  --force-new-deployment \
  --profile book_vault \
  --region us-east-1
```

### Step 3.5: Monitor Deployment

```bash
# Watch deployment progress
aws ecs describe-services \
  --cluster book-vault \
  --services book-vault-service \
  --profile book_vault \
  --region us-east-1 \
  --query 'services[0].deployments[*].{status:status,running:runningCount,desired:desiredCount,taskDef:taskDefinition}'

# Wait for service to stabilize
aws ecs wait services-stable \
  --cluster book-vault \
  --services book-vault-service \
  --profile book_vault \
  --region us-east-1

# Verify health
curl -s https://bookvault.lionikis.com/api/health
```

### Step 3.6: Test the Application

After deployment, verify everything works:

1. **Web app**: Browse to https://bookvault.lionikis.com
2. **Login**: Test authentication
3. **Browse books**: Load the library
4. **Play audio**: Stream an audiobook
5. **iOS app**: Test if you have it installed

### Verification Checklist

- [ ] Backed up current task definition
- [ ] Created optimized task definition (0.25 vCPU, 512MB)
- [ ] Registered new task definition
- [ ] Deployed to ECS
- [ ] Health check passing
- [ ] Tested web app functionality
- [ ] Tested iOS app connectivity (if applicable)

### Rollback (If Needed)

If the app becomes slow or unresponsive:

```bash
# Find the previous task definition revision
aws ecs list-task-definitions \
  --family-prefix book-vault \
  --profile book_vault \
  --region us-east-1

# Roll back to previous revision (e.g., book-vault:2)
aws ecs update-service \
  --cluster book-vault \
  --service book-vault-service \
  --task-definition book-vault:PREVIOUS_REVISION \
  --force-new-deployment \
  --profile book_vault \
  --region us-east-1
```

---

## Phase 4: Fargate Spot with 2 Tasks (Recommended)

**Purpose**: Use spare AWS capacity at up to 70% discount with zero-downtime failover

**Time to implement**: 5 minutes

**Estimated savings**: Still significant savings while maintaining availability

### Why 2 Spot Tasks?

With a single Spot task, there's a 30-60 second gap during interruptions where no healthy targets exist (503 errors). Running 2 tasks eliminates this:

```
Single Task (has downtime):
[Task A] → [Task A draining, Task B starting] → [Task B]
           └─── 30-60 sec gap (503 errors) ───┘

Two Tasks (zero downtime):
[Task A + Task B] → [Task A draining, B healthy, C starting] → [Task B + Task C]
                    └─── No gap, Task B handles traffic ───┘
```

### Cost Comparison

| Strategy                     | Tasks | Monthly Cost | Downtime Risk                  |
| ---------------------------- | ----- | ------------ | ------------------------------ |
| Current (1 task, regular)    | 1     | ~$30         | None                           |
| 1 Spot task (0.25 vCPU)      | 1     | ~$2-3        | Brief 503s during interruption |
| **2 Spot tasks (0.25 vCPU)** | 2     | **~$5-6**    | **None (seamless failover)**   |

**Recommendation**: 2 Spot tasks at ~$5-6/month—still 80% cheaper than current setup, with zero downtime.

### Why 100% Spot Is Safe for This App

- All HTTP requests are short-lived (< 1 second)
- Audio streaming uses presigned S3 URLs (client → S3 directly)
- No long-running background jobs
- ALB automatically stops routing to draining tasks
- With 2 tasks, one is always available during interruptions

### Step 4.1: Verify Cluster Has Spot Provider

```bash
aws ecs describe-clusters \
  --clusters book-vault \
  --include SETTINGS \
  --profile book_vault \
  --region us-east-1 \
  --query 'clusters[0].capacityProviders'
```

Should show `["FARGATE", "FARGATE_SPOT"]`. If not, add it:

```bash
aws ecs put-cluster-capacity-providers \
  --cluster book-vault \
  --capacity-providers FARGATE FARGATE_SPOT \
  --default-capacity-provider-strategy capacityProvider=FARGATE,weight=1 \
  --profile book_vault \
  --region us-east-1
```

### Step 4.2: Update Service to Use 2 Spot Tasks

```bash
# Update to 100% Spot with 2 tasks for zero-downtime failover
aws ecs update-service \
  --cluster book-vault \
  --service book-vault-service \
  --desired-count 2 \
  --capacity-provider-strategy \
    capacityProvider=FARGATE_SPOT,weight=1,base=0 \
  --profile book_vault \
  --region us-east-1
```

### Step 4.3: Monitor Deployment

```bash
# Watch both tasks come up
aws ecs describe-services \
  --cluster book-vault \
  --services book-vault-service \
  --profile book_vault \
  --region us-east-1 \
  --query 'services[0].{desired:desiredCount,running:runningCount,pending:pendingCount}'

# Wait for service to stabilize
aws ecs wait services-stable \
  --cluster book-vault \
  --services book-vault-service \
  --profile book_vault \
  --region us-east-1

# Verify both tasks are healthy in target group
aws elbv2 describe-target-health \
  --target-group-arn $(aws elbv2 describe-target-groups \
    --names book-vault-tg \
    --profile book_vault \
    --region us-east-1 \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text) \
  --profile book_vault \
  --region us-east-1
```

### Step 4.4: Verify Configuration

```bash
# Check capacity provider strategy
aws ecs describe-services \
  --cluster book-vault \
  --services book-vault-service \
  --profile book_vault \
  --region us-east-1 \
  --query 'services[0].{capacityStrategy:capacityProviderStrategy,desiredCount:desiredCount,runningCount:runningCount}'
```

### Verification Checklist

- [ ] Cluster has FARGATE_SPOT capacity provider
- [ ] Service updated with Spot strategy
- [ ] Desired count set to 2
- [ ] Both tasks running and healthy
- [ ] Both targets healthy in ALB target group
- [ ] Tested application functionality

### Alternative: 1 Spot Task (If Cost Is Critical)

If you want absolute minimum cost and can tolerate occasional brief outages:

```bash
aws ecs update-service \
  --cluster book-vault \
  --service book-vault-service \
  --desired-count 1 \
  --capacity-provider-strategy \
    capacityProvider=FARGATE_SPOT,weight=1,base=0 \
  --profile book_vault \
  --region us-east-1
```

This saves ~$3/month but risks 30-60 second outages during Spot interruptions.

### Rollback to Regular Fargate

If you experience issues with Spot:

```bash
aws ecs update-service \
  --cluster book-vault \
  --service book-vault-service \
  --desired-count 1 \
  --capacity-provider-strategy \
    capacityProvider=FARGATE,weight=1,base=0 \
  --profile book_vault \
  --region us-east-1
```

---

## Projected Savings

### Before Optimization

| Component                     | Monthly Cost |
| ----------------------------- | ------------ |
| Fargate (1 vCPU, 2GB, 1 task) | ~$30         |
| ALB                           | ~$18         |
| RDS db.t3.micro               | ~$15         |
| S3 Standard (1TB)             | ~$23         |
| Data Transfer                 | ~$1          |
| **Total**                     | **~$87**     |

### After Optimization

| Component                                | Monthly Cost | Savings     |
| ---------------------------------------- | ------------ | ----------- |
| Fargate (0.25 vCPU, 0.5GB, 2 Spot tasks) | ~$5-6        | $24-25      |
| ALB                                      | ~$18         | $0          |
| RDS db.t3.micro                          | ~$15         | $0          |
| S3 Intelligent-Tiering (1TB)             | ~$8-12       | $11-15      |
| Data Transfer                            | ~$1          | $0          |
| **Total**                                | **~$47-52**  | **~$35-40** |

**Total savings: ~40-45%**

### Why 2 Tasks Is Worth It

For ~$3/month more than a single Spot task, you get:

- Zero downtime during Spot interruptions
- Better load distribution
- Seamless failover

This is the recommended configuration for production use.

---

## Monitoring & Verification

### Monthly Check (5 minutes)

Run this monthly to verify optimizations are working:

```bash
# 1. Check current spend vs budget
aws ce get-cost-and-usage \
  --time-period Start=$(date -v-1m +%Y-%m-01),End=$(date +%Y-%m-01) \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --profile book_vault \
  --query 'ResultsByTime[0].Total.BlendedCost.Amount'

# 2. Check S3 storage class distribution
aws s3api list-objects-v2 \
  --bucket book-vault-media \
  --query 'Contents[].StorageClass' \
  --output text \
  --profile book_vault \
  --region us-east-1 | tr '\t' '\n' | sort | uniq -c

# 3. Check Fargate task sizing
aws ecs describe-task-definition \
  --task-definition book-vault \
  --profile book_vault \
  --region us-east-1 \
  --query 'taskDefinition.{cpu:cpu,memory:memory}'

# 4. Check Spot configuration and task count
aws ecs describe-services \
  --cluster book-vault \
  --services book-vault-service \
  --profile book_vault \
  --region us-east-1 \
  --query 'services[0].{capacityStrategy:capacityProviderStrategy,desiredCount:desiredCount,runningCount:runningCount}'
```

### Cost Explorer Dashboard

View detailed cost breakdown in AWS Console:

1. Go to: https://console.aws.amazon.com/cost-management/home
2. Click **Cost Explorer**
3. Filter by tag or service to see Book Vault costs
4. Compare month-over-month

### CloudWatch Metrics to Watch

| Metric             | Location                | What to Watch        |
| ------------------ | ----------------------- | -------------------- |
| CPU Utilization    | ECS → Service → Metrics | Should be < 80%      |
| Memory Utilization | ECS → Service → Metrics | Should be < 80%      |
| S3 Bucket Size     | S3 → Bucket → Metrics   | Track growth         |
| ALB Request Count  | EC2 → Load Balancers    | Track usage patterns |

---

## Rollback Procedures

### Rollback S3 to Standard Storage

If you need faster access for all files:

```bash
# Remove lifecycle rule
aws s3api delete-bucket-lifecycle \
  --bucket book-vault-media \
  --profile book_vault \
  --region us-east-1

# Remove Intelligent-Tiering configuration
aws s3api delete-bucket-intelligent-tiering-configuration \
  --bucket book-vault-media \
  --id "ArchiveConfig" \
  --profile book_vault \
  --region us-east-1
```

**Note**: Existing objects in archive tiers need to be restored before access.

### Rollback Fargate Sizing

```bash
# Find previous task definition
aws ecs list-task-definitions \
  --family-prefix book-vault \
  --sort DESC \
  --profile book_vault \
  --region us-east-1

# Update to previous revision
aws ecs update-service \
  --cluster book-vault \
  --service book-vault-service \
  --task-definition book-vault:PREVIOUS_REVISION \
  --force-new-deployment \
  --profile book_vault \
  --region us-east-1
```

### Rollback Fargate Spot

```bash
aws ecs update-service \
  --cluster book-vault \
  --service book-vault-service \
  --capacity-provider-strategy \
    capacityProvider=FARGATE,weight=1,base=0 \
  --profile book_vault \
  --region us-east-1
```

---

## Implementation Checklist

Use this checklist when implementing:

### Phase 1: Billing Alerts

- [x] Created AWS Budget ($75 monthly limit)
- [x] Configured email alerts at 50%, 80%, 100%
- [x] Added forecasted cost alert at 100%
- [ ] Received confirmation email (check dlionikis@gmail.com)

### Phase 2: S3 Intelligent-Tiering

- [x] Created lifecycle rule for Intelligent-Tiering
- [x] Configured archive tier (90-day only, no Deep Archive)
- [x] Verified configuration
- [ ] Check storage class distribution (after 24-48 hours)

### Phase 3: Right-Size Fargate

- [x] Backed up current task definition (saved to /tmp/task-def-backup.json)
- [x] Created optimized task definition (0.25 vCPU, 512MB)
- [x] Registered new task definition (book-vault:3)
- [x] Deployed to ECS
- [x] Verified health check (200 OK, 0.19s response)
- [x] Tested web app functionality (all endpoints working)
- [ ] Test iOS app connectivity when available

### Phase 4: Fargate Spot (2 Tasks)

- [ ] Verified cluster has Spot provider
- [ ] Updated service to use 100% Spot
- [ ] Set desired count to 2
- [ ] Both tasks running and healthy
- [ ] Both targets healthy in ALB
- [ ] Tested functionality

### Post-Implementation

- [x] Verified budget is tracking (current spend: $0.68)
- [ ] Check first month's bill in February 2026
- [ ] Compare to previous costs and verify ~$35-40/month savings

---

## Questions?

Refer to:

- [aws-deployment-plan.md](aws-deployment-plan.md) - Original deployment documentation
- AWS Cost Explorer: https://console.aws.amazon.com/cost-management/home
- AWS Budgets: https://console.aws.amazon.com/billing/home#/budgets
