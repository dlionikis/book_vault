# Database Reset Procedure

> **Purpose**: Step-by-step guide for resetting local and production databases when re-importing audiobook data.

**Last Updated**: January 2, 2026

---

## TL;DR

This document covers the complete database reset workflow:

1. Local testing with fresh test data
2. Migration consolidation (optional)
3. Production database reset
4. Data re-import and verification

**When to use**: After re-downloading/re-encoding audiobooks, fixing encoding issues, or when a clean slate is needed.

---

## Prerequisites

Before starting:

- [ ] New audiobook files are ready (local or uploaded to S3)
- [ ] Docker is running (`docker-compose up -d`)
- [ ] AWS CLI configured (for production steps)
- [ ] Session Manager Plugin installed (`brew install --cask session-manager-plugin`)

---

## Phase 1: Local Environment Reset

### Step 1.1: Clear Test Data

Remove existing test audiobooks:

```bash
rm -rf ./test-data/*
```

### Step 1.2: Copy Fresh Audiobooks

Copy sample audiobooks from your source directory:

```bash
# Copy 10 diverse books for testing
cp -R "/path/to/source/Book Name [ASIN]" test-data/
# Repeat for additional books...
```

**Recommended**: Include a mix of:

- Series books (to test sequence ordering)
- Standalone books
- Different authors/narrators

### Step 1.3: Verify File Structure

Each audiobook folder should contain:

```
Book Name [ASIN]/
├── Book Name [ASIN].m4b (or .mp3)
├── Book Name [ASIN].jpg
├── Book Name [ASIN].cue
├── Book Name [ASIN].metadata.json
└── Icon? (macOS metadata - ignored)
```

Verify with:

```bash
ls -la test-data/*/
```

---

## Phase 2: Database Reset (Local)

### Option A: Full Reset with Migration Consolidation

Use this when consolidating multiple migrations into a single initial schema:

```bash
# 1. Remove all existing migrations
rm -rf prisma/migrations/*

# 2. Reset database to match current schema
npx prisma db push --force-reset --accept-data-loss

# 3. Generate migration from current schema
TIMESTAMP=$(date +"%Y%m%d%H%M%S")
mkdir -p "prisma/migrations/${TIMESTAMP}_initial_schema"
npx prisma migrate diff --from-empty --to-schema-datamodel prisma/schema.prisma --script > "prisma/migrations/${TIMESTAMP}_initial_schema/migration.sql"

# 4. Mark migration as applied
npx prisma migrate resolve --applied ${TIMESTAMP}_initial_schema

# 5. Regenerate Prisma Client
npx prisma generate
```

### Option B: Simple Reset (Keep Existing Migrations)

Use this for routine resets:

```bash
npx prisma migrate reset --force
```

### Step 2.1: Seed Test User

```bash
npm run db:seed
```

Default credentials: `testuser` / `password123`

---

## Phase 3: Import and Verify (Local)

### Step 3.1: Run Import

```bash
npm run import
```

Expected output:

```
📚 Scanning directory: /Users/demetri/projects/book_vault/test-data
Found X folders to process
✅ Imported: Book Name 1
✅ Imported: Book Name 2
...
📊 Import Summary:
   ✅ Imported: X
   ⚠️  Skipped: 0
   ❌ Errors: 0
```

### Step 3.2: Verify Database Contents

```bash
# Check entity counts
docker exec book_vault_db psql -U postgres -d book_vault -c "
SELECT 'Books' as entity, COUNT(*) FROM books
UNION ALL SELECT 'Authors', COUNT(*) FROM authors
UNION ALL SELECT 'Series', COUNT(*) FROM series
UNION ALL SELECT 'Narrators', COUNT(*) FROM narrators
UNION ALL SELECT 'Chapters', COUNT(*) FROM chapters
ORDER BY entity;"
```

### Step 3.3: Verify Series Ordering

```bash
docker exec book_vault_db psql -U postgres -d book_vault -c "
SELECT b.title, s.title as series, bs.sequence
FROM books b
JOIN book_series bs ON b.id = bs.book_id
JOIN series s ON s.id = bs.series_id
ORDER BY s.title, bs.sequence;"
```

### Step 3.4: Test Application

```bash
npm run dev
```

1. Open http://localhost:3000
2. Login with test credentials
3. Verify books display correctly
4. Test playback and chapter navigation
5. Confirm chapters align with audio

---

## Phase 4: Production Reset

**IMPORTANT**: Only proceed after local validation passes.

