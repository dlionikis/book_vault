# ECS Spot Fallback Automation Plan

> **Created**: March 1, 2026
> **Status**: Planned
> **Priority**: High (addresses production outage risk)
> **Problem**: Twice in 2 months, Fargate Spot capacity became unavailable, causing full site outage for hours

---

## Overview

Book Vault runs on 2 Fargate Spot tasks for cost efficiency (~$20/month vs ~$60 for on-demand). Twice in the last two months, Spot capacity became unavailable in us-east-1, killing both tasks and leaving the site down for hours.

This plan adds automated fallback: a dormant on-demand service that a Lambda function activates only when Spot capacity is unavailable, then deactivates once Spot returns. You only pay for on-demand during actual outages.

### Current Architecture

```
book-vault-service
  └── 2x FARGATE_SPOT (weight=1)    ← both can be reclaimed simultaneously
```

### Target Architecture

```
book-vault-spot        → FARGATE_SPOT, desiredCount: 2    ← normal operation
book-vault-fallback    → FARGATE (on-demand), desiredCount: 0    ← dormant, wakes when Spot dies

Both services → same ALB target group → port 8080
```

### How It Works

```
Normal state (~99% of the time):
  spot: 2 running
  fallback: 0 running (dormant)
  Cost: ~$20/mo (Spot only)

Spot capacity lost:
  1. Both Spot tasks get killed, ECS can't provision replacements
  2. EventBridge detects Spot task stopped event
  3. Lambda checks: are there 0 Spot tasks running?
  4. Lambda sets fallback desiredCount = 1
  5. On-demand fallback starts (~60-90 seconds)
  6. Site back online on 1 on-demand task
  Cost: ~$20/mo + on-demand for duration of outage

Hourly recovery check (while fallback is active):
  1. EventBridge triggers Lambda every hour
  2. Lambda checks: is spot runningCount > 0?
  3. If yes → Spot is back, set fallback desiredCount = 0
  4. If no → keep fallback, check again next hour

Spot returns:
  1. ECS provisions new Spot tasks automatically
  2. Next hourly Lambda check detects spot runningCount > 0
  3. Lambda sets fallback desiredCount = 0
  4. Back to normal: 2 Spot, 0 on-demand
```

---

## Architecture Diagram

```
                    ┌─────────────────────────────┐
                    │      ALB (book-vault-alb)    │
                    │      Target Group: book-vault-tg
                    └──────────┬──────────────────┘
                               │
                 ┌─────────────┼─────────────┐
                 │             │             │
           ┌─────────┐  ┌─────────┐  ┌─────────────┐
           │ Spot #1  │  │ Spot #2  │  │  Fallback   │
           │ (active) │  │ (active) │  │ (dormant=0) │
           └─────────┘  └─────────┘  └─────────────┘
                                           │
                                     activated by
                                           │
                    ┌──────────────────────────────────┐
                    │  Lambda: book-vault-spot-fallback │
                    └──────────┬───────────────────────┘
                               │
                 triggered by  │
                 ┌─────────────┼─────────────┐
                 │                           │
    ┌────────────────────┐     ┌─────────────────────┐
    │ EventBridge:       │     │ EventBridge:         │
    │ Spot task stopped  │     │ Hourly recovery      │
    │ (immediate)        │     │ check (scheduled)    │
    └────────────────────┘     └─────────────────────┘
```

---

## Implementation

### Phase 1: Split Into Two Services

**Time estimate**: 2-3 hours

Migrate from one mixed service to two dedicated services without downtime.

#### Step 1: Capture current configuration

```bash
# Get current service details for reference
aws ecs describe-services \
  --cluster book-vault \
  --services book-vault-service \
  --profile book_vault \
  --region us-east-1 \
  --query 'services[0].{
    taskDef:taskDefinition,
    networkConfig:networkConfiguration,
    loadBalancers:loadBalancers,
    healthCheck:healthCheckGracePeriodSeconds
  }' \
  --output json
```

Note the subnet IDs, security group, and target group ARN from the output — you'll need them for the new services.

#### Step 2: Create `book-vault-spot` (primary, 2x Spot)

```bash
aws ecs create-service \
  --cluster book-vault \
  --service-name book-vault-spot \
  --task-definition book-vault \
  --desired-count 2 \
  --capacity-provider-strategy capacityProvider=FARGATE_SPOT,weight=1,base=0 \
  --network-configuration "awsvpcConfiguration={
    subnets=[SUBNET_1,SUBNET_2,SUBNET_3],
    securityGroups=[SECURITY_GROUP_ID],
    assignPublicIp=ENABLED
  }" \
  --load-balancers "targetGroupArn=TARGET_GROUP_ARN,containerName=book-vault,containerPort=8080" \
  --health-check-grace-period-seconds 120 \
  --enable-execute-command \
  --profile book_vault \
  --region us-east-1
```

