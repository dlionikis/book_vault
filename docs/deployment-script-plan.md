# Deployment Script & Swift Drift Check Implementation Plan

> **Status**: Completed
> **Created**: January 1, 2026
> **Completed**: January 1, 2026

## Summary

Create a unified deployment script with validation options and add Swift type drift checking to match the existing TypeScript drift check pattern.

## Prerequisites

Before implementing, ensure:

- Docker Desktop is running (for deployment testing)
- AWS CLI configured with `book_vault` profile
- iOS Simulator available (`iPhone 15` with iOS 17.5)
- `xcpretty` installed (`gem install xcpretty`)
- `swiftlint` installed (`brew install swiftlint`) - already present
- `openapi-generator` installed (`brew install openapi-generator`) - already present

## Goals

1. `npm run deploy` - Run all checks (web + iOS) then deploy
2. `npm run deploy:web` - Run web checks only then deploy
3. `npm run deploy:only` - Deploy without checks
4. `npm run api:check-drift:swift` - Check Swift types are in sync with OpenAPI spec
5. Update CI to enforce Swift drift checking
6. Consolidate `docs/testing.md` as the single source of truth for all testing documentation

## Design Principles

- **No code duplication**: Scripts call npm commands that CI also uses
- **CI parity**: Local scripts run the same commands as CI workflows
- **Fail fast**: Stop on first error

---

## Files to Create/Modify

| File                             | Action  | Purpose                                        |
| -------------------------------- | ------- | ---------------------------------------------- |
| `scripts/deploy.sh`              | Create  | Main deployment script                         |
| `scripts/ios-validate.sh`        | Create  | iOS validation (lint, build, test)             |
| `package.json`                   | Modify  | Add npm scripts                                |
| `.husky/pre-commit`              | Modify  | Add Swift regeneration                         |
| `.github/workflows/api.yml`      | Modify  | Add Swift drift check job                      |
| `docs/testing.md`                | Rewrite | Consolidate all testing docs (source of truth) |
| `CLAUDE.md`                      | Modify  | Reference docs/testing.md for testing details  |
| `docs/INDEX.md`                  | Modify  | Update testing.md description                  |
| `docs/data-validation-layers.md` | Modify  | Reference testing.md for contract tests        |
| `docs/mobile-ios-plan.md`        | Modify  | Reference testing.md for iOS testing           |

---

## Implementation Steps

### Step 1: Add Swift Drift Check Script

**Add to `package.json`:**

```json
"api:check-drift:swift": "npm run api:generate:swift && git diff --exit-code ios/BookVault/Generated/Models/"
```

This mirrors the TypeScript pattern:

```json
"api:check-drift": "npm run api:generate:ts && git diff --exit-code lib/api-types.ts"
```

### Step 2: Create `scripts/ios-validate.sh`

```bash
#!/bin/bash
set -e

# iOS validation script - mirrors CI workflow (ios-tests.yml)
# Usage: ./scripts/ios-validate.sh [--lint-only|--build-only|--test-only]

cd "$(dirname "$0")/../ios"

run_lint() {
  echo "🔍 Running SwiftLint..."
  swiftlint lint --config .swiftlint.yml --strict
}

run_build() {
  echo "🔨 Building iOS app..."
  xcodebuild build \
    -scheme BookVault \
    -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' \
    CODE_SIGNING_ALLOWED=NO \
    | xcpretty
}

run_tests() {
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
  all|"")       run_lint && run_build && run_tests ;;
  *)            echo "Usage: $0 [--lint-only|--build-only|--test-only]"; exit 1 ;;
esac

echo "✅ iOS validation complete"
```

### Step 3: Create `scripts/deploy.sh`

