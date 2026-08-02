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
SERVICE="book-vault-spot"
CONTAINER="book-vault"

# Shared TLS/exec plumbing for talking to RDS from inside a task.
# shellcheck source=scripts/lib/remote-pg.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/remote-pg.sh"

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

# Main
main() {
    check_prerequisites

    log_info "Finding running task in $SERVICE..."
    TASK_ARN=$(remote_pg_task_arn "$CLUSTER" "$SERVICE") || exit 1
    log_info "Task: ${TASK_ARN##*/}"

    if [[ $# -gt 0 ]]; then
        # Run a specific SQL command.
        #
        # The SQL is passed to the remote script as an argv element rather than
        # interpolated into the JS source, so backticks, $ and quotes in the
        # query cannot break the template literal (or the shell layers under it).
        SQL_COMMAND="$1"
        log_info "Running SQL command..."

        remote_pg_exec "$CLUSTER" "$SERVICE" "$CONTAINER" "
    const r = await client.query(process.argv[2]);
    console.log(JSON.stringify(r.rows, null, 2));
" "$SQL_COMMAND"
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
