# Database Migration Guide

## Running Migrations Securely

### Development (Local)

For local development, migrations are applied automatically via Prisma:

```bash
npx prisma migrate dev --name description_of_change
```

This will:

1. Create a new migration file
2. Apply it to your local database
3. Regenerate Prisma Client

### Production (RDS)

For production, use the secure migration script that retrieves credentials from AWS Secrets Manager:

```bash
./scripts/run-production-migration.sh prisma/migrations/<migration-name>/migration.sql
```

**Example:**

```bash
./scripts/run-production-migration.sh prisma/migrations/20260102_change_sequence_to_int/migration.sql
```

### How It Works

The script:

1. ✅ Retrieves credentials from AWS Secrets Manager (auditable, secure)
2. ✅ Parses the DATABASE_URL to extract connection details
3. ✅ Applies the migration using `psql`
4. ✅ Never exposes credentials in command history or logs

### Prerequisites

- AWS CLI configured with `book_vault` profile
- `jq` installed (`brew install jq`)
- `psql` client installed

### AWS Secrets Manager

Production credentials are stored in:

- **Secret Name**: `book-vault/database`
- **Region**: `us-east-1`
- **Contains**: Full `DATABASE_URL` connection string

To view the secret:

```bash
aws secretsmanager get-secret-value \
  --secret-id book-vault/database \
  --profile book_vault \
  --region us-east-1 \
  --query SecretString \
  --output text | jq '.'
```

### Manual Migration (If Needed)

If you need to run SQL manually on production:

```bash
# Retrieve DATABASE_URL
DATABASE_URL=$(aws secretsmanager get-secret-value \
  --secret-id book-vault/database \
  --profile book_vault \
  --region us-east-1 \
  --query SecretString \
  --output text | jq -r '.DATABASE_URL')

# Connect to database
psql "$DATABASE_URL"

# Or parse and connect manually
DB_PASS=$(echo "$DATABASE_URL" | sed -n 's|postgresql://[^:]*:\([^@]*\)@.*|\1|p')
DB_HOST=$(echo "$DATABASE_URL" | sed -n 's|postgresql://[^@]*@\([^:]*\):.*|\1|p')

PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U postgres -d book_vault
```

### Security Best Practices

1. ❌ **Never** hardcode passwords in scripts
2. ❌ **Never** commit credentials to git
3. ❌ **Never** pass passwords as CLI arguments (appears in process list)
4. ✅ **Always** use AWS Secrets Manager for production credentials
5. ✅ **Always** use `PGPASSWORD` environment variable
6. ✅ **Always** audit secret access via CloudTrail

### Verifying Migration

After running a migration, verify it was applied:

```bash
# Check table structure
./scripts/run-production-migration.sh <(echo "\d book_series")

# Or use the script with psql directly
DATABASE_URL=$(aws secretsmanager get-secret-value \
  --secret-id book-vault/database \
  --profile book_vault \
  --region us-east-1 \
  --query SecretString \
  --output text | jq -r '.DATABASE_URL')

psql "$DATABASE_URL" -c "\d book_series"
```

## Troubleshooting

### "jq: command not found"

```bash
brew install jq
```

### "psql: command not found"

```bash
brew install postgresql@15
```

### AWS CLI not configured

```bash
aws configure --profile book_vault
# Enter access key, secret key, and region (us-east-1)
```

### Migration already applied

If the migration was already applied manually, mark it as applied in Prisma's migration history (dev only):

```bash
npx prisma migrate resolve --applied <migration-name>
```
