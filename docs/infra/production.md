# Book Vault - AWS Production Infrastructure

> Auto-generated infrastructure documentation from AWS API queries.
>
> **Generated**: 2026-03-01T21:33:57Z
> **Account ID**: 212477431339
> **Region**: us-east-1
> **Audit Version**: 1.0.0

---

## Overview

| Resource Type  | Count |
| -------------- | ----- |
| VPCs           | 1     |
| Subnets        | 6     |
| Load Balancers | 1     |
| ECS Clusters   | 1     |
| ECS Services   | 2     |
| RDS Instances  | 1     |
| S3 Buckets     | 1     |

### Architecture Summary

```
┌─────────────────────────────────────────────────────────────────────┐
│                         AWS Account: 212477431339              │
│                         Region: us-east-1                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   [Route53] → [ALB] → [ECS Fargate] → [RDS PostgreSQL]             │
│                           ↓                                         │
│                        [S3 Media]                                   │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## Entry Points

### Load Balancers (Public)

- **book-vault-alb**
  - DNS: `book-vault-alb-1714872234.us-east-1.elb.amazonaws.com`
  - Type: application
  - Listeners: HTTPS:443, HTTP:80

## Networking

### VPCs

#### vpc-0424cfb25685e00db

- **ID**: `vpc-0424cfb25685e00db`
- **CIDR**: `172.31.0.0/16`
- **Default**: True

### Subnets

| Name | ID                         | CIDR           | AZ         | Public? |
| ---- | -------------------------- | -------------- | ---------- | ------- |
| -    | `subnet-08192d0ff0c7ef37b` | 172.31.0.0/20  | us-east-1a | Yes     |
| -    | `subnet-0346e88f62cad493b` | 172.31.80.0/20 | us-east-1b | Yes     |
| -    | `subnet-0d81f2c892d4b8e3b` | 172.31.16.0/20 | us-east-1c | Yes     |
| -    | `subnet-093f52a651450b860` | 172.31.32.0/20 | us-east-1d | Yes     |
| -    | `subnet-016693a6c64df4b28` | 172.31.48.0/20 | us-east-1e | Yes     |
| -    | `subnet-00e1355be755bef46` | 172.31.64.0/20 | us-east-1f | Yes     |

### Security Groups

#### book-vault-ecs-sg (`sg-02ace66e9f98047f4`)

> ECS task security group for Book Vault

**Ingress Rules:**

- tcp port 8080 from `sg-000e1a271382a0a8b`

#### default (`sg-02e9566540bb36b73`)

> default VPC security group

**Ingress Rules:**

- -1 port None from `sg-02e9566540bb36b73`

#### book-vault-alb-sg (`sg-000e1a271382a0a8b`)

> ALB security group for Book Vault

⚠️ **Warning**: Has 0.0.0.0/0 ingress rules

**Ingress Rules:**

- tcp port 80 from `0.0.0.0/0`
- tcp port 443 from `0.0.0.0/0`

#### book-vault-rds-sg (`sg-0cf6ebf00112f6227`)

> Security group for Book Vault RDS

**Ingress Rules:**

- tcp port 5432 from `sg-02ace66e9f98047f4`

### Load Balancers

#### book-vault-alb

- **ARN**: `arn:aws:elasticloadbalancing:us-east-1:212477431339:loadbalancer/app/book-vault-alb/75fb398e9ed3d00c`
- **Type**: application
- **Scheme**: internet-facing
- **State**: active
- **VPC**: `vpc-0424cfb25685e00db`
- **AZs**: us-east-1b, us-east-1a, us-east-1c

## Compute

### ECS Clusters

#### book-vault

- **ARN**: `arn:aws:ecs:us-east-1:212477431339:cluster/book-vault`
- **Status**: ACTIVE
- **Running Tasks**: 2
- **Active Services**: 2
- **Capacity Providers**: FARGATE, FARGATE_SPOT

### ECS Services

#### book-vault-spot

- **Status**: ACTIVE
- **Desired/Running/Pending**: 2/2/0
- **Launch Type**: Capacity Provider
  - FARGATE_SPOT: weight=1, base=0
- **Task Definition**: `arn:aws:ecs:us-east-1:212477431339:task-definition/book-vault:3`
- **Load Balancers**:
  - Container `book-vault:8080`

#### book-vault-fallback

- **Status**: ACTIVE
- **Desired/Running/Pending**: 0/0/0
- **Launch Type**: Capacity Provider
  - FARGATE: weight=1, base=0
- **Task Definition**: `arn:aws:ecs:us-east-1:212477431339:task-definition/book-vault:3`
- **Load Balancers**:
  - Container `book-vault:8080`

### ECR Repositories

- **book-vault**: `212477431339.dkr.ecr.us-east-1.amazonaws.com/book-vault`

### Lambda Functions

- **book-vault-spot-fallback** (python3.12, 128MB)

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

#### book-vault-spot-recovery-check

- **State**: ENABLED
- **Schedule**: `rate(1 hour)`
- **Targets**:
  - lambda: `book-vault-spot-fallback`

#### book-vault-spot-task-stopped

- **State**: ENABLED
- **Event Pattern**: ECS task state change
- **Targets**:
  - lambda: `book-vault-spot-fallback`

### Spot Fallback Automation Flow

```
Spot task stops -> EventBridge -> Lambda (spot-fallback)
  -> checks Spot running count
  -> if 0: activates fallback on-demand service
  -> sends SNS alert

