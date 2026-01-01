#!/bin/bash
set -e

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
  CURRENT_STEP="Jest tests"
  echo "🧪 Running tests..."
  npm test
}

# Run all validations
run_format_check
run_lint
run_type_check
run_api_validate
run_api_drift_check
run_api_coverage
run_tests

# Clear step tracking on success
CURRENT_STEP=""

echo ""
echo -e "${GREEN}✅ Web validation complete${NC}"
echo "   Log: $LOG_FILE"