```bash
#!/bin/bash
set -e

# Deployment script for Book Vault
# Usage:
#   npm run deploy        - Full validation (web + iOS) + deploy
#   npm run deploy:web    - Web validation + deploy
#   npm run deploy:only   - Deploy only (no validation)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_step() { echo -e "${GREEN}==>${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# Parse arguments
SKIP_WEB_CHECKS=false
SKIP_IOS_CHECKS=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --deploy-only)
      SKIP_WEB_CHECKS=true
      SKIP_IOS_CHECKS=true
      shift ;;
    --web)
      SKIP_IOS_CHECKS=true
      shift ;;
    --dry-run)
      DRY_RUN=true
      shift ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--deploy-only|--web|--dry-run]"
      exit 1 ;;
  esac
done

cd "$PROJECT_ROOT"

# === VALIDATION PHASE ===

if [ "$SKIP_WEB_CHECKS" = false ]; then
  log_step "Running web validation (npm run validate:full)..."
  npm run validate:full
fi

if [ "$SKIP_IOS_CHECKS" = false ]; then
  log_step "Running iOS validation..."

  log_step "Checking Swift type drift..."
  npm run api:check-drift:swift

  log_step "Running iOS lint, build, and tests..."
  "$SCRIPT_DIR/ios-validate.sh"
fi

# === DEPLOYMENT PHASE ===

if [ "$DRY_RUN" = true ]; then
  log_warn "Dry run - skipping actual deployment"
  exit 0
fi

log_step "Building Docker image for AMD64..."
docker buildx create --use --name amd64builder 2>/dev/null || true
docker buildx build --platform linux/amd64 -t book-vault:amd64 --load .

log_step "Authenticating to ECR..."
mkdir -p /tmp/docker-config
cat > /tmp/docker-config/config.json << 'EOF'
{
  "auths": {},
  "credsStore": "osxkeychain"
}
EOF

ACCOUNT_ID=$(AWS_PROFILE=book_vault aws sts get-caller-identity --query 'Account' --output text)
AWS_PROFILE=book_vault aws ecr get-login-password --region us-east-1 | \
  DOCKER_CONFIG=/tmp/docker-config docker login --username AWS \
  --password-stdin "${ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com"

log_step "Tagging and pushing to ECR..."
docker tag book-vault:amd64 "${ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/book-vault:latest"
DOCKER_CONFIG=/tmp/docker-config docker push "${ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/book-vault:latest"

log_step "Deploying to ECS..."
aws ecs update-service \
  --cluster book-vault \
  --service book-vault-service \
  --force-new-deployment \
  --profile book_vault \
  --region us-east-1 \
  --query 'service.{status:status,runningCount:runningCount,desiredCount:desiredCount}' \
  --output json

log_step "Monitoring deployment..."
echo "Waiting for service to stabilize..."
aws ecs wait services-stable \
  --cluster book-vault \
  --services book-vault-service \
  --profile book_vault \
  --region us-east-1

log_step "Verifying health endpoint..."
curl -sf https://bookvault.lionikis.com/api/health || {
  log_error "Health check failed!"
  exit 1
}

echo ""
echo -e "${GREEN}✅ Deployment complete!${NC}"
echo "   URL: https://bookvault.lionikis.com"
```

### Step 4: Update `package.json` Scripts

Add these scripts:

```json
{
  "scripts": {
    "api:check-drift:swift": "npm run api:generate:swift && git diff --exit-code ios/BookVault/Generated/Models/",
    "ios:lint": "./scripts/ios-validate.sh --lint-only",
    "ios:build": "./scripts/ios-validate.sh --build-only",
    "ios:test": "./scripts/ios-validate.sh --test-only",
    "ios:validate": "./scripts/ios-validate.sh",
    "deploy": "./scripts/deploy.sh",
    "deploy:web": "./scripts/deploy.sh --web",
    "deploy:only": "./scripts/deploy.sh --deploy-only"
  }
}
```

### Step 5: Update Pre-commit Hook

**Modify `.husky/pre-commit`:**

```bash
npx lint-staged

# OpenAPI: Check if spec changed and regenerate types
if git diff --cached --name-only | grep -q "docs/api/openapi.yaml"; then
  echo "📝 OpenAPI spec changed, regenerating TypeScript types..."
  npm run api:generate:ts
  git add lib/api-types.ts

  echo "📝 Regenerating Swift models..."
  npm run api:generate:swift
  git add ios/BookVault/Generated/Models/

  echo "✅ Validating OpenAPI spec..."
  npm run api:validate || {
    echo "❌ OpenAPI spec validation failed"
    exit 1
  }
fi
```

### Step 6: Update CI Workflow

**Add to `.github/workflows/api.yml`:**

```yaml
check-generated-swift:
  name: Check Generated Swift Models are Up-to-Date
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4

    - uses: actions/setup-node@v4
      with:
        node-version: '20'

    - name: Install dependencies
      run: npm ci

    - name: Install OpenAPI Generator
      run: npm install -g @openapitools/openapi-generator-cli

    - name: Generate Swift models
      run: npm run api:generate:swift

    - name: Check for uncommitted changes
      run: |
        if ! git diff --exit-code ios/BookVault/Generated/Models/; then
          echo "❌ ERROR: Generated Swift models are out of sync with OpenAPI spec"
          echo "Please run: npm run api:generate:swift"
          echo "Then commit the updated ios/BookVault/Generated/Models/ files"
          exit 1
        fi
        echo "✅ Generated Swift models are up-to-date"
```

### Step 7: Consolidate Testing Documentation

**Rewrite `docs/testing.md`** as the single source of truth for all testing. New structure:

