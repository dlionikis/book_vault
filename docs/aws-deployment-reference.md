# AWS Deployment Reference

> Quick reference for AWS deployment operations. For full deployment history and setup details, see [archive/aws-deployment-plan-full.md](archive/aws-deployment-plan-full.md).

**Live URL**: https://bookvault.lionikis.com
**Status**: Production (deployed December 31, 2025)

---

## Architecture

```
Browser/iOS → ALB (HTTPS) → ECS Fargate → RDS PostgreSQL
                                      ↓
                               S3 (media files)
```

| Component    | Details                                   |
| ------------ | ----------------------------------------- |
| **Hosting**  | ECS Fargate (1 vCPU, 2GB RAM)             |
| **Database** | RDS PostgreSQL (db.t3.micro)              |
| **Storage**  | S3 `book-vault-media` (514 GB, 691 books) |
| **Domain**   | bookvault.lionikis.com with ACM SSL       |

---

## Quick Deploy

For routine code deployments:

```bash
# One-command deploy (validates + builds + pushes + deploys)
npm run deploy

# Or step by step:
npm run deploy:dry-run          # Validate only
npm run deploy:only             # Skip validation, just deploy
```

### Manual Deploy Steps

```bash
# 1. Build for AWS (AMD64)
docker buildx build --platform linux/amd64 -t book-vault:amd64 --load .

# 2. Authenticate to ECR
ACCOUNT_ID=$(AWS_PROFILE=book_vault aws sts get-caller-identity --query 'Account' --output text)
AWS_PROFILE=book_vault aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com

# 3. Tag and push
docker tag book-vault:amd64 ${ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/book-vault:latest
docker push ${ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/book-vault:latest

# 4. Deploy to ECS
aws ecs update-service \
  --cluster book-vault \
  --service book-vault-service \
  --force-new-deployment \
  --profile book_vault \
  --region us-east-1
```

**Deployment time**: ~6-10 minutes (build → push → ECS rolling update)

---

## Database Operations

RDS is locked down - only accessible via ECS Exec.

### Prerequisites

```bash
brew install --cask session-manager-plugin
```

### Connect to Database

```bash
# Interactive shell in ECS container
npm run db:connect

# Or directly:
./scripts/db-connect.sh
```

### Run Migrations

```bash
# Apply pending migrations to production
npm run db:migrate:deploy production

# For local development
npm run db:migrate
```

---

## Monitoring

```bash
# Check service status
aws ecs describe-services \
  --cluster book-vault \
  --services book-vault-service \
  --profile book_vault \
  --region us-east-1 \
  --query 'services[0].deployments'

# View logs
aws logs tail /ecs/book-vault --follow --profile book_vault --region us-east-1

# Health check
curl -s https://bookvault.lionikis.com/api/health
```

---

## Secrets Management

Secrets are in AWS Secrets Manager:

| Secret                      | Purpose               |
| --------------------------- | --------------------- |
| `book-vault/database`       | DATABASE_URL          |
| `book-vault/auth`           | NEXTAUTH_SECRET       |
| `book-vault/prod/test-user` | Test user credentials |

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

## Rollback

```bash
# Deploy previous task definition revision
aws ecs update-service \
  --cluster book-vault \
  --service book-vault-service \
  --task-definition book-vault:PREVIOUS_REVISION \
  --profile book_vault \
  --region us-east-1
```

---

## Cost

~$65-70/month for personal use:

- ECS Fargate: ~$30
- ALB: ~$16-20
- RDS: ~$15
- S3: ~$12

---

## AWS CLI Profile

**Always use `--profile book_vault`** to avoid running commands against wrong AWS account.

```bash
# ✅ CORRECT
aws s3 ls --profile book_vault

# ❌ WRONG
aws s3 ls
```

---

## Full Documentation

For complete setup history, infrastructure details, and cleanup procedures, see:
[archive/aws-deployment-plan-full.md](archive/aws-deployment-plan-full.md)
