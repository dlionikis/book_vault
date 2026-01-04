#!/bin/bash
set -eo pipefail

# iOS validation script - mirrors CI workflow (ios-tests.yml + api.yml Swift drift)
# Usage: ./scripts/ios-validate.sh [--lint-only|--build-only|--test-only|--skip-drift]
#
# Logs are written to: logs/ios-validate.log

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Setup logging
LOG_DIR="$PROJECT_ROOT/logs"
LOG_FILE="$LOG_DIR/ios-validate.log"
mkdir -p "$LOG_DIR"

# Log with timestamp to file and display to console
exec > >(tee -a "$LOG_FILE") 2>&1
echo ""
echo "========================================"
echo "iOS validation started: $(date)"
echo "========================================"

cd "$SCRIPT_DIR/../ios"

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

run_drift_check() {
  CURRENT_STEP="Swift type drift check"
  echo "🔄 Checking Swift type drift..."
  cd "$SCRIPT_DIR/.."
  npm run api:check-drift:swift
  cd "$SCRIPT_DIR/../ios"
}

run_lint() {
  CURRENT_STEP="SwiftLint"
  echo "🔍 Running SwiftLint..."
  swiftlint lint --config .swiftlint.yml --strict
}

run_build() {
  CURRENT_STEP="iOS build"
  echo "🔨 Building iOS app..."
  # Use a specific simulator to avoid building for x86_64 (which has stricter Swift 6 warnings)
  # This matches what CI does and avoids issues with generated OpenAPI code
  SIMULATOR_DEST=$(xcrun simctl list devices available -j | python3 -c "
import json, sys
data = json.load(sys.stdin)
for runtime, devices in data.get('devices', {}).items():
    if 'iOS' in runtime:
        for d in devices:
            if 'iPhone' in d['name'] and d['isAvailable']:
                print(f\"platform=iOS Simulator,id={d['udid']}\")
                sys.exit(0)
print('platform=iOS Simulator,name=Any iOS Simulator Device')
")
  echo "   Using simulator: $SIMULATOR_DEST"
  if command -v xcpretty &> /dev/null; then
    xcodebuild build \
      -scheme BookVault \
      -destination "$SIMULATOR_DEST" \
      CODE_SIGNING_ALLOWED=NO \
      | xcpretty
  else
    xcodebuild build \
      -scheme BookVault \
      -destination "$SIMULATOR_DEST" \
      CODE_SIGNING_ALLOWED=NO
  fi
}

run_tests() {
  CURRENT_STEP="iOS tests"
  echo "🧪 Running iOS tests..."
  # Tests need a specific simulator - find the first available iPhone simulator
  SIMULATOR_DEST=$(xcrun simctl list devices available -j | python3 -c "
import json, sys
data = json.load(sys.stdin)
for runtime, devices in data.get('devices', {}).items():
    if 'iOS' in runtime:
        for d in devices:
            if 'iPhone' in d['name'] and d['isAvailable']:
                print(f\"platform=iOS Simulator,id={d['udid']}\")
                sys.exit(0)
print('platform=iOS Simulator,name=Any iOS Simulator Device')
")
  if command -v xcpretty &> /dev/null; then
    xcodebuild test \
      -scheme BookVault \
      -destination "$SIMULATOR_DEST" \
      -enableCodeCoverage YES \
      CODE_SIGNING_ALLOWED=NO \
      | xcpretty
  else
    xcodebuild test \
      -scheme BookVault \
      -destination "$SIMULATOR_DEST" \
      -enableCodeCoverage YES \
      CODE_SIGNING_ALLOWED=NO
  fi
}

case "${1:-all}" in
  --lint-only)  run_lint ;;
  --build-only) run_build ;;
  --test-only)  run_tests ;;
  --skip-drift) run_lint && run_build && run_tests ;;
  all|"")       run_drift_check && run_lint && run_build && run_tests ;;
  *)            echo "Usage: $0 [--lint-only|--build-only|--test-only|--skip-drift]"; exit 1 ;;
esac

# Clear step tracking on success
CURRENT_STEP=""

echo -e "${GREEN}✅ iOS validation complete${NC}"
echo "   Log: $LOG_FILE"