#### Step 3: Create `book-vault-fallback` (dormant on-demand)

```bash
aws ecs create-service \
  --cluster book-vault \
  --service-name book-vault-fallback \
  --task-definition book-vault \
  --desired-count 0 \
  --capacity-provider-strategy capacityProvider=FARGATE,weight=1,base=0 \
  --network-configuration "awsvpcConfiguration={
    subnets=[SUBNET_1,SUBNET_2,SUBNET_3],
    securityGroups=[SECURITY_GROUP_ID],
    assignPublicIp=ENABLED
  }" \
  --load-balancers "targetGroupArn=TARGET_GROUP_ARN,containerName=book-vault,containerPort=8080" \
  --health-check-grace-period-seconds 120 \
  --enable-execute-command \
  --profile book_vault \
  --region us-east-1
```

#### Step 4: Verify new services are healthy

```bash
# Check all services
aws ecs describe-services \
  --cluster book-vault \
  --services book-vault-spot book-vault-fallback \
  --profile book_vault \
  --region us-east-1 \
  --query 'services[*].{
    name:serviceName,
    desired:desiredCount,
    running:runningCount,
    status:status
  }'

# Verify ALB sees 2 healthy targets (from spot service)
aws elbv2 describe-target-health \
  --target-group-arn TARGET_GROUP_ARN \
  --profile book_vault \
  --region us-east-1
```

Expected output: 2 healthy targets from `book-vault-spot`, 0 from `book-vault-fallback`.

#### Step 5: Decommission old service

Only after confirming the spot service has 2 running tasks:

```bash
# Scale down old service
aws ecs update-service \
  --cluster book-vault \
  --service book-vault-service \
  --desired-count 0 \
  --profile book_vault \
  --region us-east-1

# Wait ~2 minutes for tasks to drain, then delete
aws ecs delete-service \
  --cluster book-vault \
  --service book-vault-service \
  --force \
  --profile book_vault \
  --region us-east-1
```

#### Step 6: Update deploy script

Update `npm run deploy` / `scripts/deploy.sh` to deploy both services:

```bash
# Deploy to both services
# The fallback service (desiredCount: 0) won't spin up tasks,
# but updating its task definition ensures it uses the latest
# image when activated.
for SERVICE in book-vault-spot book-vault-fallback; do
  aws ecs update-service \
    --cluster book-vault \
    --service "$SERVICE" \
    --force-new-deployment \
    --profile book_vault \
    --region us-east-1
done
```

---

### Phase 2: Lambda Function

**Time estimate**: 2-3 hours

#### Lambda Code

```python
# lambda/spot_fallback.py
import json
import os
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

AWS_REGION = os.environ.get('AWS_REGION', 'us-east-1')
ecs = boto3.client('ecs', region_name=AWS_REGION)
sns = boto3.client('sns', region_name=AWS_REGION)

CLUSTER = os.environ['ECS_CLUSTER']
SPOT_SERVICE = os.environ['SPOT_SERVICE']
FALLBACK_SERVICE = os.environ['FALLBACK_SERVICE']
SNS_TOPIC_ARN = os.environ['SNS_TOPIC_ARN']


def get_service_info(service_name):
    """Get running and desired count for a service."""
    response = ecs.describe_services(
        cluster=CLUSTER,
        services=[service_name]
    )
    if response['services']:
        svc = response['services'][0]
        return {
            'running': svc['runningCount'],
            'desired': svc['desiredCount'],
            'pending': svc['pendingCount'],
        }
    return {'running': 0, 'desired': 0, 'pending': 0}


def set_desired_count(service_name, count):
    """Update the desired count for a service."""
    logger.info(f"Setting {service_name} desiredCount to {count}")
    ecs.update_service(
        cluster=CLUSTER,
        service=service_name,
        desiredCount=count
    )


def notify(subject, message):
    """Send SNS notification."""
    try:
        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=subject,
            Message=message
        )
    except Exception as e:
        logger.error(f"Failed to send SNS notification: {e}")


def handler(event, context):
    """
    Handles two triggers:
    1. EventBridge ECS task state change → Spot task stopped, check if fallback needed
    2. EventBridge hourly schedule → check if Spot is back, deactivate fallback

    Logic:
    - Spot running = 0 AND fallback desired = 0 → activate fallback
    - Spot running > 0 AND fallback desired > 0 → deactivate fallback
    - Otherwise → no action
    """
    logger.info(f"Event: {json.dumps(event, default=str)}")

    spot = get_service_info(SPOT_SERVICE)
    fallback = get_service_info(FALLBACK_SERVICE)

    logger.info(
        f"Spot: running={spot['running']}, pending={spot['pending']}, desired={spot['desired']} | "
        f"Fallback: running={fallback['running']}, desired={fallback['desired']}"
    )

    # Case 1: Spot is down, fallback is not active → activate fallback
    if spot['running'] == 0 and spot['pending'] == 0 and fallback['desired'] == 0:
        logger.info("🚨 Spot unavailable — activating on-demand fallback")
        set_desired_count(FALLBACK_SERVICE, 1)
        notify(
            "Book Vault: Spot Fallback Activated",
            f"Fargate Spot capacity is unavailable.\n"
            f"Activated on-demand fallback task.\n"
            f"Spot status: {spot['running']} running, {spot['pending']} pending\n"
            f"Hourly checks will deactivate fallback when Spot returns."
        )
        return {'action': 'activated_fallback', 'spot': spot}

    # Case 2: Spot is back, fallback is still active → deactivate fallback
    elif spot['running'] > 0 and fallback['desired'] > 0:
        logger.info("✅ Spot restored — deactivating on-demand fallback")
        set_desired_count(FALLBACK_SERVICE, 0)
        notify(
            "Book Vault: Spot Restored, Fallback Deactivated",
            f"Fargate Spot capacity has returned.\n"
            f"Spot status: {spot['running']} running\n"
            f"Deactivated on-demand fallback to save cost."
        )
        return {'action': 'deactivated_fallback', 'spot': spot}

    # Case 3: No action needed
    else:
        if spot['running'] > 0:
            state = "normal"
        elif fallback['running'] > 0:
            state = "fallback_active_waiting_for_spot"
        elif fallback['desired'] > 0 and fallback['running'] == 0:
            state = "fallback_starting"
        else:
            state = "spot_pending"

        logger.info(f"No action needed. State: {state}")
        return {'action': 'no_change', 'state': state, 'spot': spot, 'fallback': fallback}
```

