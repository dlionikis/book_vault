#!/usr/bin/env bash
#
# Connect to production database via ECS Exec
#
# Usage: ./scripts/db-connect.sh [command]
#
# Examples:
#   ./scripts/db-connect.sh              # Interactive shell in container
#   ./scripts/db-connect.sh "SELECT 1"   # Run a single SQL query
#
# Prerequisites:
#   - AWS CLI configured with appropriate credentials
#   - Session Manager Plugin installed (brew install --cask session-manager-plugin)
#

set -euo pipefail

CLUSTER="book-vault"
SERVICE="book-vault-service"
CONTAINER="book-vault"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI not found. Install with: brew install awscli"
        exit 1
    fi

    if ! command -v session-manager-plugin &> /dev/null; then
        log_error "Session Manager Plugin not found."
        log_error "Install with: brew install --cask session-manager-plugin"
        exit 1
    fi
}

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

# Main
main() {
    check_prerequisites

    log_info "Finding running task in $SERVICE..."
    TASK_ARN=$(get_task_arn)
    log_info "Task: ${TASK_ARN##*/}"

    if [[ $# -gt 0 ]]; then
        # Run a specific SQL command
        SQL_COMMAND="$1"
        log_info "Running SQL command..."

        aws ecs execute-command \
            --cluster "$CLUSTER" \
            --task "$TASK_ARN" \
            --container "$CONTAINER" \
            --command "node -e \"
const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();
prisma.\$queryRawUnsafe(\\\`$SQL_COMMAND\\\`).then(r => {
    console.log(JSON.stringify(r, null, 2));
    process.exit(0);
}).catch(e => {
    console.error(e.message);
    process.exit(1);
});
\"" \
            --interactive
    else
        # Interactive shell
        log_info "Starting interactive shell..."
        log_warn "Note: psql is not installed in the container."
        log_warn "Use 'npx prisma studio' or Node.js for database access."
        echo ""

        aws ecs execute-command \
            --cluster "$CLUSTER" \
            --task "$TASK_ARN" \
            --container "$CONTAINER" \
            --command "/bin/sh" \
            --interactive
    fi
}

main "$@"
