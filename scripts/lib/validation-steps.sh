#!/bin/bash
# Shared validation steps for validate.sh and deploy.sh.
#
# Single source of truth so the two gates cannot diverge (a SwiftLint break once
# passed CI-style validation but blocked deploy — see docs/development-process.md §8).
#
# This file is SOURCED, not executed. The sourcing script must, before sourcing:
#   - set `set -eo pipefail`
#   - define PROJECT_ROOT and LOG_FILE
#   - install its own ERR trap that reports $CURRENT_STEP (see install_step_trap below)
#
# Each step sets CURRENT_STEP (read by the trap on failure) and runs one check.
# Grouped into: WEB (no infra), DATABASE-GATED (need Postgres), and iOS (need Xcode).

# Colors (guard against double-definition when sourced after the caller sets them)
: "${RED:=$'\033[0;31m'}"
: "${GREEN:=$'\033[0;32m'}"
: "${YELLOW:=$'\033[1;33m'}"
: "${NC:=$'\033[0m'}"

CURRENT_STEP=""

# Installs the standard ERR trap that surfaces the failing step + log location.
# Callers invoke this once after defining LOG_FILE.
install_step_trap() {
  trap 'if [ -n "$CURRENT_STEP" ]; then
    echo ""
    echo -e "${RED}❌ Failed: $CURRENT_STEP${NC}"
    echo "See full log: $LOG_FILE"
    echo "" >> "$LOG_FILE"
    echo "❌ Failed: $CURRENT_STEP" >> "$LOG_FILE"
    echo "Timestamp: $(date)" >> "$LOG_FILE"
  fi' ERR
}

# ── Web steps (no infrastructure required) ──────────────────────────────────

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

# Runs the full web gate (everything above, in order).
run_web_gate() {
  run_format_check
  run_lint
  run_type_check
  run_api_validate
  run_api_drift_check
  run_api_coverage
  run_tests
}

# ── Database-gated steps (need Postgres on :5433) ───────────────────────────

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

# Runs the DB-backed suites (caller must have run require_database first).
run_db_suites() {
  run_integration_tests
  run_contract_tests
  run_e2e_smoke
}

# ── iOS steps (need Xcode + simulator) ──────────────────────────────────────

run_ios_drift_check() {
  CURRENT_STEP="Swift type drift check"
  echo "🔄 Checking Swift type drift..."
  npm run api:check-drift:swift
}

run_ios_lint() {
  CURRENT_STEP="SwiftLint"
  echo "🔍 Running SwiftLint (--strict)..."
  ( cd "$PROJECT_ROOT/ios" && swiftlint lint --config .swiftlint.yml --strict )
}

# Resolves the first available iPhone simulator destination.
_ios_simulator_dest() {
  xcrun simctl list devices available -j | python3 -c "
import json, sys
data = json.load(sys.stdin)
for runtime, devices in data.get('devices', {}).items():
    if 'iOS' in runtime:
        for d in devices:
            if 'iPhone' in d['name'] and d['isAvailable']:
                print(f\"platform=iOS Simulator,id={d['udid']}\")
                sys.exit(0)
print('platform=iOS Simulator,name=Any iOS Simulator Device')
"
}

run_ios_build() {
  CURRENT_STEP="iOS build"
  echo "🔨 Building iOS app..."
  ( cd "$PROJECT_ROOT/ios" && xcodebuild build \
    -scheme BookVault \
    -destination 'generic/platform=iOS Simulator' \
    CODE_SIGNING_ALLOWED=NO )
}

run_ios_tests() {
  CURRENT_STEP="iOS tests"
  echo "🧪 Running iOS tests..."
  local dest
  dest="$(_ios_simulator_dest)"
  echo "   Using simulator: $dest"
  ( cd "$PROJECT_ROOT/ios" && xcodebuild test \
    -scheme BookVault \
    -destination "$dest" \
    -enableCodeCoverage YES \
    CODE_SIGNING_ALLOWED=NO )
}

# Runs the full iOS gate (drift → lint → build → tests).
run_ios_gate() {
  run_ios_drift_check
  run_ios_lint
  run_ios_build
  run_ios_tests
}
