# AWS Infrastructure Audit Toolkit

> Automated discovery and documentation of AWS production infrastructure for Book Vault.

## Overview

This toolkit queries AWS APIs to generate:

1. **Machine-readable inventory** (`out/summary.json`)
2. **Human-readable documentation** (`../docs/infra/production.md`)
3. **Infrastructure diagram** (`../docs/infra/production.dot` + `.svg`)

All operations are **read-only** - no changes are made to infrastructure.

## Prerequisites

### Required

- **AWS CLI v2** - [Installation guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- **jq** - JSON processor (`brew install jq`)
- **Python 3.8+** - For generating documentation and diagrams

### Optional

- **Graphviz** - For rendering diagrams (`brew install graphviz`)
  - Without it, only `.dot` source is generated

### AWS Authentication

The script uses standard AWS CLI authentication. Configure one of:

```bash
# Option 1: Environment variables
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_REGION="us-east-1"

# Option 2: AWS Profile
export AWS_PROFILE="book-vault-prod"

# Option 3: AWS SSO
aws sso login --profile book-vault-prod
export AWS_PROFILE="book-vault-prod"
```

### Required IAM Permissions

The audit requires read-only access. Attach `ReadOnlyAccess` managed policy or use this minimal policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "sts:GetCallerIdentity",
        "ec2:Describe*",
        "ecs:Describe*",
        "ecs:List*",
        "ecr:Describe*",
        "ecr:List*",
        "elasticloadbalancing:Describe*",
        "rds:Describe*",
        "s3:GetBucket*",
        "s3:ListBucket",
        "s3:ListAllMyBuckets",
        "route53:List*",
        "route53:Get*",
        "acm:Describe*",
        "acm:List*",
        "cloudfront:List*",
        "cloudfront:Get*",
        "iam:GetRole",
        "iam:GetRolePolicy",
        "iam:ListAttachedRolePolicies",
        "iam:ListRolePolicies",
        "iam:GetInstanceProfile",
        "secretsmanager:ListSecrets",
        "secretsmanager:DescribeSecret",
        "ssm:DescribeParameters",
        "logs:DescribeLogGroups",
        "cloudwatch:DescribeAlarms",
        "events:ListRules",
        "lambda:ListFunctions",
        "lambda:GetFunction",
        "sqs:ListQueues",
        "sns:ListTopics"
      ],
      "Resource": "*"
    }
  ]
}
```

## Usage

### Quick Start

```bash
cd infra-audit
./audit.sh
```

### Options

```bash
./audit.sh                    # Full audit with default region
./audit.sh --region us-west-2 # Override region
./audit.sh --dry-run          # Validate setup without running
./audit.sh --skip-diagram     # Skip Graphviz rendering
./audit.sh --help             # Show help
```

## Generated Outputs

### Raw AWS CLI Outputs (gitignored)

```
out/raw/
├── account-info.json        # AWS account details
├── vpcs.json                # VPC configurations
├── subnets.json             # Subnet details
├── security-groups.json     # Security group rules
├── load-balancers.json      # ALB/NLB configurations
├── ecs-clusters.json        # ECS cluster details
├── rds-instances.json       # Database instances
├── s3-buckets.json          # S3 bucket inventory
└── ...                      # Additional resources
```

### Processed Outputs

```
out/
├── summary.json             # Normalized inventory (machine-readable)
└── gaps.json                # Permission errors encountered

../docs/infra/
├── production.md            # Narrative documentation
├── production.dot           # Graphviz source
└── production.svg           # Rendered diagram (if graphviz installed)
```

## Schema: summary.json

```json
{
  "meta": {
    "account_id": "123456789012",
    "account_alias": "book-vault-prod",
    "region": "us-east-1",
    "generated_at": "2026-01-02T12:00:00Z",
    "audit_version": "1.0.0"
  },
  "networking": {
    "vpcs": [...],
    "subnets": [...],
    "route_tables": [...],
    "internet_gateways": [...],
    "nat_gateways": [...],
    "vpc_endpoints": [...],
    "security_groups": [...],
    "load_balancers": [...]
  },
  "compute": {
    "ec2_instances": [...],
    "auto_scaling_groups": [...],
    "ecs_clusters": [...],
    "ecs_services": [...],
    "ecr_repositories": [...],
    "lambda_functions": [...]
  },
  "data": {
    "rds_instances": [...],
    "rds_clusters": [...],
    "elasticache_clusters": [...],
    "s3_buckets": [...]
  },
  "edge": {
    "route53_zones": [...],
    "acm_certificates": [...],
    "cloudfront_distributions": [...]
  },
  "security": {
    "iam_roles": [...],
    "secrets": [...],
    "ssm_parameters": [...]
  },
  "observability": {
    "log_groups": [...],
    "alarms": [...],
    "event_rules": [...],
    "sqs_queues": [...],
    "sns_topics": [...]
  },
  "relationships": {
    "traffic_flows": [...],
    "security_findings": [...]
  },
  "gaps": {
    "permission_errors": [...],
    "missing_resources": [...]
  }
}
```

## How It Works

1. **Discovery Phase** (`audit.sh`)
   - Detects account and region
   - Runs AWS CLI commands for each resource type
   - Saves raw JSON to `out/raw/`
   - Records any permission errors

2. **Normalization Phase** (`lib/normalize.py`)
   - Parses raw JSON files
   - Extracts relevant fields
   - Infers relationships (ALB → targets, ECS → IAM, etc.)
   - Produces `out/summary.json`

3. **Generation Phase** (`lib/generate.py`)
   - Reads `summary.json`
   - Generates Markdown documentation
   - Generates Graphviz DOT diagram
   - Renders SVG if Graphviz is available

## Updating Infrastructure Docs

After any infrastructure changes:

```bash
cd infra-audit
./audit.sh
git add ../docs/infra/
git commit -m "docs: update infrastructure diagram"
```

## Troubleshooting

### "Access Denied" Errors

Check `out/gaps.json` for specific permission issues. Update IAM policy as needed.

### "command not found: jq"

```bash
brew install jq   # macOS
apt install jq    # Ubuntu/Debian
```

### Diagram Not Rendering

```bash
brew install graphviz   # macOS
apt install graphviz    # Ubuntu/Debian
```

Then re-run `./audit.sh` or manually:

```bash
dot -Tsvg ../docs/infra/production.dot -o ../docs/infra/production.svg
```

## Security Notes

- **No secrets are captured** - Only resource names/ARNs, never values
- **Read-only operations** - No infrastructure modifications
- **Raw outputs are gitignored** - Contains ARNs that could be sensitive
- **Review before committing** - Check `production.md` doesn't expose internal details you want private