#### Create IAM Role

```bash
# Create role
aws iam create-role \
  --role-name book-vault-spot-fallback-lambda \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "lambda.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }' \
  --profile book_vault

# CloudWatch Logs (for Lambda logging)
aws iam attach-role-policy \
  --role-name book-vault-spot-fallback-lambda \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
  --profile book_vault

# ECS + SNS permissions
aws iam put-role-policy \
  --role-name book-vault-spot-fallback-lambda \
  --policy-name SpotFallbackAccess \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "ecs:DescribeServices",
          "ecs:UpdateService"
        ],
        "Resource": "*",
        "Condition": {
          "StringEquals": {
            "ecs:cluster": "arn:aws:ecs:us-east-1:ACCOUNT_ID:cluster/book-vault"
          }
        }
      },
      {
        "Effect": "Allow",
        "Action": "sns:Publish",
        "Resource": "arn:aws:sns:us-east-1:ACCOUNT_ID:book-vault-spot-alerts"
      }
    ]
  }' \
  --profile book_vault
```

#### Deploy Lambda

```bash
# Package
cd lambda
zip spot_fallback.zip spot_fallback.py

# Create function
aws lambda create-function \
  --function-name book-vault-spot-fallback \
  --runtime python3.12 \
  --role arn:aws:iam::ACCOUNT_ID:role/book-vault-spot-fallback-lambda \
  --handler spot_fallback.handler \
  --zip-file fileb://spot_fallback.zip \
  --timeout 30 \
  --memory-size 128 \
  --architecture arm64 \
  --profile book_vault \
  --region us-east-1
```

> **Note**: Using `arm64` (Graviton) for 20% cost savings — not that it matters at this usage level, but good practice.

---

### Phase 3: EventBridge — Spot Task Stopped Trigger

**Time estimate**: 30 minutes

Fires the Lambda whenever a Spot task stops. The Lambda then checks whether fallback is needed (it may just be normal task cycling).

```bash
# Create rule matching Spot task stop events
aws events put-rule \
  --name book-vault-spot-task-stopped \
  --event-pattern '{
    "source": ["aws.ecs"],
    "detail-type": ["ECS Task State Change"],
    "detail": {
      "clusterArn": ["arn:aws:ecs:us-east-1:ACCOUNT_ID:cluster/book-vault"],
      "group": ["service:book-vault-spot"],
      "lastStatus": ["STOPPED"]
    }
  }' \
  --profile book_vault \
  --region us-east-1

# Point it at the Lambda
aws events put-targets \
  --rule book-vault-spot-task-stopped \
  --targets "Id=spot-fallback-lambda,Arn=arn:aws:lambda:us-east-1:ACCOUNT_ID:function:book-vault-spot-fallback" \
  --profile book_vault \
  --region us-east-1

# Grant EventBridge permission to invoke Lambda
aws lambda add-permission \
  --function-name book-vault-spot-fallback \
  --statement-id spot-task-stopped-trigger \
  --action lambda:InvokeFunction \
  --principal events.amazonaws.com \
  --source-arn arn:aws:events:us-east-1:ACCOUNT_ID:rule/book-vault-spot-task-stopped \
  --profile book_vault \
  --region us-east-1
```