Hourly schedule -> EventBridge -> Lambda (spot-fallback)
  -> checks if Spot is back
  -> if yes: deactivates fallback service
  -> sends SNS alert
```

## Data Stores

### RDS Instances

#### book-vault-db

- **Engine**: postgres 15.14
- **Class**: db.t3.micro
- **Status**: available
- **Multi-AZ**: False
- **Storage**: 20GB gp2
- **Endpoint**: `book-vault-db.carekqk266tw.us-east-1.rds.amazonaws.com:5432`
- **Encrypted**: True
- **Public**: True
- **Backup Retention**: 7 days

### S3 Buckets

**Application Buckets:**

- `book-vault-media` (Region: us-east-1)

## Security & IAM

### IAM Roles (Compute-related)

- **AWSServiceRoleForECS**
  - Policy to enable Amazon ECS to manage your EC2 instances and related resources.
- **book-vault-ecs-execution**
- **book-vault-ecs-task**
- **book-vault-spot-fallback-lambda**

### Secrets Manager

| Secret Name                 | Description                                                 |
| --------------------------- | ----------------------------------------------------------- |
| `book-vault/database`       | Book Vault RDS PostgreSQL credentials                       |
| `book-vault/auth`           | Book Vault NextAuth configuration                           |
| `book-vault/prod/test-user` | Production test user credentials for Claude Code validation |

### SSL/TLS Certificates

- **bookvault.lionikis.com**
  - Status: ISSUED
  - Type: AMAZON_ISSUED
  - In use by: 1 resources

### Security Findings

- 🟡 **wide_open_sg** on `book-vault-alb-sg`
  - Allows tcp port 80 from 0.0.0.0/0
- 🟡 **wide_open_sg** on `book-vault-alb-sg`
  - Allows tcp port 443 from 0.0.0.0/0

## Observability

### CloudWatch Log Groups

- `/aws/lambda/book-vault-spot-fallback` (Retention: Never expire)
- `/ecs/book-vault` (Retention: Never expire)

## Known Gaps / Permissions Issues

No permission issues encountered.

## Maintenance

### How to Re-run the Audit

```bash
cd infra-audit
./audit.sh
```

### How to Update the Diagram

If you have Graphviz installed:

```bash
dot -Tsvg ../docs/infra/production.dot -o ../docs/infra/production.svg
```

Install Graphviz:

```bash
# macOS
brew install graphviz

# Ubuntu/Debian
apt install graphviz
```

### Viewing the Diagram

Open `docs/infra/production.svg` in a browser or SVG viewer.

---

_This document was auto-generated. Do not edit manually._
_Re-run the audit to update: `cd infra-audit && ./audit.sh`_
