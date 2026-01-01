#!/bin/bash
set -e

# iOS validation script - mirrors CI workflow (ios-tests.yml)
# Usage: ./scripts/ios-validate.sh [--lint-only|--build-only|--test-only]

cd "$(dirname "$0")/../ios"

run_lint() {
  echo "Running SwiftLint..."
  swiftlint lint --config .swiftlint.yml --strict
}

run_build() {
  echo "Building iOS app..."
  xcodebuild build \
    -scheme BookVault \
    -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' \
    CODE_SIGNING_ALLOWED=NO \
    | xcpretty
}

run_tests() {
  echo "Running iOS tests..."
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
  all|"")       run_lint && run_build && run_tests ;;
  *)            echo "Usage: $0 [--lint-only|--build-only|--test-only]"; exit 1 ;;
esac

echo "iOS validation complete"