---

### Phase 4: EventBridge — Hourly Recovery Check

**Time estimate**: 30 minutes

Runs every hour to detect when Spot capacity returns and deactivate the fallback.

```bash
# Create hourly schedule
aws events put-rule \
  --name book-vault-spot-recovery-check \
  --schedule-expression "rate(1 hour)" \
  --state ENABLED \
  --profile book_vault \
  --region us-east-1

# Point it at the same Lambda
aws events put-targets \
  --rule book-vault-spot-recovery-check \
  --targets "Id=spot-fallback-lambda,Arn=arn:aws:lambda:us-east-1:ACCOUNT_ID:function:book-vault-spot-fallback" \
  --profile book_vault \
  --region us-east-1

# Grant EventBridge permission
aws lambda add-permission \
  --function-name book-vault-spot-fallback \
  --statement-id hourly-recovery-check-trigger \
  --action lambda:InvokeFunction \
  --principal events.amazonaws.com \
  --source-arn arn:aws:events:us-east-1:ACCOUNT_ID:rule/book-vault-spot-recovery-check \
  --profile book_vault \
  --region us-east-1
```

---

### Phase 5: SNS Alerts

**Time estimate**: 15 minutes

Get notified when failover happens.

```bash
# Create topic
aws sns create-topic \
  --name book-vault-spot-alerts \
  --profile book_vault \
  --region us-east-1

# Subscribe your email
aws sns subscribe \
  --topic-arn arn:aws:sns:us-east-1:ACCOUNT_ID:book-vault-spot-alerts \
  --protocol email \
  --notification-endpoint YOUR_EMAIL \
  --profile book_vault \
  --region us-east-1
```

You'll receive an email to confirm the subscription. After confirming, you'll get notifications when:

- Fallback is activated (Spot unavailable)
- Fallback is deactivated (Spot restored)

---

## Edge Cases & Safety

### Race condition: Lambda fires during normal Spot task cycling

When a Spot task stops and ECS replaces it, there's a brief window where `runningCount = 1` (or 0 if both cycle at once). The Lambda handles this by checking `pending` count too — if tasks are pending, ECS is already provisioning replacements and no fallback is needed.

The Lambda only activates fallback when: `running == 0 AND pending == 0`. This means ECS has given up trying to provision Spot tasks.

### What if the Lambda itself fails?

The Lambda is stateless and idempotent — it can safely run multiple times. The hourly schedule acts as a safety net: even if the task-stopped trigger misses, the hourly check will catch the situation within an hour.

### What if fallback gets stuck on?

The hourly check will deactivate it as soon as Spot returns. If you want an additional safety net, add a CloudWatch alarm on the fallback service's running count — alert if it's been running for > 24 hours (Spot outages rarely last that long).

### Deployments

The deploy script pushes new images to both services. The fallback service (desiredCount: 0) won't launch any tasks, but its task definition updates so it uses the latest image when activated. If the fallback is currently active during a deployment, it will do a rolling update just like the spot service.

---

## Cost Analysis

### Normal Operation (Spot available, ~99% of the time)

| Component                                     | Monthly Cost   |
| --------------------------------------------- | -------------- |
| 2x Fargate Spot (1 vCPU, 2GB each)            | ~$20           |
| Lambda (hourly invocation + occasional event) | ~$0.00         |
| EventBridge rules                             | $0.00          |
| SNS (0 notifications)                         | $0.00          |
| **Total**                                     | **~$20/month** |

### During Spot Outage

| Component                       | Cost        |
| ------------------------------- | ----------- |
| 1x Fargate on-demand (fallback) | ~$0.04/hour |
| Lambda invocations              | ~$0.00      |
| SNS notifications               | ~$0.00      |

A 6-hour Spot outage adds ~$0.24 to your bill. Even a full 24-hour outage is only ~$1.

### Lambda Cost Detail

Lambda's permanent free tier never expires — every AWS account gets 1 million requests and 400,000 GB-seconds per month. Your usage: ~744 hourly invocations + a handful of event triggers = well under 1,000 invocations/month. Effectively $0.00.

### Comparison to Current Setup

| Config                                     | Monthly Cost | Downtime Risk                                 |
| ------------------------------------------ | ------------ | --------------------------------------------- |
| 2x Spot (old setup)                        | ~$20         | Hours of downtime when Spot unavailable       |
| 1 on-demand + 1 Spot (current)             | ~$40         | Low risk, but paying $20/mo extra permanently |
| **2x Spot + dormant fallback (this plan)** | **~$20**     | **~2 min downtime max**                       |