### Step 4.1: Verify S3 Upload Complete

```bash
# Check files are uploaded
aws s3 ls s3://<your-bucket>/ --recursive | head -20

# Count total files
aws s3 ls s3://<your-bucket>/ --recursive | wc -l
```

### Step 4.2: Connect to Production Container

```bash
npm run db:connect
```

Or manually:

```bash
TASK_ID=$(aws ecs list-tasks --cluster <cluster-name> --service-name <service-name> \
  --region <region> --query 'taskArns[0]' --output text | awk -F'/' '{print $NF}')

aws ecs execute-command --cluster <cluster-name> --task "$TASK_ID" --container <container-name> \
  --command "/bin/sh" --interactive --region <region>
```

### Step 4.3: Reset Production Database

Inside the ECS container:

```bash
# Reset database
npx prisma db push --force-reset --accept-data-loss

# Mark migration as applied (use your migration timestamp)
npx prisma migrate resolve --applied YYYYMMDDHHMMSS_initial_schema
```

### Step 4.4: Create Test User with Production Password

**From your local machine** (not inside ECS):

```bash
# 1. Get password from Secrets Manager
CREDS=$(aws secretsmanager get-secret-value \
  --secret-id <your-secret-id> \
  --region <region> \
  --query 'SecretString' --output text)
PASSWORD=$(echo "$CREDS" | jq -r '.password')

# 2. Generate bcrypt hash
HASH=$(node -e "console.log(require('bcryptjs').hashSync('$PASSWORD', 10))")
echo "Generated hash for production user"
```

**Inside ECS container**, create the user with the hash:

```bash
# Note: new PrismaClient() is acceptable here only because this is a one-off
# emergency admin script run inside the container, not application code.
node -e "
const { PrismaClient } = require('@prisma/client');
(async () => {
  const p = new PrismaClient();
  await p.user.upsert({
    where: { username: 'testuser' },
    update: { passwordHash: '<paste-hash-here>' },
    create: {
      username: 'testuser',
      passwordHash: '<paste-hash-here>'
    }
  });
  console.log('Test user created/updated');
  await p.\$disconnect();
})();
"
```

### Step 4.5: Run Production Import

The import process for production depends on your setup:

**Option A**: If import script can access S3:

```bash
# Inside ECS container
npm run import
```

**Option B**: Run import separately based on your infrastructure

### Step 4.6: Verify Production

From your local machine:

```bash
# 1. Get credentials
CREDS=$(aws secretsmanager get-secret-value \
  --secret-id <your-secret-id> \
  --region <region> \
  --query 'SecretString' --output text)

# 2. Test login
curl -s -X POST "https://<your-domain>/api/auth/mobile/login" \
  -H "Content-Type: application/json" \
  -d "$CREDS"

# 3. Test books endpoint (use token from login response)
curl -s "https://<your-domain>/api/books" \
  -H "Authorization: Bearer <token>" | jq '.books | length'
```

---

## Troubleshooting

### Migration Errors

**Problem**: `A migration failed to apply`

**Solution**:

1. Check for duplicate migrations with similar names
2. Remove duplicates: `rm -rf prisma/migrations/<duplicate-folder>`
3. Re-run reset process

### Connection Issues (Production)

**Problem**: Cannot connect via ECS Exec

**Solution**:

1. Ensure Session Manager Plugin is installed: `brew install --cask session-manager-plugin`
2. Verify AWS credentials are configured
3. Check that ECS Exec is enabled on the service

### Import Failures

**Problem**: Import script fails or skips books

**Solution**:

1. Check file permissions on source directory
2. Validate JSON format of `.metadata.json` files
3. Check for special characters in filenames
4. Review import error messages for specific issues

---

## Checklist Summary

### Local Reset

- [ ] Test data cleared
- [ ] Fresh audiobooks copied
- [ ] Database reset
- [ ] Test user seeded
- [ ] Import successful
- [ ] Application tested locally

### Production Reset

- [ ] S3 upload complete
- [ ] Local validation passed
- [ ] Connected to ECS container
- [ ] Database reset
- [ ] Migration marked as applied
- [ ] Test user created with production password
- [ ] Import completed
- [ ] Production API verified

---

## Related Documentation

- [aws-deployment-reference.md](aws-deployment-reference.md) - AWS infrastructure & deploy commands
- [database-migration-guide.md](database-migration-guide.md) - Secure database migrations
- [testing.md](testing.md) - Complete testing guide
