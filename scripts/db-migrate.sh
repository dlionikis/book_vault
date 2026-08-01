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

# The production runtime image ships only the Prisma client runtime, not the
# `prisma` CLI, so `npx prisma ...` in the container downloads the LATEST CLI —
# which may be a different major than the one this project's migrations were
# authored against. Pin the CLI to the project's own prisma version.
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

# Get a running task ARN
get_task_arn() {
    local task_arn
    task_arn=$(aws ecs list-tasks \
        --cluster "$CLUSTER" \
        --service-name "$SERVICE" \
        --desired-status RUNNING \
        --query 'taskArns[0]' \
        --output text 2>/dev/null)

    if [[ -z "$task_arn" || "$task_arn" == "None" ]]; then
        log_error "No running tasks found in service $SERVICE"
        exit 1
    fi

    echo "$task_arn"
}

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

    TASK_ARN=$(get_task_arn)
    log_info "Using task: ${TASK_ARN##*/}"

    if [ -n "$MIGRATION_FILE" ]; then
        # Run specific SQL file
        if [ ! -f "$MIGRATION_FILE" ]; then
            log_error "Migration file not found: $MIGRATION_FILE"
            exit 1
        fi

        log_info "Running SQL file: $MIGRATION_FILE"
        log_warn "Reading file locally and executing remotely..."

        # Read the SQL file and escape it for shell
        SQL_CONTENT=$(cat "$MIGRATION_FILE")

        # Execute via the `pg` driver. As of Prisma 7 the generated client is
        # TypeScript (lib/generated/prisma) and the production image has no TS
        # loader, so raw SQL goes through pg directly.
        aws ecs execute-command \
            --cluster "$CLUSTER" \
            --task "$TASK_ARN" \
            --container "$CONTAINER" \
            --command "node -e \"
const { Client } = require('pg');
const client = new Client({ connectionString: process.env.DATABASE_URL });
const sql = \\\`$(echo "$SQL_CONTENT" | sed 's/`/\\\\\\`/g' | sed 's/\$/\\\\$/g')\\\`;
client.connect()
    .then(() => client.query(sql))
    .then(r => {
        console.log('Rows affected:', r.rowCount);
        return client.end().then(() => process.exit(0));
    })
    .catch(e => {
        console.error('Error:', e.message);
        process.exit(1);
    });
\"" \
            --interactive
    else
        # Run prisma migrate deploy, pinned to the project's CLI version.
        log_info "Running: npx prisma@${PRISMA_VERSION} migrate deploy"

        # ECS Exec's session exit code reflects the *session*, not the remote
        # command — so a failed migration still exits 0 and would falsely print
        # "completed". Capture the output (tee so it's still visible live) and
        # verify Prisma's own success/failure markers before declaring success.
        local exec_output
        exec_output=$(aws ecs execute-command \
            --cluster "$CLUSTER" \
            --task "$TASK_ARN" \
            --container "$CONTAINER" \
            --command "npx --yes prisma@${PRISMA_VERSION} migrate deploy" \
            --interactive 2>&1 | tee /dev/tty)

        # Prisma prints "Error" / "P1012" etc. on failure; on success it prints
        # either "Applying migration" + "successfully applied" or, when nothing
        # is pending, "No pending migrations to apply".
        if echo "$exec_output" | grep -qiE "error|Validation Error|is no longer supported|P[0-9]{4}"; then
            log_error "Migration FAILED (see Prisma output above)."
            exit 1
        fi
        if ! echo "$exec_output" | grep -qiE "successfully applied|No pending migrations to apply|Database schema is up to date"; then
            log_error "Could not confirm migration success from Prisma output — treating as failure."
            exit 1
        fi
    fi

    log_success "Migration completed!"
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