This plan gives you the cost of all-Spot with the reliability of having on-demand, at the expense of ~2 minutes of downtime during failover (vs hours currently).

---

## Testing

### Test 1: Simulate Spot loss (manual)

```bash
# Manually scale spot service to 0
aws ecs update-service \
  --cluster book-vault \
  --service book-vault-spot \
  --desired-count 0 \
  --profile book_vault \
  --region us-east-1

# Watch Lambda logs — should activate fallback within ~1-2 minutes
aws logs tail /aws/lambda/book-vault-spot-fallback --follow \
  --profile book_vault \
  --region us-east-1

# Verify fallback is running
aws ecs describe-services \
  --cluster book-vault \
  --services book-vault-fallback \
  --profile book_vault \
  --region us-east-1 \
  --query 'services[0].{desired:desiredCount,running:runningCount}'

# Check you received an SNS email

# Restore spot service
aws ecs update-service \
  --cluster book-vault \
  --service book-vault-spot \
  --desired-count 2 \
  --profile book_vault \
  --region us-east-1

# Wait for next hourly check (or invoke Lambda manually)
aws lambda invoke \
  --function-name book-vault-spot-fallback \
  --payload '{"source": "manual-test"}' \
  /tmp/lambda-response.json \
  --profile book_vault \
  --region us-east-1

cat /tmp/lambda-response.json
# Should show: {"action": "deactivated_fallback", ...}
```

### Test 2: Verify no false alarms

Normal Spot task cycling (e.g., during deployments) should NOT trigger the fallback. Deploy a new version and watch the Lambda logs — it should log "No action needed" as tasks cycle.

### Test 3: Verify site stays up during failover

1. Open `https://bookvault.lionikis.com` in a browser
2. Scale spot to 0 (simulating outage)
3. Site may blip for ~60-90 seconds while fallback starts
4. Refresh — site should be back
5. Restore spot, wait for hourly check, verify fallback deactivates

---

## Implementation Checklist

### Phase 1: Service Split (2-3 hours)

- [ ] Capture current service configuration
- [ ] Create `book-vault-spot` service (2x FARGATE_SPOT)
- [ ] Create `book-vault-fallback` service (desiredCount: 0, FARGATE)
- [ ] Verify 2 healthy targets in ALB
- [ ] Decommission old `book-vault-service`
- [ ] Update deploy script to target both services
- [ ] Test deploy pushes to both services
- [ ] Update `docs/infra/production.md`

### Phase 2: Lambda Function (2-3 hours)

- [ ] Create IAM role with ECS + SNS permissions
- [ ] Write and package Lambda function
- [ ] Deploy Lambda (Python 3.12, arm64, 128MB)
- [ ] Test Lambda manually via CLI invoke

### Phase 3: Spot Stopped Trigger (30 min)

- [ ] Create EventBridge rule for ECS task state change
- [ ] Add Lambda as target
- [ ] Grant invoke permission
- [ ] Verify rule matches Spot task stop events

### Phase 4: Hourly Recovery Check (30 min)

- [ ] Create EventBridge scheduled rule (rate: 1 hour)
- [ ] Add Lambda as target
- [ ] Grant invoke permission

### Phase 5: SNS Alerts (15 min)

- [ ] Create SNS topic
- [ ] Subscribe email
- [ ] Confirm subscription
- [ ] Verify notifications arrive during testing

### Post-Implementation

- [ ] Run full failover test (simulate Spot loss)
- [ ] Verify no false alarms during normal deploys
- [ ] Add Lambda logs and EventBridge rules to CloudWatch dashboard
- [ ] Update `docs/aws-deployment-reference.md` with new service names
- [ ] Update CLAUDE.md with new deploy targets
- [ ] Revert current setup from 1 on-demand + 1 Spot back to 2x Spot

---

## Phase 6: Expand Infra-Audit Toolkit

**Time estimate**: 2-3 hours

The existing `infra-audit` toolkit already queries Lambda functions and EventBridge rules, but the normalization and doc generation layers don't fully capture the automation relationships. After the Spot fallback is in place, expand the toolkit so `./audit.sh` documents the complete picture.

### Current Gaps

| Layer                  | What it does today                                                      | What's missing                                                                                                   |
| ---------------------- | ----------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| `audit.sh` (discovery) | Queries `lambda list-functions`, `events list-rules`                    | Doesn't query EventBridge targets (`events list-targets-by-rule`) or Lambda event source mappings                |
| `normalize.py`         | Lists Lambda by name/runtime/memory, EventBridge rules by name/schedule | Doesn't capture Lambda environment variables, IAM role, or EventBridge → Lambda target connections               |
| `generate.py`          | Lists Lambda under Compute, EventBridge under Observability             | Doesn't show automation relationships (e.g., "EventBridge rule X triggers Lambda Y which manages ECS service Z") |

