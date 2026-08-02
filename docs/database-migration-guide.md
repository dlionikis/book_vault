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

Apply all pending migrations:

```bash
./scripts/db-migrate.sh production
```

Or a single SQL file:

```bash
./scripts/db-migrate.sh production prisma/migrations/<migration-name>/migration.sql
```

### How It Works

The script connects through a running ECS task (`aws ecs execute-command`), so
credentials never leave AWS — the task already has `DATABASE_URL` in its
environment, and nothing is passed on the command line.

Pending migrations are applied as raw SQL, each in its own transaction, and
recorded in `_prisma_migrations` with the sha256 of `migration.sql` — the same
checksum Prisma stores. A later `prisma migrate deploy` from anywhere with a
real CLI therefore sees them as applied rather than pending or drifted.

### Why not `prisma migrate deploy` in the container?

Three constraints in the production environment rule it out, all worth knowing
before "simplifying" this back to a CLI call:

1. **No CLI in the image.** The runtime image ships only the Prisma client
   runtime, so the CLI would have to be fetched at run time.
2. **Fetching it OOMs the task.** The task has **512MB total**, shared with the
   running Next.js server. An `npm install` of the Prisma CLI is killed by the
   OOM reaper and risks taking the serving process down with it.
3. **`npx prisma` cannot load the config.** `prisma.config.ts` imports
   `defineConfig` from `prisma/config`, which is not resolvable from `/app`, so
   it fails with `Cannot find module 'prisma/config'`. Prisma 7 requires the
   config file (it no longer reads `url` from the datasource block), so
   `--schema` does not get around it.

`psql` is also not installed in the image.

### TLS is mandatory and not automatic

RDS refuses unencrypted connections, and since Prisma 7 handed connection
handling to the `pg` driver, TLS has to be configured explicitly. `sslmode=require`
does **not** work — as of pg 8.22 it verifies against the system trust store,
while RDS serves an Amazon-signed certificate. Verification needs Amazon's CA
explicitly (`certs/rds-global-bundle.pem`, shipped in the image).

All of this is handled by [`scripts/lib/remote-pg.sh`](../scripts/lib/remote-pg.sh),
which every production database script goes through. Two further traps it
absorbs: `package.json` is ESM, so `node -e "...require(...)"` fails and remote
snippets must be `.cjs` files; and those files must live under `/app` for
`require('pg')` to resolve.

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

### Manual Queries (If Needed)

Run ad-hoc SQL against production:

```bash
./scripts/db-connect.sh "SELECT count(*) FROM books"
```

Note there is **no direct psql route to production RDS**. The security group
allows the ECS task security group, not individual IPs, so `psql "$DATABASE_URL"`
from a laptop cannot connect — and `psql` is not installed in the container
either. `db-connect.sh` goes through a running task, which is why it works.

### Security Best Practices

1. ❌ **Never** hardcode passwords in scripts
2. ❌ **Never** commit credentials to git
3. ❌ **Never** pass passwords as CLI arguments (appears in process list)
4. ✅ **Always** use AWS Secrets Manager for production credentials
5. ✅ **Always** go through the scripts in `scripts/`, which read `DATABASE_URL`
   from the task environment inside AWS rather than moving credentials around
6. ✅ **Always** audit secret access via CloudTrail

### Verifying Migration

After running a migration, verify it was applied:

```bash
# Which migrations have been applied?
./scripts/db-connect.sh "SELECT migration_name, finished_at FROM _prisma_migrations ORDER BY finished_at DESC LIMIT 5"

# Does an expected column exist?
./scripts/db-connect.sh "SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'books'"
```

`\d`-style psql meta-commands are not available (no psql in the image); query
`information_schema` instead.

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
