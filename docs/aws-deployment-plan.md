# AWS Deployment Plan

> **Created**: December 30, 2025
> **Updated**: December 31, 2025
> **Status**: ✅ COMPLETE - Deployed to Production
> **Live URL**: https://bookvault.lionikis.com
> **Archived**: This plan is complete. Kept for reference and future maintenance.

## TL;DR

Deploy Book Vault to AWS using:

- **Hosting**: ECS Fargate (with Application Load Balancer)
- **Database**: RDS PostgreSQL
- **Storage**: S3 for media files + CloudFront CDN (optional)
- **Estimated Cost**: ~$65-70/month for personal use

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Pre-Deployment Checklist](#2-pre-deployment-checklist)
3. [Phase 1: S3 Media Storage](#phase-1-s3-media-storage) ✅
4. [Phase 2: RDS Database](#phase-2-rds-database) ✅
5. [Phase 3: ECS Fargate Deployment](#phase-3-ecs-fargate-deployment) ✅
6. [Phase 4: CloudFront CDN](#phase-4-cloudfront-cdn-optional)
7. [Phase 5: Domain & SSL](#phase-5-domain--ssl) ✅
8. [Environment Variables](#environment-variables)
9. [Cost Estimates](#cost-estimates)
10. [Rollback & Cleanup](#rollback--cleanup)

---

## 1. Architecture Overview

```
┌─────────────────┐         ┌─────────────────┐
│   Web Browser   │         │   iOS App       │
└────────┬────────┘         └────────┬────────┘
         │ HTTPS                     │ HTTPS
         └───────────┬───────────────┘
                     ▼
         ┌─────────────────┐
         │  CloudFront     │ ← CDN (images, static assets)
         │  (Optional)     │
         └────────┬────────┘
                  │
                  ▼
         ┌─────────────────┐
         │  Application    │ ← Routes traffic
         │  Load Balancer  │
         └────────┬────────┘
                  │
                  ▼
         ┌─────────────────┐
         │  ECS Fargate    │ ← Next.js Application
         │  (Container)    │
         └────────┬────────┘
                  │
        ┌─────────┴─────────┐
        ▼                   ▼
┌──────────────┐    ┌──────────────┐
│  RDS         │    │  S3 Bucket   │
│  PostgreSQL  │    │  (Media)     │
└──────────────┘    └──────────────┘
```

### Why ECS Fargate?

We chose ECS Fargate over App Runner for:

- **Better observability** - ALB provides detailed health check logs
- **Security group control** - Can verify and debug traffic flow
- **Native Secrets Manager** - Inject secrets directly as env vars
- **Container debugging** - Can exec into running containers
- **Mature platform** - Well-documented, battle-tested

---

## 2. Pre-Deployment Checklist

### AWS CLI Profile Requirement

**IMPORTANT**: Always use `--profile book_vault` with every AWS CLI command. Never assume the default profile.

```bash
# ✅ CORRECT - Always explicit
aws s3 ls --profile book_vault
aws ecs list-clusters --profile book_vault --region us-east-1

# ❌ WRONG - Never assume default
aws s3 ls
```

This prevents accidentally running commands against the wrong AWS account (e.g., work vs personal).

---

Before deploying, verify these are complete:

- [x] Prisma singleton pattern (`lib/db.ts`) - prevents connection exhaustion
- [x] S3 streaming support (`lib/s3.ts`) - range requests for audio
- [x] Environment variables standardized to AWS conventions
- [x] All tests passing (339 tests)
- [x] OpenAPI contract tests passing
- [x] AWS account created
- [x] AWS CLI installed and configured
- [x] Domain name ready (`bookvault.lionikis.com`)

---

## Phase 1: S3 Media Storage ✅

**Goal**: Upload audiobook files and cover images to S3

**Status**: Complete (December 30, 2025)

### Step 1.1: Create S3 Bucket

```bash
# Create bucket
aws s3 mb s3://book-vault-media \
  --profile book_vault \
  --region us-east-1

# Output: make_bucket: book-vault-media
```

### Step 1.2: Configure CORS (for browser/iOS access)

```bash
# Configure CORS for browser and iOS access
aws s3api put-bucket-cors \
  --bucket book-vault-media \
  --profile book_vault \
  --region us-east-1 \
  --cors-configuration '{
    "CORSRules": [
      {
        "AllowedOrigins": ["*"],
        "AllowedMethods": ["GET", "HEAD"],
        "AllowedHeaders": ["*"],
        "ExposeHeaders": ["Content-Length", "Content-Range", "Accept-Ranges"],
        "MaxAgeSeconds": 3600
      }
    ]
  }'
```

### Step 1.3: Upload Media Files

```bash
# Sync audio book directory to S3 (preserves folder structure)
# Excludes: .cue files, Icon files (macOS metadata), .DS_Store
aws s3 sync <AUDIO_BOOK_SOURCE_PATH> s3://book-vault-media/ \
  --exclude "*.cue" \
  --exclude "Icon*" \
  --exclude "Icon?" \
  --exclude ".DS_Store" \
  --profile book_vault \
  --region us-east-1

# Verify upload
aws s3 ls s3://book-vault-media/ --profile book_vault --region us-east-1 | head -20
```

**Note**: 477GB library at ~5 MB/s upload = ~27 hours. The `sync` command is stateless and resumable.

---

## Phase 2: RDS Database ✅

**Goal**: Set up managed PostgreSQL database

**Status**: Complete (December 30, 2025)

### Step 2.1: Create Security Group

```bash
# Create security group for RDS
aws ec2 create-security-group \
  --group-name book-vault-rds-sg \
  --description "Security group for Book Vault RDS" \
  --profile book_vault \
  --region us-east-1

# Output: <RDS_SG_ID>
```

### Step 2.2: Create RDS Instance

```bash
# Create RDS instance (db.t3.micro for personal use ~$15/month)
aws rds create-db-instance \
  --db-instance-identifier book-vault-db \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --engine-version 15 \
  --master-username postgres \
  --master-user-password "YOUR_STRONG_PASSWORD" \
  --allocated-storage 20 \
  --storage-type gp3 \
  --vpc-security-group-ids <RDS_SG_ID> \
  --db-name book_vault \
  --backup-retention-period 7 \
  --publicly-accessible \
  --storage-encrypted \
  --profile book_vault \
  --region us-east-1

# Wait for instance to become available (takes 5-10 minutes)
aws rds describe-db-instances \
  --db-instance-identifier book-vault-db \
  --profile book_vault \
  --region us-east-1 \
  --query 'DBInstances[0].[DBInstanceStatus,Endpoint.Address]' \
  --output text

# Output when ready:
# available  book-vault-db.<RDS_IDENTIFIER>.us-east-1.rds.amazonaws.com
```

### Step 2.3: Run Migrations

```bash
# Run Prisma migrations against production database
DATABASE_URL="postgresql://postgres:YOUR_PASSWORD@book-vault-db.<RDS_IDENTIFIER>.us-east-1.rds.amazonaws.com:5432/book_vault" \
  npx prisma migrate deploy

# Seed test user
DATABASE_URL="postgresql://postgres:YOUR_PASSWORD@book-vault-db.<RDS_IDENTIFIER>.us-east-1.rds.amazonaws.com:5432/book_vault" \
  npm run db:seed
```

### Production Connection String

```
DATABASE_URL=postgresql://postgres:YOUR_PASSWORD@book-vault-db.<RDS_IDENTIFIER>.us-east-1.rds.amazonaws.com:5432/book_vault
```

---

## Phase 3: ECS Fargate Deployment ✅

**Goal**: Deploy Next.js app to ECS Fargate with Application Load Balancer

**Status**: Complete (December 31, 2025)

### Existing Resources (Reusing)

| Resource           | Value                                                                |
| ------------------ | -------------------------------------------------------------------- |
| ECR Image          | `<AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/book-vault:latest` |
| RDS Endpoint       | `book-vault-db.<RDS_IDENTIFIER>.us-east-1.rds.amazonaws.com`         |
| S3 Bucket          | `book-vault-media`                                                   |
| Secrets            | `book-vault/database`, `book-vault/auth`                             |
| VPC                | `<VPC_ID>` (default)                                                 |
| RDS Security Group | `<RDS_SG_ID>`                                                        |

### Created Resources

| Resource           | ID/ARN                                                                                                                |
| ------------------ | --------------------------------------------------------------------------------------------------------------------- |
| ECS Cluster        | `book-vault`                                                                                                          |
| ECS Service        | `book-vault-service`                                                                                                  |
| Task Definition    | `book-vault:<REVISION>`                                                                                               |
| ALB                | `book-vault-alb` (`arn:aws:elasticloadbalancing:us-east-1:<AWS_ACCOUNT_ID>:loadbalancer/app/book-vault-alb/<ALB_ID>`) |
| ALB DNS            | `book-vault-alb-<RANDOM>.us-east-1.elb.amazonaws.com`                                                                 |
| Target Group       | `book-vault-tg` (`arn:aws:elasticloadbalancing:us-east-1:<AWS_ACCOUNT_ID>:targetgroup/book-vault-tg/<TG_ID>`)         |
| ALB Security Group | `<ALB_SG_ID>`                                                                                                         |
| ECS Security Group | `<ECS_SG_ID>`                                                                                                         |
| Execution Role     | `book-vault-ecs-execution`                                                                                            |
| Task Role          | `book-vault-ecs-task`                                                                                                 |
| SSL Certificate    | `arn:aws:acm:us-east-1:<AWS_ACCOUNT_ID>:certificate/<CERT_ID>`                                                        |

### Step 3.1: Code Changes (Already Complete)

**`next.config.js`** - Standalone output:

```javascript
const nextConfig = {
  output: 'standalone',
  // ... rest of config
};
```

**`prisma/schema.prisma`** - Alpine Linux binary target:

```prisma
generator client {
  provider      = "prisma-client-js"
  binaryTargets = ["native", "linux-musl-openssl-3.0.x"]
}
```

**`Dockerfile`** - Multi-stage build for AMD64, uses port 8080.

### Step 3.2: ECR Repository (Already Complete)

```bash
# Already created
# Repository: <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/book-vault
```

### Step 3.3: Build and Push Docker Image

```bash
# Create buildx builder for cross-platform builds (if not exists)
docker buildx create --use --name amd64builder 2>/dev/null || true

# Build for AMD64 and load into local Docker
docker buildx build --platform linux/amd64 -t book-vault:amd64 --load .

# Authenticate Docker to ECR
mkdir -p /tmp/docker-config
cat > /tmp/docker-config/config.json << 'EOF'
{
  "auths": {},
  "credsStore": "osxkeychain"
}
EOF

AWS_PROFILE=book_vault aws ecr get-login-password --region us-east-1 | \
  DOCKER_CONFIG=/tmp/docker-config docker login --username AWS \
  --password-stdin <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com

# Tag and push
docker tag book-vault:amd64 <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/book-vault:latest
DOCKER_CONFIG=/tmp/docker-config docker push <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/book-vault:latest
```

### Step 3.4: Create ECS Cluster

```bash
aws ecs create-cluster \
  --cluster-name book-vault \
  --capacity-providers FARGATE \
  --default-capacity-provider-strategy capacityProvider=FARGATE,weight=1 \
  --profile book_vault \
  --region us-east-1
```

### Step 3.5: Create IAM Roles

#### Task Execution Role (pulls images, reads secrets)

```bash
# Create the role with trust policy
aws iam create-role \
  --role-name book-vault-ecs-execution \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "ecs-tasks.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }' \
  --profile book_vault

# Attach the managed policy for ECR and CloudWatch
aws iam attach-role-policy \
  --role-name book-vault-ecs-execution \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy \
  --profile book_vault

# Add Secrets Manager access
aws iam put-role-policy \
  --role-name book-vault-ecs-execution \
  --policy-name SecretsManagerAccess \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": ["secretsmanager:GetSecretValue"],
      "Resource": "arn:aws:secretsmanager:us-east-1:<AWS_ACCOUNT_ID>:secret:book-vault/*"
    }]
  }' \
  --profile book_vault

# Add CloudWatch Logs access (required for container logging)
aws iam put-role-policy \
  --role-name book-vault-ecs-execution \
  --policy-name CloudWatchLogsAccess \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:us-east-1:<AWS_ACCOUNT_ID>:log-group:/ecs/*"
    }]
  }' \
  --profile book_vault
```

#### Task Role (runtime permissions - S3 access)

```bash
# Create the role
aws iam create-role \
  --role-name book-vault-ecs-task \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "ecs-tasks.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }' \
  --profile book_vault

# Add S3 read access
aws iam put-role-policy \
  --role-name book-vault-ecs-task \
  --policy-name S3ReadAccess \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::book-vault-media",
        "arn:aws:s3:::book-vault-media/*"
      ]
    }]
  }' \
  --profile book_vault
```

### Step 3.6: Create Security Groups

#### ALB Security Group (allows internet traffic)

```bash
aws ec2 create-security-group \
  --group-name book-vault-alb-sg \
  --description "ALB security group for Book Vault" \
  --vpc-id <VPC_ID> \
  --profile book_vault \
  --region us-east-1

# Note the SecurityGroupId from output (e.g., sg-xxxxxxxxx), then:

aws ec2 authorize-security-group-ingress \
  --group-id <ALB_SG_ID> \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0 \
  --profile book_vault \
  --region us-east-1

aws ec2 authorize-security-group-ingress \
  --group-id <ALB_SG_ID> \
  --protocol tcp \
  --port 443 \
  --cidr 0.0.0.0/0 \
  --profile book_vault \
  --region us-east-1
```

#### ECS Task Security Group (allows traffic from ALB)

```bash
aws ec2 create-security-group \
  --group-name book-vault-ecs-sg \
  --description "ECS task security group for Book Vault" \
  --vpc-id <VPC_ID> \
  --profile book_vault \
  --region us-east-1

# Note the SecurityGroupId from output, then allow traffic from ALB:

aws ec2 authorize-security-group-ingress \
  --group-id <ECS_SG_ID> \
  --protocol tcp \
  --port 8080 \
  --source-group <ALB_SG_ID> \
  --profile book_vault \
  --region us-east-1
```

#### Update RDS Security Group (allow ECS tasks)

```bash
aws ec2 authorize-security-group-ingress \
  --group-id <RDS_SG_ID> \
  --protocol tcp \
  --port 5432 \
  --source-group <ECS_SG_ID> \
  --profile book_vault \
  --region us-east-1
```

### Step 3.7: Create Application Load Balancer

#### Create the ALB

```bash
aws elbv2 create-load-balancer \
  --name book-vault-alb \
  --subnets <SUBNET_1> <SUBNET_2> <SUBNET_3> \
  --security-groups <ALB_SG_ID> \
  --scheme internet-facing \
  --type application \
  --ip-address-type ipv4 \
  --profile book_vault \
  --region us-east-1

# Note the LoadBalancerArn and DNSName from output
```

#### Create Target Group

```bash
aws elbv2 create-target-group \
  --name book-vault-tg \
  --protocol HTTP \
  --port 8080 \
  --vpc-id <VPC_ID> \
  --target-type ip \
  --health-check-protocol HTTP \
  --health-check-path /api/health \
  --health-check-interval-seconds 30 \
  --health-check-timeout-seconds 10 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 3 \
  --profile book_vault \
  --region us-east-1

# Note the TargetGroupArn from output
```

#### Create Listener

```bash
aws elbv2 create-listener \
  --load-balancer-arn <ALB_ARN> \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=forward,TargetGroupArn=<TARGET_GROUP_ARN> \
  --profile book_vault \
  --region us-east-1
```

### Step 3.8: Create Task Definition

First, get the auth secret ARN:

```bash
aws secretsmanager list-secrets \
  --profile book_vault \
  --region us-east-1 \
  --query 'SecretList[?Name==`book-vault/auth`].ARN' \
  --output text
```

Create `task-definition.json` in the project root:

```json
{
  "family": "book-vault",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "1024",
  "memory": "2048",
  "executionRoleArn": "arn:aws:iam::<AWS_ACCOUNT_ID>:role/book-vault-ecs-execution",
  "taskRoleArn": "arn:aws:iam::<AWS_ACCOUNT_ID>:role/book-vault-ecs-task",
  "containerDefinitions": [
    {
      "name": "book-vault",
      "image": "<AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/book-vault:latest",
      "essential": true,
      "portMappings": [
        {
          "containerPort": 8080,
          "hostPort": 8080,
          "protocol": "tcp"
        }
      ],
      "environment": [
        { "name": "NODE_ENV", "value": "production" },
        { "name": "PORT", "value": "8080" },
        { "name": "AWS_REGION", "value": "us-east-1" },
        { "name": "AWS_S3_BUCKET", "value": "book-vault-media" },
        { "name": "JWT_ACCESS_TOKEN_EXPIRY", "value": "3600" },
        { "name": "JWT_REFRESH_TOKEN_EXPIRY", "value": "2592000" },
        { "name": "MOBILE_CORS_ORIGIN", "value": "*" },
        { "name": "NEXTAUTH_URL", "value": "http://<ALB_DNS_NAME>" }
      ],
      "secrets": [
        {
          "name": "DATABASE_URL",
          "valueFrom": "arn:aws:secretsmanager:us-east-1:<AWS_ACCOUNT_ID>:secret:book-vault/database-<SUFFIX>:DATABASE_URL::"
        },
        {
          "name": "NEXTAUTH_SECRET",
          "valueFrom": "arn:aws:secretsmanager:us-east-1:<AWS_ACCOUNT_ID>:secret:book-vault/auth-<SUFFIX>:NEXTAUTH_SECRET::"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/book-vault",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "ecs",
          "awslogs-create-group": "true"
        }
      }
    }
  ]
}
```

Register the task definition:

```bash
aws ecs register-task-definition \
  --cli-input-json file://task-definition.json \
  --profile book_vault \
  --region us-east-1
```

### Step 3.9: Create ECS Service

```bash
aws ecs create-service \
  --cluster book-vault \
  --service-name book-vault-service \
  --task-definition book-vault \
  --desired-count 1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[<SUBNET_1>,<SUBNET_2>],securityGroups=[<ECS_SG_ID>],assignPublicIp=ENABLED}" \
  --load-balancers "targetGroupArn=<TARGET_GROUP_ARN>,containerName=book-vault,containerPort=8080" \
  --profile book_vault \
  --region us-east-1
```

### Step 3.10: Verify Deployment

```bash
# Check service status
aws ecs describe-services \
  --cluster book-vault \
  --services book-vault-service \
  --profile book_vault \
  --region us-east-1

# Check task status
aws ecs list-tasks --cluster book-vault --profile book_vault --region us-east-1
aws ecs describe-tasks --cluster book-vault --tasks <TASK_ARN> --profile book_vault --region us-east-1

# Check ALB health
aws elbv2 describe-target-health \
  --target-group-arn <TARGET_GROUP_ARN> \
  --profile book_vault \
  --region us-east-1

# View logs
aws logs tail /ecs/book-vault --follow --profile book_vault --region us-east-1

# Test the endpoint
curl http://<ALB_DNS_NAME>/api/health
```

---

## Phase 4: CloudFront CDN (Optional)

**Goal**: Cache images and static assets for faster loading

### Step 4.1: Create CloudFront Distribution

```bash
aws cloudfront create-distribution \
  --origin-domain-name book-vault-media.s3.us-east-1.amazonaws.com \
  --default-root-object index.html \
  --profile book_vault
```

### Step 4.2: Configure Cache Behaviors

- **Images (_.jpg, _.png)**: Cache for 1 year (images don't change)
- **Audio (_.mp3, _.m4a, \*.m4b)**: No cache (use S3 directly with range requests)

---

## Phase 5: Domain & SSL ✅

**Goal**: Configure custom domain with HTTPS

**Status**: Complete (December 31, 2025)

**Live URL**: https://bookvault.lionikis.com

### Step 5.1: Request SSL Certificate

```bash
aws acm request-certificate \
  --domain-name bookvault.lionikis.com \
  --validation-method DNS \
  --profile book_vault \
  --region us-east-1

# Output: arn:aws:acm:us-east-1:<AWS_ACCOUNT_ID>:certificate/<CERT_ID>
```

### Step 5.2: Get DNS Validation Record

```bash
aws acm describe-certificate \
  --certificate-arn <CERTIFICATE_ARN> \
  --profile book_vault \
  --region us-east-1 \
  --query 'Certificate.DomainValidationOptions[0].ResourceRecord'
```

### Step 5.3: Add DNS Records at Domain Registrar (Dreamhost)

Add these CNAME records:

**Record 1: SSL Certificate Validation**
| Field | Value |
|-------|-------|
| Type | CNAME |
| Name | `_e88945a577d6bdac26d0807c2a1143da.bookvault` |
| Value | `_71291e2c414bf606296faceaf1d884dc.jkddzztszm.acm-validations.aws` |

**Record 2: Subdomain → ALB**
| Field | Value |
|-------|-------|
| Type | CNAME |
| Name | `bookvault` |
| Value | `book-vault-alb-<RANDOM>.us-east-1.elb.amazonaws.com` |

### Step 5.4: Wait for Certificate Validation

```bash
# Check status (wait for ISSUED)
aws acm describe-certificate \
  --certificate-arn <CERTIFICATE_ARN> \
  --profile book_vault \
  --region us-east-1 \
  --query 'Certificate.Status'
```

### Step 5.5: Add HTTPS Listener to ALB

```bash
aws elbv2 create-listener \
  --load-balancer-arn <ALB_ARN> \
  --protocol HTTPS \
  --port 443 \
  --certificates CertificateArn=<CERTIFICATE_ARN> \
  --default-actions Type=forward,TargetGroupArn=<TARGET_GROUP_ARN> \
  --profile book_vault \
  --region us-east-1
```

### Step 5.6: Redirect HTTP to HTTPS

```bash
# Get HTTP listener ARN
aws elbv2 describe-listeners \
  --load-balancer-arn <ALB_ARN> \
  --profile book_vault \
  --region us-east-1 \
  --query 'Listeners[?Port==`80`].ListenerArn' \
  --output text

# Modify to redirect
aws elbv2 modify-listener \
  --listener-arn <HTTP_LISTENER_ARN> \
  --default-actions 'Type=redirect,RedirectConfig={Protocol=HTTPS,Port=443,StatusCode=HTTP_301}' \
  --profile book_vault \
  --region us-east-1
```

### Step 5.7: Update NEXTAUTH_URL in Task Definition

```bash
# Get current task definition, update NEXTAUTH_URL, and register new revision
aws ecs describe-task-definition \
  --task-definition book-vault \
  --profile book_vault \
  --region us-east-1 \
  --query 'taskDefinition' | \
  jq 'del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy) |
      .containerDefinitions[0].environment = [.containerDefinitions[0].environment[] | if .name == "NEXTAUTH_URL" then .value = "https://bookvault.lionikis.com" else . end]' | \
  aws ecs register-task-definition \
    --cli-input-json file:///dev/stdin \
    --profile book_vault \
    --region us-east-1

# Deploy new task definition
aws ecs update-service \
  --cluster book-vault \
  --service book-vault-service \
  --task-definition book-vault \
  --force-new-deployment \
  --profile book_vault \
  --region us-east-1
```

### Step 5.8: Verify

```bash
# Test HTTPS
curl -s https://bookvault.lionikis.com/api/health

# Test HTTP redirect
curl -s -o /dev/null -w "%{http_code} -> %{redirect_url}\n" http://bookvault.lionikis.com/
```

---

## Environment Variables

### Required for Production

| Variable          | Description            | Example                                 |
| ----------------- | ---------------------- | --------------------------------------- |
| `DATABASE_URL`    | RDS connection string  | `postgresql://user:pass@host:5432/db`   |
| `NEXTAUTH_URL`    | Public URL of your app | `https://bookvault.yourdomain.com`      |
| `NEXTAUTH_SECRET` | Random 32+ char secret | Generate with `openssl rand -base64 32` |
| `NODE_ENV`        | Environment            | `production`                            |
| `PORT`            | Container port         | `8080`                                  |
| `AWS_S3_BUCKET`   | S3 bucket name         | `book-vault-media`                      |
| `AWS_REGION`      | AWS region             | `us-east-1`                             |

### Optional

| Variable                   | Description                   | Default   |
| -------------------------- | ----------------------------- | --------- |
| `CLOUDFRONT_DOMAIN`        | CloudFront domain for images  | (none)    |
| `JWT_ACCESS_TOKEN_EXPIRY`  | Mobile token expiry (seconds) | `3600`    |
| `JWT_REFRESH_TOKEN_EXPIRY` | Mobile refresh token expiry   | `2592000` |
| `MOBILE_CORS_ORIGIN`       | CORS origin for mobile        | `*`       |

### Secrets Manager

Secrets are stored in AWS Secrets Manager and injected into the container by ECS:

| Secret                | ARN                                                                                     |
| --------------------- | --------------------------------------------------------------------------------------- |
| `book-vault/database` | `arn:aws:secretsmanager:us-east-1:<AWS_ACCOUNT_ID>:secret:book-vault/database-<SUFFIX>` |
| `book-vault/auth`     | `arn:aws:secretsmanager:us-east-1:<AWS_ACCOUNT_ID>:secret:book-vault/auth-<SUFFIX>`     |

#### View/Update Secrets

```bash
# View a secret
aws secretsmanager get-secret-value \
  --secret-id book-vault/database \
  --profile book_vault \
  --region us-east-1

# Update a secret
aws secretsmanager update-secret \
  --secret-id book-vault/database \
  --secret-string '{"DATABASE_URL":"new-value"}' \
  --profile book_vault \
  --region us-east-1
```

---

## Cost Estimates

### ECS Fargate Setup (~$65-70/month)

| Service                   | Spec                        | Monthly Cost |
| ------------------------- | --------------------------- | ------------ |
| Fargate                   | 1 vCPU, 2GB RAM (always-on) | ~$30         |
| Application Load Balancer | -                           | ~$16-20      |
| RDS PostgreSQL            | db.t3.micro, 20GB           | ~$15         |
| S3 Storage                | ~500GB                      | ~$11.50      |
| S3 Data Transfer          | 10GB/month                  | ~$0.90       |
| **Total**                 |                             | **~$65-75**  |

### Notes

- S3 storage: $0.023/GB/month
- S3 data transfer: $0.09/GB (first 10TB)
- RDS: Pay for instance + storage
- Fargate: Pay for vCPU-hours + GB-hours
- ALB: $0.0225/hour + LCU charges

---

## Rollback & Cleanup

### Rollback to Previous Image

```bash
# Update service to use a specific image tag
aws ecs update-service \
  --cluster book-vault \
  --service book-vault-service \
  --task-definition book-vault:PREVIOUS_REVISION \
  --profile book_vault \
  --region us-east-1
```

### Full Cleanup (Delete Everything)

**Order matters!** Delete in this sequence to avoid dependency errors.

```bash
# 1. Delete ECS service (set desired count to 0 first)
aws ecs update-service --cluster book-vault --service book-vault-service --desired-count 0 --profile book_vault --region us-east-1
aws ecs delete-service --cluster book-vault --service book-vault-service --force --profile book_vault --region us-east-1

# 2. Deregister task definitions (mark as INACTIVE)
aws ecs deregister-task-definition --task-definition book-vault:1 --profile book_vault --region us-east-1
aws ecs deregister-task-definition --task-definition book-vault:2 --profile book_vault --region us-east-1

# 3. Delete cluster
aws ecs delete-cluster --cluster book-vault --profile book_vault --region us-east-1

# 4. Delete ALB listeners (must delete before ALB)
# HTTPS listener
aws elbv2 delete-listener \
  --listener-arn <HTTPS_LISTENER_ARN> \
  --profile book_vault --region us-east-1

# HTTP listener
aws elbv2 delete-listener \
  --listener-arn <HTTP_LISTENER_ARN> \
  --profile book_vault --region us-east-1

# 5. Delete ALB and Target Group
aws elbv2 delete-load-balancer \
  --load-balancer-arn <ALB_ARN> \
  --profile book_vault --region us-east-1

# Wait for ALB to be deleted (check with describe-load-balancers), then delete target group
aws elbv2 delete-target-group \
  --target-group-arn <TARGET_GROUP_ARN> \
  --profile book_vault --region us-east-1

# 6. Delete security groups (after ALB is deleted)
aws ec2 delete-security-group --group-id <ECS_SG_ID> --profile book_vault --region us-east-1  # ECS SG
aws ec2 delete-security-group --group-id <ALB_SG_ID> --profile book_vault --region us-east-1  # ALB SG

# 7. Delete IAM roles (must remove policies first)
aws iam delete-role-policy --role-name book-vault-ecs-execution --policy-name SecretsManagerAccess --profile book_vault
aws iam delete-role-policy --role-name book-vault-ecs-execution --policy-name CloudWatchLogsAccess --profile book_vault
aws iam detach-role-policy --role-name book-vault-ecs-execution --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy --profile book_vault
aws iam delete-role --role-name book-vault-ecs-execution --profile book_vault
aws iam delete-role-policy --role-name book-vault-ecs-task --policy-name S3ReadAccess --profile book_vault
aws iam delete-role --role-name book-vault-ecs-task --profile book_vault

# 8. Delete CloudWatch log group
aws logs delete-log-group --log-group-name /ecs/book-vault --profile book_vault --region us-east-1

# 9. Delete SSL certificate (optional, can keep for future use)
aws acm delete-certificate \
  --certificate-arn <CERTIFICATE_ARN> \
  --profile book_vault --region us-east-1
```

---

## Deployment Checklist

### Phase 1: S3 ✅

- [x] S3 bucket created (`book-vault-media`)
- [x] CORS configured for browser/iOS
- [x] Media files uploading (477GB)

### Phase 2: RDS ✅

- [x] Security group created (`<RDS_SG_ID>`)
- [x] RDS instance created (`book-vault-db.<RDS_IDENTIFIER>.us-east-1.rds.amazonaws.com`)
- [x] Migrations run successfully (5 migrations, 17 tables)
- [x] Test user seeded (credentials in .env)
- [x] Secrets Manager configured

### Phase 3: ECS Fargate ✅

- [x] Dockerfile created (multi-stage, AMD64)
- [x] ECR repository created
- [x] Image built and pushed
- [x] ECS cluster created (`book-vault`)
- [x] IAM roles created (`book-vault-ecs-execution`, `book-vault-ecs-task`)
- [x] Security groups created (ALB: `<ALB_SG_ID>`, ECS: `<ECS_SG_ID>`)
- [x] ALB + Target Group created
- [x] Task definition registered (`book-vault:2`)
- [x] ECS service running (`book-vault-service`)
- [x] Health check passing

### Phase 4: CloudFront (Optional)

- [ ] CloudFront distribution created

### Phase 5: Domain & SSL ✅

- [x] Custom domain configured (`bookvault.lionikis.com`)
- [x] SSL certificate issued (`<CERTIFICATE_ARN>`)
- [x] HTTPS listener added to ALB
- [x] HTTP → HTTPS redirect configured
- [x] NEXTAUTH_URL updated

### Post-Deployment ✅

- [x] Test login flow
- [x] Test audio playback (with presigned S3 URLs)
- [x] Test iOS app connectivity (cover images + downloads working)
- [x] Monitor logs for errors
- [ ] Set up billing alerts (optional)

---

## Completion Summary

**Deployed**: December 31, 2025

### S3 Media Storage

- **Total Size**: 513.6 GB (2,781 files)
- **Books**: 691 audiobooks
- **Content**: Audio files (.mp3/.m4b), cover images (.jpg), metadata (.json)

### Key Learnings

1. **IAM Task Roles**: ECS Fargate uses `AWS_CONTAINER_CREDENTIALS_RELATIVE_URI` for credentials, not explicit `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`. Fixed in [lib/s3.ts](../lib/s3.ts) to support both modes.

2. **Presigned URLs**: S3 bucket is private (correct). API generates 1-hour presigned URLs for secure media access. iOS caches covers by book ID to avoid cache misses on URL expiry.

3. **Cross-Platform Build**: Apple Silicon (M1/M2) requires `docker buildx` with `--platform linux/amd64` for ECS Fargate compatibility.

### Related PRs

- **#50**: AWS Deployment (ECS Fargate, RDS, S3, Domain/SSL)
- **#51**: Presigned URL Implementation (S3 media access, IAM task role fix)

---

## Questions?

Refer to:

- [architecture.md](architecture.md) - System design
- [api-quick-ref.md](api-quick-ref.md) - API endpoints
- AWS Documentation for specific services