### 6.1 Discovery Additions (`audit.sh`)

Add to the `discover_compute()` function:

```bash
# Lambda function details (environment, role, layers)
if [[ -f "${RAW_DIR}/lambda-functions.json" ]] && \
   jq -e '.Functions | length > 0' "${RAW_DIR}/lambda-functions.json" > /dev/null 2>&1; then
    local func_names=$(jq -r '.Functions[].FunctionName' "${RAW_DIR}/lambda-functions.json" 2>/dev/null || echo "")
    for func in $func_names; do
        aws_query "lambda-detail-${func}.json" lambda get-function --function-name "$func" || true
        aws_query "lambda-policy-${func}.json" lambda get-policy --function-name "$func" || true
    done
fi
```

Add to the `discover_observability()` function:

```bash
# EventBridge rule targets (which Lambda/SNS/SQS each rule triggers)
if [[ -f "${RAW_DIR}/event-rules.json" ]] && \
   jq -e '.Rules | length > 0' "${RAW_DIR}/event-rules.json" > /dev/null 2>&1; then
    local rule_names=$(jq -r '.Rules[].Name' "${RAW_DIR}/event-rules.json" 2>/dev/null || echo "")
    for rule in $rule_names; do
        aws_query "event-targets-${rule}.json" events list-targets-by-rule --rule "$rule" || true
    done
fi

# SNS topic subscriptions
if [[ -f "${RAW_DIR}/sns-topics.json" ]] && \
   jq -e '.Topics | length > 0' "${RAW_DIR}/sns-topics.json" > /dev/null 2>&1; then
    local topic_arns=$(jq -r '.Topics[].TopicArn' "${RAW_DIR}/sns-topics.json" 2>/dev/null || echo "")
    for arn in $topic_arns; do
        local topic_name=$(echo "$arn" | grep -oE '[^:]+$')
        aws_query "sns-subscriptions-${topic_name}.json" sns list-subscriptions-by-topic --topic-arn "$arn" || true
    done
fi
```

### 6.2 Normalization Additions (`normalize.py`)

Expand `_normalize_lambda()` to include richer detail:

```python
def _normalize_lambda(self) -> List[Dict]:
    """Normalize Lambda function data with triggers and targets."""
    data = load_json_file(self.raw_dir / "lambda-functions.json")
    if not data:
        return []

    functions = []
    for fn in data.get("Functions", []):
        func_name = fn.get("FunctionName", "")

        # Load detailed config if available
        detail = load_json_file(self.raw_dir / f"lambda-detail-{func_name}.json") or {}
        policy = load_json_file(self.raw_dir / f"lambda-policy-{func_name}.json") or {}

        # Parse resource-based policy to find triggers
        triggers = []
        if policy.get("Policy"):
            try:
                import json as json_mod
                pol = json_mod.loads(policy["Policy"])
                for stmt in pol.get("Statement", []):
                    source_arn = stmt.get("Condition", {}).get(
                        "ArnLike", {}
                    ).get("AWS:SourceArn", "")
                    if source_arn:
                        triggers.append({
                            "source": stmt.get("Principal", {}).get("Service", ""),
                            "source_arn": source_arn,
                            "statement_id": stmt.get("Sid", ""),
                        })
            except Exception:
                pass

        functions.append({
            "name": func_name,
            "arn": fn.get("FunctionArn"),
            "runtime": fn.get("Runtime"),
            "memory": fn.get("MemorySize"),
            "timeout": fn.get("Timeout"),
            "architecture": fn.get("Architectures", ["x86_64"])[0],
            "role": fn.get("Role", "").split("/")[-1],
            "description": fn.get("Description"),
            "last_modified": fn.get("LastModified"),
            "triggers": triggers,
        })

    return functions
```

Expand `_normalize_event_rules()` to include targets:

```python
def _normalize_event_rules(self) -> List[Dict]:
    """Normalize EventBridge rules with their targets."""
    data = load_json_file(self.raw_dir / "event-rules.json")
    if not data:
        return []

    rules = []
    for rule in data.get("Rules", []):
        rule_name = rule.get("Name", "")

        # Load targets for this rule
        targets_data = load_json_file(
            self.raw_dir / f"event-targets-{rule_name}.json"
        ) or {}
        targets = [
            {
                "id": t.get("Id"),
                "arn": t.get("Arn"),
                "type": self._infer_target_type(t.get("Arn", "")),
                "name": t.get("Arn", "").split(":")[-1] if t.get("Arn") else None,
            }
            for t in targets_data.get("Targets", [])
        ]

        rules.append({
            "arn": rule.get("Arn"),
            "name": rule_name,
            "description": rule.get("Description"),
            "state": rule.get("State"),
            "schedule": rule.get("ScheduleExpression"),
            "event_pattern": rule.get("EventPattern"),
            "targets": targets,
        })

    return rules


def _infer_target_type(self, arn: str) -> str:
    """Infer the target type from its ARN."""
    if ":function:" in arn:
        return "lambda"
    elif ":topic" in arn:
        return "sns"
    elif ":queue" in arn:
        return "sqs"
    elif ":stateMachine:" in arn:
        return "step_functions"
    return "unknown"
```

