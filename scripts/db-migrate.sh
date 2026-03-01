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
        # Run prisma migrate deploy
        log_info "Running: npx prisma migrate deploy"
        npx prisma migrate deploy
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

        # Execute via node/prisma's $executeRawUnsafe
        aws ecs execute-command \
            --cluster "$CLUSTER" \
            --task "$TASK_ARN" \
            --container "$CONTAINER" \
            --command "node -e \"
const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();
const sql = \\\`$(echo "$SQL_CONTENT" | sed 's/`/\\\\\\`/g' | sed 's/\$/\\\\$/g')\\\`;
prisma.\\\$executeRawUnsafe(sql).then(r => {
    console.log('Rows affected:', r);
    process.exit(0);
}).catch(e => {
    console.error('Error:', e.message);
    process.exit(1);
});
\"" \
            --interactive
    else
        # Run prisma migrate deploy
        log_info "Running: npx prisma migrate deploy"

        aws ecs execute-command \
            --cluster "$CLUSTER" \
            --task "$TASK_ARN" \
            --container "$CONTAINER" \
            --command "npx prisma migrate deploy" \
            --interactive
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
