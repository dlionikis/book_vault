#!/bin/bash
#
# Run database migrations on local or production database
#
# Usage:
#   ./scripts/db-migrate.sh local [migration-file]      # Run on local database
#   ./scripts/db-migrate.sh production                  # Run pending migrations via ECS Exec
#   ./scripts/db-migrate.sh production <sql-file>       # Run SQL file via ECS Exec
#
# Prerequisites:
#   - For production: AWS CLI, Session Manager Plugin
#   - For local: psql, .env with DATABASE_URL
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ECS configuration
CLUSTER="book-vault"
SERVICE="book-vault-spot"
CONTAINER="book-vault"

# Shared TLS/exec plumbing for talking to RDS from inside a task.
# shellcheck source=scripts/lib/remote-pg.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/remote-pg.sh"

# Pin the CLI to the project's own prisma version for the *local* path, where a
# bare `npx prisma` would fetch the latest — possibly a different major than the
# one these migrations were authored against.
#
# Production does not use the CLI at all: the runtime image ships only the client
# runtime, and installing the CLI in the 512MB task OOMs. See
# run_production_migration.
#
# `package.json` is ESM now, so read it with fs rather than require().
PRISMA_VERSION=$(node -p "JSON.parse(require('fs').readFileSync('./package.json','utf8')).devDependencies.prisma.replace(/^[^0-9]*/, '')" 2>/dev/null)
if [ -z "$PRISMA_VERSION" ]; then
    log_error "Could not read prisma version from package.json"
    exit 1
fi

show_usage() {
    cat << EOF
Database Migration Script

Usage:
  $0 local                      Run 'prisma migrate deploy' on local database
  $0 local <sql-file>           Run SQL file on local database
  $0 production                 Run 'prisma migrate deploy' via ECS Exec
  $0 production <sql-file>      Run SQL file via ECS Exec (reads file locally, executes remotely)

Examples:
  $0 local
  $0 production
  $0 local prisma/migrations/20260102_fix/migration.sql
  $0 production prisma/migrations/20260102_fix/migration.sql

EOF
    exit 1
}

# Validate arguments
if [ -z "$1" ]; then
    show_usage
fi

ENVIRONMENT="$1"
MIGRATION_FILE="${2:-}"

if [ "$ENVIRONMENT" != "local" ] && [ "$ENVIRONMENT" != "production" ]; then
    log_error "Environment must be 'local' or 'production'"
    show_usage
fi

# Run migration on local database
run_local_migration() {
    log_info "Running migration on local database..."

    if [ ! -f ".env" ]; then
        log_error ".env file not found"
        exit 1
    fi

    # Load DATABASE_URL from .env
    export $(grep "^DATABASE_URL=" .env | xargs)

    if [ -z "$DATABASE_URL" ]; then
        log_error "DATABASE_URL not found in .env file"
        exit 1
    fi

    if [ -n "$MIGRATION_FILE" ]; then
        # Run specific SQL file
        if [ ! -f "$MIGRATION_FILE" ]; then
            log_error "Migration file not found: $MIGRATION_FILE"
            exit 1
        fi

        log_info "Running SQL file: $MIGRATION_FILE"
        psql "$DATABASE_URL" -f "$MIGRATION_FILE"
    else
        # Run prisma migrate deploy (pinned; locally this matches the installed
        # version anyway, but keep it consistent with the production path).
        log_info "Running: npx prisma@${PRISMA_VERSION} migrate deploy"
        npx --yes "prisma@${PRISMA_VERSION}" migrate deploy
    fi

    log_success "Migration completed successfully!"
}

