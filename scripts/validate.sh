#!/bin/bash
set -eo pipefail

# Validation script — runs the project gates from the shared step library.
# Usage:
#   ./scripts/validate.sh            (or --all)  Web gate + DB suites + iOS gate — the true "everything"
#   ./scripts/validate.sh --web                  Web gate + DB suites (no iOS; no Xcode needed)
#   ./scripts/validate.sh --ios                  iOS gate only (Swift drift + SwiftLint + build + tests)
#
# npm mapping: validate:full → (default/all), validate:web → --web, validate:ios → --ios.
# `npm run deploy` runs the same web+DB+iOS gate (from the same library) then pushes,
# so validation and deployment cannot diverge.
#
# Logs are written to: logs/validate.log

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# === ARGUMENT PARSING ===

RUN_WEB=true
RUN_IOS=true

while [[ $# -gt 0 ]]; do
  case $1 in
    --all)  RUN_WEB=true;  RUN_IOS=true;  shift ;;
    --web)  RUN_WEB=true;  RUN_IOS=false; shift ;;
    --ios)  RUN_WEB=false; RUN_IOS=true;  shift ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--all|--web|--ios]"
      exit 1 ;;
  esac
done

# Setup logging
LOG_DIR="$PROJECT_ROOT/logs"
LOG_FILE="$LOG_DIR/validate.log"
mkdir -p "$LOG_DIR"

# Log with timestamp to file and display to console
exec > >(tee -a "$LOG_FILE") 2>&1
echo ""
echo "========================================"
echo "Validation started: $(date)"
echo "  web=$RUN_WEB  ios=$RUN_IOS"
echo "========================================"

cd "$PROJECT_ROOT"

# Shared step definitions (colors, CURRENT_STEP, run_* functions, trap installer)
# shellcheck source=scripts/lib/validation-steps.sh
source "$SCRIPT_DIR/lib/validation-steps.sh"
install_step_trap

# Web gate + DB-backed suites
if [ "$RUN_WEB" = true ]; then
  run_web_gate
  require_database
  run_db_suites
fi

# iOS gate
if [ "$RUN_IOS" = true ]; then
  run_ios_gate
fi

# Clear step tracking on success
CURRENT_STEP=""

echo ""
echo -e "${GREEN}✅ Validation complete${NC} (web=$RUN_WEB ios=$RUN_IOS)"
echo "   Log: $LOG_FILE"
