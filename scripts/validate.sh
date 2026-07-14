#!/bin/bash
set -eo pipefail

# Web validation script wrapper - runs npm run validate:full with logging
# Usage: ./scripts/validate.sh
#
# Logs are written to: logs/validate.log

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Setup logging
LOG_DIR="$PROJECT_ROOT/logs"
LOG_FILE="$LOG_DIR/validate.log"
mkdir -p "$LOG_DIR"

# Log with timestamp to file and display to console
exec > >(tee -a "$LOG_FILE") 2>&1
echo ""
echo "========================================"
echo "Web validation started: $(date)"
echo "========================================"

cd "$PROJECT_ROOT"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Track current step for error reporting
CURRENT_STEP=""

# Trap to show failed step on error (also write directly to log file)
trap 'if [ -n "$CURRENT_STEP" ]; then
  echo ""
  echo -e "${RED}❌ Failed: $CURRENT_STEP${NC}"
  echo "See full log: $LOG_FILE"
  echo "" >> "$LOG_FILE"
  echo "❌ Failed: $CURRENT_STEP" >> "$LOG_FILE"
  echo "Timestamp: $(date)" >> "$LOG_FILE"
fi' ERR

run_format_check() {
  CURRENT_STEP="Format check (prettier)"
  echo "🔍 Checking formatting..."
  npm run format:check
}

run_lint() {
  CURRENT_STEP="Lint (eslint)"
  echo "🔍 Running ESLint..."
  npm run lint
}

run_type_check() {
  CURRENT_STEP="Type check (tsc)"
  echo "🔍 Running TypeScript check..."
  npm run type-check
}

run_api_validate() {
  CURRENT_STEP="API spec validation (redocly)"
  echo "🔍 Validating OpenAPI spec..."
  npm run api:validate
}

run_api_drift_check() {
  CURRENT_STEP="TypeScript type drift check"
  echo "🔄 Checking TypeScript type drift..."
  npm run api:check-drift
}

run_api_coverage() {
  CURRENT_STEP="API endpoint coverage"
  echo "🔍 Checking API endpoint coverage..."
  npm run api:check-coverage
}

run_tests() {
  CURRENT_STEP="Jest tests (unit)"
  echo "🧪 Running unit tests..."
  npm test
}

require_database() {
  CURRENT_STEP="Database availability check"
  if ! (echo > /dev/tcp/localhost/5433) 2>/dev/null; then
    echo -e "${RED}❌ PostgreSQL is not reachable on port 5433.${NC}"
    echo "   Integration and contract tests need the database:"
    echo "   docker-compose up -d"
    exit 1
  fi
}

run_integration_tests() {
  CURRENT_STEP="Jest tests (integration, real DB)"
  echo "🧪 Running integration tests..."
  npm run test:integration
}

run_contract_tests() {
  CURRENT_STEP="OpenAPI contract tests (live server)"
  echo "🔍 Running live contract tests against the spec..."
  npm run test:contract
}

run_e2e_smoke() {
  CURRENT_STEP="Playwright web smoke (E2E, live server)"
  echo "🎭 Running Playwright web smoke..."
  # Playwright owns the dev server (webServer in playwright.config.ts) and
  # globalSetup re-checks the DB + seeds fixtures. The DB was already gated by
  # require_database above.
  npm run test:e2e
}

# Run all validations
run_format_check
run_lint
run_type_check
run_api_validate
run_api_drift_check
run_api_coverage
run_tests
require_database
run_integration_tests
run_contract_tests
run_e2e_smoke

# Clear step tracking on success
CURRENT_STEP=""

echo ""
echo -e "${GREEN}✅ Web validation complete${NC}"
echo "   Log: $LOG_FILE"