# Run migration on production via ECS Exec
run_production_migration() {
    log_info "Running migration on production database via ECS Exec..."

    # Check prerequisites
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI not found. Install with: brew install awscli"
        exit 1
    fi

    if ! command -v session-manager-plugin &> /dev/null; then
        log_error "Session Manager Plugin not found."
        log_error "Install with: brew install --cask session-manager-plugin"
        exit 1
    fi

    TASK_ARN=$(remote_pg_task_arn "$CLUSTER" "$SERVICE") || exit 1
    log_info "Using task: ${TASK_ARN##*/}"

    if [ -n "$MIGRATION_FILE" ]; then
        # Run specific SQL file
        if [ ! -f "$MIGRATION_FILE" ]; then
            log_error "Migration file not found: $MIGRATION_FILE"
            exit 1
        fi

        log_info "Running SQL file: $MIGRATION_FILE"
        log_warn "Reading file locally and executing remotely..."

        SQL_CONTENT=$(cat "$MIGRATION_FILE")

        # Raw SQL goes through the `pg` driver: as of Prisma 7 the generated
        # client is TypeScript (lib/generated/prisma) and the production image
        # has no TS loader.
        #
        # The SQL is handed over as argv rather than pasted into a template
        # literal. The previous version escaped backticks and `$` with sed,
        # which still mangled any migration containing `${`, and silently
        # dropped the transaction — a multi-statement file that failed halfway
        # left the schema partly migrated.
        remote_pg_exec "$CLUSTER" "$SERVICE" "$CONTAINER" "
    const sql = process.argv[2];
    await client.query('BEGIN');
    try {
      const r = await client.query(sql);
      await client.query('COMMIT');
      console.log('Rows affected:', r.rowCount);
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    }
" "$SQL_CONTENT"
    else
        # Apply pending migrations as raw SQL, recording each in
        # _prisma_migrations exactly as `prisma migrate deploy` would.
        #
        # Why not the Prisma CLI: the runtime image ships only the client
        # runtime, so the CLI has to be fetched at run time — and installing it
        # inside the task OOMs. The task has 512MB total, shared with the
        # running Next.js server, so an `npm install` of the CLI is killed and
        # risks taking the serving process with it.
        #
        # The checksum is the sha256 of migration.sql, which is what Prisma
        # stores, so a later `migrate deploy` run from anywhere with a real CLI
        # sees these as applied rather than pending or drifted.
        log_info "Applying pending migrations via SQL (no CLI in the runtime image)"

        local applied_any=0
        local migration_dir name checksum sql
        for migration_dir in prisma/migrations/*/; do
            [ -f "${migration_dir}migration.sql" ] || continue
            name=$(basename "$migration_dir")
            checksum=$(shasum -a 256 "${migration_dir}migration.sql" | awk '{print $1}')
            sql=$(cat "${migration_dir}migration.sql")

            log_info "Checking ${name}..."
            local out
            out=$(remote_pg_exec "$CLUSTER" "$SERVICE" "$CONTAINER" "
    const [, , name, checksum, sql] = process.argv;
    const seen = await client.query(
      'SELECT finished_at FROM _prisma_migrations WHERE migration_name = \$1 AND rolled_back_at IS NULL',
      [name]
    );
    if (seen.rowCount > 0) {
      console.log('SKIP:already applied');
    } else {
      await client.query('BEGIN');
      try {
        await client.query(sql);
        await client.query(
          \`INSERT INTO _prisma_migrations
             (id, checksum, migration_name, started_at, finished_at, applied_steps_count)
           VALUES (gen_random_uuid()::text, \$1, \$2, now(), now(), 1)\`,
          [checksum, name]
        );
        await client.query('COMMIT');
        console.log('APPLIED:ok');
      } catch (err) {
        await client.query('ROLLBACK');
        throw err;
      }
    }
" "$name" "$checksum" "$sql" 2>&1)

            if echo "$out" | grep -q "APPLIED:ok"; then
                log_success "  applied ${name}"
                applied_any=1
            elif echo "$out" | grep -q "SKIP:already applied"; then
                log_info "  already applied"
            else
                log_error "  FAILED: ${name}"
                echo "$out" | grep -E "ERROR:|error" | head -5
                exit 1
            fi
        done

        if [ "$applied_any" -eq 0 ]; then
            log_info "No pending migrations to apply."
        fi
        log_success "Migration completed!"
    fi
}

# Main
case "$ENVIRONMENT" in
    local)
        run_local_migration
        ;;
    production)
        run_production_migration
        ;;
esac
