#!/bin/bash
set -e

# iOS validation script - mirrors CI workflow (ios-tests.yml + api.yml Swift drift)
# Usage: ./scripts/ios-validate.sh [--lint-only|--build-only|--test-only|--skip-drift]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/../ios"

# Colors for output
RED='\033[0;31m'
NC='\033[0m' # No Color

# Track current step for error reporting
CURRENT_STEP=""

# Trap to show failed step on error
trap 'if [ -n "$CURRENT_STEP" ]; then echo ""; echo -e "${RED}❌ Failed: $CURRENT_STEP${NC}"; fi' ERR

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
  xcodebuild build \
    -scheme BookVault \
    -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' \
    CODE_SIGNING_ALLOWED=NO \
    | xcpretty
}

run_tests() {
  CURRENT_STEP="iOS tests"
  echo "🧪 Running iOS tests..."
  xcodebuild test \
    -scheme BookVault \
    -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' \
    -enableCodeCoverage YES \
    CODE_SIGNING_ALLOWED=NO \
    | xcpretty
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

echo "✅ iOS validation complete"