```markdown
# Testing Guide

> **TL;DR**: All testing commands and CI workflows in one place.

## Quick Reference

| Command                 | Purpose                               |
| ----------------------- | ------------------------------------- |
| `npm test`              | Run Jest tests                        |
| `npm run test:contract` | Run OpenAPI contract tests            |
| `npm run validate`      | Format + lint + types + tests         |
| `npm run validate:full` | Above + API validation + drift checks |
| `npm run ios:validate`  | iOS lint + build + tests              |
| `npm run ios:lint`      | SwiftLint only                        |
| `npm run deploy`        | Full validation + deploy              |

## Web Testing (Jest + RTL)

- Test structure, patterns, mocking examples
- Coverage goals
- Troubleshooting

## API Contract Testing

- OpenAPI validation
- Type drift checks (TypeScript + Swift)
- Contract test execution

## iOS Testing (XCTest)

- SwiftLint configuration
- xcodebuild commands
- Coverage thresholds

## CI/CD Workflows

- main.yml - Web validation
- api.yml - API contract checks
- ios-tests.yml - iOS validation
- storybook.yml - Storybook build

## Deployment Validation

- npm run deploy options
- Pre-deployment checks
```

**Update other docs to reference `docs/testing.md`:**

1. **`CLAUDE.md`** (Section 2 - Testing & Quality):
   - Keep command list but add: `See [docs/testing.md](docs/testing.md) for detailed testing guide`

2. **`docs/INDEX.md`**:
   - Update description: `[testing.md](testing.md) - Complete testing guide (web, iOS, CI, deployment)`

3. **`docs/data-validation-layers.md`**:
   - In contract testing section, add: `See [testing.md](testing.md#api-contract-testing) for commands`

4. **`docs/mobile-ios-plan.md`**:
   - In testing section, add: `See [testing.md](testing.md#ios-testing) for detailed iOS testing guide`

---

## Command Matrix

| Command               | Web Checks         | iOS Checks                 | Deploy |
| --------------------- | ------------------ | -------------------------- | ------ |
| `npm run deploy`      | ✅ `validate:full` | ✅ drift + lint/build/test | ✅     |
| `npm run deploy:web`  | ✅ `validate:full` | ❌                         | ✅     |
| `npm run deploy:only` | ❌                 | ❌                         | ✅     |

## Validation Overlap (Script ↔ CI)

| Check        | Local Script                    | CI Workflow     |
| ------------ | ------------------------------- | --------------- |
| Format       | `npm run format:check`          | `main.yml`      |
| Lint         | `npm run lint`                  | `main.yml`      |
| Type check   | `npm run type-check`            | `main.yml`      |
| Tests        | `npm test`                      | `main.yml`      |
| API validate | `npm run api:validate`          | `api.yml`       |
| TS drift     | `npm run api:check-drift`       | `api.yml`       |
| Swift drift  | `npm run api:check-drift:swift` | `api.yml` (new) |
| iOS lint     | `swiftlint`                     | `ios-tests.yml` |
| iOS build    | `xcodebuild build`              | `ios-tests.yml` |
| iOS tests    | `xcodebuild test`               | `ios-tests.yml` |

---

## Testing the Implementation

After implementation:

```bash
# Test Swift drift check
npm run api:check-drift:swift

# Test iOS validation
npm run ios:validate

# Test deploy dry-run (no actual deployment)
./scripts/deploy.sh --dry-run

# Test web-only deploy dry-run
./scripts/deploy.sh --web --dry-run

# Test deploy-only dry-run
./scripts/deploy.sh --deploy-only --dry-run
```

---

## Notes

1. **OpenAPI Generator in CI**: Need to install `@openapitools/openapi-generator-cli` or use Java-based generator. The script uses homebrew-installed version locally.

2. **Simulator**: Using `iPhone 15,OS=17.5` to match CI exactly.

3. **xcpretty**: Required for cleaner output. Already installed in CI, may need local install (`gem install xcpretty`).

---

## Context & References

**Related files to understand before implementing:**

- `package.json` - Existing npm scripts (add new ones here)
- `.husky/pre-commit` - Current pre-commit hook (extend for Swift)
- `.github/workflows/api.yml` - TypeScript drift check (pattern to follow)
- `.github/workflows/ios-tests.yml` - iOS CI workflow (commands to match)
- `docs/aws-deployment-plan.md` - Deployment commands reference (Quick Deploy Guide section)
- `scripts/generate-swift.sh` - Existing Swift generation script

**Key patterns to follow:**

- TypeScript drift check: `npm run api:generate:ts && git diff --exit-code lib/api-types.ts`
- iOS CI commands: `xcodebuild test -scheme BookVault -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5'`
- AWS profile requirement: Always use `--profile book_vault` with AWS CLI commands
