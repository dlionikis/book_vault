#!/usr/bin/env bash
#
# Import audiobooks into the production database, then sync media to S3.
#
# Usage:
#   ./scripts/import-prod.sh
#
# Steps:
#   1. Open RDS firewall for current IP (auto-closes on exit)
#   2. Fetch DATABASE_URL from AWS Secrets Manager
#   3. Run `npm run import` against production DB
#   4. Sync MEDIA_DATA_PATH to s3://${S3_BUCKET}/
#
# Env overrides:
#   MEDIA_DATA_PATH  Local audiobook source (default: /Volumes/BeeDrive/Libation)
#   S3_BUCKET        Target S3 bucket            (default: book-vault-media)
#   DATABASE_URL     Skip Secrets Manager lookup if already set
#

set -euo pipefail

AWS_PROFILE="book_vault"
AWS_REGION="us-east-1"
DB_SECRET_ID="book-vault/database"
MEDIA_DATA_PATH="${MEDIA_DATA_PATH:-/Volumes/BeeDrive/Libation}"
S3_BUCKET="${S3_BUCKET:-book-vault-media}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIREWALL_SCRIPT="${SCRIPT_DIR}/db-firewall.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_step()  { echo -e "\n${BOLD}${CYAN}==> $1${NC}"; }
log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

firewall_opened=0

cleanup() {
    local exit_code=$?
    if [[ "$firewall_opened" -eq 1 ]]; then
        log_step "Closing RDS firewall"
        "$FIREWALL_SCRIPT" close || log_warn "Failed to close firewall — run 'npm run db:firewall:close' manually"
    fi
    if [[ "$exit_code" -ne 0 ]]; then
        log_error "Import failed (exit $exit_code)"
    fi
    exit "$exit_code"
}
trap cleanup EXIT INT TERM

# 1. Validate inputs
log_step "Validating environment"
if [[ ! -d "$MEDIA_DATA_PATH" ]]; then
    log_error "MEDIA_DATA_PATH does not exist: $MEDIA_DATA_PATH"
    exit 1
fi
log_info "Media source: ${CYAN}${MEDIA_DATA_PATH}${NC}"
log_info "S3 target:    ${CYAN}s3://${S3_BUCKET}/${NC}"

# 2. Open firewall
log_step "Opening RDS firewall"
"$FIREWALL_SCRIPT" open
firewall_opened=1

# 3. Resolve DATABASE_URL
if [[ -z "${DATABASE_URL:-}" ]]; then
    log_step "Fetching DATABASE_URL from Secrets Manager (${DB_SECRET_ID})"
    DATABASE_URL=$(aws secretsmanager get-secret-value \
        --secret-id "$DB_SECRET_ID" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --query 'SecretString' \
        --output text \
        | node -e "process.stdin.on('data',d=>console.log(JSON.parse(d).DATABASE_URL))")

    if [[ -z "$DATABASE_URL" ]]; then
        log_error "Could not resolve DATABASE_URL from secret ${DB_SECRET_ID}"
        exit 1
    fi
    export DATABASE_URL
    log_info "DATABASE_URL loaded from Secrets Manager"
else
    log_info "Using DATABASE_URL from environment"
fi

# 4. Run import
log_step "Running database import"
MEDIA_DATA_PATH="$MEDIA_DATA_PATH" DATABASE_URL="$DATABASE_URL" npm run import

# 5. Close firewall — S3 sync doesn't need RDS access
log_step "Closing RDS firewall (no longer needed for S3 sync)"
"$FIREWALL_SCRIPT" close
firewall_opened=0

# 6. Sync to S3 (stream output live)
log_step "Syncing media to s3://${S3_BUCKET}/"
log_info "This can take a while — output streams below..."
echo ""
aws s3 sync "${MEDIA_DATA_PATH}/" "s3://${S3_BUCKET}/" \
    --exclude "*.cue" \
    --exclude "Icon*" \
    --exclude "Icon?" \
    --exclude ".DS_Store" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION"

log_step "Done"
log_info "Import + S3 sync complete"
