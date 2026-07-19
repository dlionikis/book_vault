#!/bin/bash
set -eo pipefail

# Web validation script wrapper - runs npm run validate:full with logging.
# Runs the web gate + the DB-backed suites (integration/contract/E2E).
# It does NOT run iOS checks — that's the iOS gate (npm run ios:validate).
# `npm run deploy` runs this same web gate + DB suites + the iOS gate, from the
# shared step library below, so the two cannot diverge.
#
# Usage: ./scripts/validate.sh
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

# Shared step definitions (colors, CURRENT_STEP, run_* functions, trap installer)
# shellcheck source=scripts/lib/validation-steps.sh
source "$SCRIPT_DIR/lib/validation-steps.sh"
install_step_trap

# Run the web gate, then the DB-backed suites
run_web_gate
require_database
run_db_suites

# Clear step tracking on success
CURRENT_STEP=""

echo ""
echo -e "${GREEN}✅ Web validation complete${NC}"
echo "   Log: $LOG_FILE"