Expand SNS normalization to include subscriptions:

```python
def _normalize_sns(self) -> List[Dict]:
    """Normalize SNS topics with subscriptions."""
    data = load_json_file(self.raw_dir / "sns-topics.json")
    if not data:
        return []

    topics = []
    for topic in data.get("Topics", []):
        topic_arn = topic.get("TopicArn", "")
        topic_name = topic_arn.split(":")[-1]

        # Load subscriptions
        subs_data = load_json_file(
            self.raw_dir / f"sns-subscriptions-{topic_name}.json"
        ) or {}
        subscriptions = [
            {
                "protocol": s.get("Protocol"),
                "endpoint": s.get("Endpoint", "").split(":")[-1]
                    if s.get("Protocol") == "lambda"
                    else "(redacted)" if s.get("Protocol") == "email"
                    else s.get("Endpoint"),
            }
            for s in subs_data.get("Subscriptions", [])
        ]

        topics.append({
            "arn": topic_arn,
            "name": topic_name,
            "subscriptions": subscriptions,
        })

    return topics
```

### 6.3 Documentation Generation Additions (`generate.py`)

Add a new **Automation** section to the generated `production.md`:

````python
def _automation_section(self) -> str:
    """Generate automation section showing Lambda + EventBridge relationships."""
    lambdas = self.compute.get("lambda_functions", [])
    rules = self.observability.get("event_rules", [])

    if not lambdas and not rules:
        return ""

    lines = ["## Automation", ""]

    # Lambda Functions
    if lambdas:
        lines.append("### Lambda Functions")
        lines.append("")
        for fn in lambdas:
            lines.append(f"#### {fn.get('name')}")
            if fn.get('description'):
                lines.append(f"> {fn.get('description')}")
            lines.append(f"- **Runtime**: {fn.get('runtime')} ({fn.get('architecture')})")
            lines.append(f"- **Memory**: {fn.get('memory')}MB, Timeout: {fn.get('timeout')}s")
            lines.append(f"- **IAM Role**: `{fn.get('role')}`")

            # Show triggers
            if fn.get('triggers'):
                lines.append("- **Triggered by**:")
                for t in fn['triggers']:
                    source = t.get('source', '').replace('.amazonaws.com', '')
                    lines.append(f"  - {source}: `{t.get('statement_id')}`")
            lines.append("")

    # EventBridge Rules with targets
    if rules:
        book_vault_rules = [r for r in rules if 'book-vault' in r.get('name', '').lower()]
        if book_vault_rules:
            lines.append("### EventBridge Rules")
            lines.append("")
            for rule in book_vault_rules:
                lines.append(f"#### {rule.get('name')}")
                lines.append(f"- **State**: {rule.get('state')}")
                if rule.get('schedule'):
                    lines.append(f"- **Schedule**: `{rule.get('schedule')}`")
                if rule.get('event_pattern'):
                    lines.append(f"- **Event Pattern**: ECS task state change")
                if rule.get('targets'):
                    lines.append("- **Targets**:")
                    for t in rule['targets']:
                        lines.append(f"  - {t.get('type')}: `{t.get('name')}`")
                lines.append("")

    # Automation diagram (text)
    spot_rules = [r for r in rules if 'spot' in r.get('name', '').lower()]
    if spot_rules:
        lines.append("### Spot Fallback Automation Flow")
        lines.append("")
        lines.append("```")
        lines.append("Spot task stops → EventBridge → Lambda (spot-fallback)")
        lines.append("  → checks Spot running count")
        lines.append("  → if 0: activates fallback on-demand service")
        lines.append("  → sends SNS alert")
        lines.append("")
        lines.append("Hourly schedule → EventBridge → Lambda (spot-fallback)")
        lines.append("  → checks if Spot is back")
        lines.append("  → if yes: deactivates fallback service")
        lines.append("  → sends SNS alert")
        lines.append("```")
        lines.append("")

    return "\n".join(lines)
````

Add this method call to the `generate()` method, between the compute and data sections:

```python
def generate(self) -> str:
    sections = [
        self._header(),
        self._overview(),
        self._entry_points(),
        self._networking_section(),
        self._compute_section(),
        self._automation_section(),    # ← new
        self._data_section(),
        self._security_section(),
        self._observability_section(),
        self._gaps_section(),
        self._how_to_section()
    ]
    return "\n\n".join(filter(None, sections))
```

### 6.4 Expected Output in `production.md`

After these changes, running `./audit.sh` will produce a new Automation section:

````markdown
## Automation

### Lambda Functions

#### book-vault-spot-fallback

- **Runtime**: python3.12 (arm64)
- **Memory**: 128MB, Timeout: 30s
- **IAM Role**: `book-vault-spot-fallback-lambda`
- **Triggered by**:
  - events: `spot-task-stopped-trigger`
  - events: `hourly-recovery-check-trigger`

### EventBridge Rules

#### book-vault-spot-task-stopped

- **State**: ENABLED
- **Event Pattern**: ECS task state change
- **Targets**:
  - lambda: `book-vault-spot-fallback`

#### book-vault-spot-recovery-check

- **State**: ENABLED
- **Schedule**: `rate(1 hour)`
- **Targets**:
  - lambda: `book-vault-spot-fallback`

### Spot Fallback Automation Flow

\```
Spot task stops → EventBridge → Lambda (spot-fallback)
→ checks Spot running count
→ if 0: activates fallback on-demand service
→ sends SNS alert

Hourly schedule → EventBridge → Lambda (spot-fallback)
→ checks if Spot is back
→ if yes: deactivates fallback service
→ sends SNS alert
\```
````

### 6.5 IAM Permissions Update

The audit script's IAM policy already includes `lambda:ListFunctions`, `lambda:GetFunction`, and `events:ListRules`. Add these for the new queries:

```json
{
  "Action": ["lambda:GetPolicy", "events:ListTargetsByRule", "sns:ListSubscriptionsByTopic"],
  "Resource": "*"
}
```

### Phase 6 Checklist

- [ ] Add Lambda detail + policy queries to `audit.sh`
- [ ] Add EventBridge target queries to `audit.sh`
- [ ] Add SNS subscription queries to `audit.sh`
- [ ] Expand `_normalize_lambda()` with triggers and config
- [ ] Expand `_normalize_event_rules()` with targets
- [ ] Expand `_normalize_sns()` with subscriptions
- [ ] Add `_automation_section()` to `generate.py`
- [ ] Update IAM audit policy with new permissions
- [ ] Run `./audit.sh` and verify new Automation section in `production.md`
- [ ] Update `infra-audit/README.md` with new schema fields

---

## Implementation Checklist (Updated)

### Phase 1: Service Split (2-3 hours)

- [ ] Capture current service configuration
- [ ] Create `book-vault-spot` service (2x FARGATE_SPOT)
- [ ] Create `book-vault-fallback` service (desiredCount: 0, FARGATE)
- [ ] Verify 2 healthy targets in ALB
- [ ] Decommission old `book-vault-service`
- [ ] Update deploy script to target both services
- [ ] Test deploy pushes to both services

### Phase 2: Lambda Function (2-3 hours)

- [ ] Create IAM role with ECS + SNS permissions
- [ ] Write and package Lambda function
- [ ] Deploy Lambda (Python 3.12, arm64, 128MB)
- [ ] Test Lambda manually via CLI invoke

### Phase 3: Spot Stopped Trigger (30 min)

- [ ] Create EventBridge rule for ECS task state change
- [ ] Add Lambda as target
- [ ] Grant invoke permission

### Phase 4: Hourly Recovery Check (30 min)

- [ ] Create EventBridge scheduled rule (rate: 1 hour)
- [ ] Add Lambda as target
- [ ] Grant invoke permission

### Phase 5: SNS Alerts (15 min)

- [ ] Create SNS topic
- [ ] Subscribe email
- [ ] Confirm subscription

### Phase 6: Expand Infra-Audit (2-3 hours)

- [ ] Update `audit.sh` with Lambda detail, EventBridge target, and SNS subscription queries
- [ ] Update `normalize.py` with richer Lambda, EventBridge, and SNS normalization
- [ ] Add `_automation_section()` to `generate.py`
- [ ] Update audit IAM policy
- [ ] Run audit and verify output

### Post-Implementation

- [ ] Run full failover test (simulate Spot loss)
- [ ] Verify no false alarms during normal deploys
- [ ] Run `./audit.sh` to regenerate `production.md`
- [ ] Update `docs/aws-deployment-reference.md` with new service names
- [ ] Update CLAUDE.md with new deploy targets
- [ ] Revert current setup from 1 on-demand + 1 Spot back to 2x Spot

---

## Related Documents

- [aws-deployment-reference.md](./aws-deployment-reference.md) — Deploy commands and monitoring
- [infra/production.md](./infra/production.md) — Infrastructure inventory (needs update)
- [usage-dashboard-plan.md](./usage-dashboard-plan.md) — Dashboard will track Spot interruptions and fallback activations
