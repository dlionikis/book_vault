#!/bin/bash
set -e

# Deployment script for Book Vault
# Usage:
#   npm run deploy          - Full validation (web + iOS) + deploy
#   npm run deploy:dry-run  - Full validation only (no deploy)
#   npm run deploy:web      - Web validation + deploy
#   npm run deploy:only     - Deploy only (no validation)

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

# Track current step for error reporting
CURRENT_STEP=""

# Trap to show failed step on error
trap 'if [ -n "$CURRENT_STEP" ]; then echo ""; log_error "Failed: $CURRENT_STEP"; fi' ERR

# === FUNCTIONS ===

check_git_status() {
  local current_branch=$(git branch --show-current)
  local has_changes=false
  local changed_files=""

  # Check for uncommitted changes
  if ! git diff --quiet HEAD 2>/dev/null; then
    has_changes=true
    changed_files=$(git diff --name-only HEAD)
  fi

  # Check for untracked files (excluding common ones)
  local untracked=$(git ls-files --others --exclude-standard)
  if [ -n "$untracked" ]; then
    has_changes=true
    if [ -n "$changed_files" ]; then
      changed_files="$changed_files"$'\n'"$untracked"
    else
      changed_files="$untracked"
    fi
  fi

  # If not on main or has changes, warn and ask for confirmation
  if [ "$current_branch" != "main" ] || [ "$has_changes" = true ]; then
    echo ""
    log_warn "Deployment safety check"
    echo ""
    echo -e "  Branch: ${YELLOW}$current_branch${NC}"

    if [ "$has_changes" = true ]; then
      echo -e "  Status: ${YELLOW}uncommitted changes${NC}"
      echo ""
      echo "  Changed files:"
      echo "$changed_files" | sed 's/^/    /'
    fi

    echo ""
    echo -e "  ${YELLOW}Docker will build from your local filesystem, not from git.${NC}"
    echo ""
    read -p "  Continue with deployment? [y/N] " -n 1 -r
    echo ""

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      echo "Deployment cancelled."
      exit 1
    fi
    echo ""
  fi
}

run_web_validation() {
  CURRENT_STEP="Web validation (npm run validate:full)"
  log_step "Running web validation (npm run validate:full)..."
  npm run validate:full
}

run_ios_validation() {
  CURRENT_STEP="iOS validation (drift check + lint + build + tests)"
  log_step "Running iOS validation (drift check + lint + build + tests)..."
  "$SCRIPT_DIR/ios-validate.sh"
}

run_deploy() {
  CURRENT_STEP="Docker build (AMD64)"
  log_step "Building Docker image for AMD64..."
  docker buildx create --use --name amd64builder 2>/dev/null || true
  docker buildx build --platform linux/amd64 -t book-vault:amd64 --load .

  CURRENT_STEP="ECR authentication"
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

  CURRENT_STEP="ECR push"
  log_step "Tagging and pushing to ECR..."
  docker tag book-vault:amd64 "${ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/book-vault:latest"
  DOCKER_CONFIG=/tmp/docker-config docker push "${ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/book-vault:latest"

  CURRENT_STEP="ECS deployment"
  log_step "Deploying to ECS..."
  aws ecs update-service \
    --cluster book-vault \
    --service book-vault-service \
    --force-new-deployment \
    --profile book_vault \
    --region us-east-1 \
    --query 'service.{status:status,runningCount:runningCount,desiredCount:desiredCount}' \
    --output json

  CURRENT_STEP="ECS service stabilization"
  log_step "Monitoring deployment..."
  echo "Waiting for service to stabilize..."
  aws ecs wait services-stable \
    --cluster book-vault \
    --services book-vault-service \
    --profile book_vault \
    --region us-east-1

  CURRENT_STEP="Health check"
  log_step "Verifying health endpoint..."
  curl -sf https://bookvault.lionikis.com/api/health || {
    log_error "Health check failed!"
    return 1
  }

  # Clear step tracking on success
  CURRENT_STEP=""

  echo ""
  echo -e "${GREEN}✅ Deployment complete!${NC}"
  echo "   URL: https://bookvault.lionikis.com"
}

# === ARGUMENT PARSING ===

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

# === MAIN ===

cd "$PROJECT_ROOT"

# Validation phase
[ "$SKIP_WEB_CHECKS" = false ] && run_web_validation
[ "$SKIP_IOS_CHECKS" = false ] && run_ios_validation

# Deployment phase
if [ "$DRY_RUN" = true ]; then
  log_warn "Dry run - skipping actual deployment"
  exit 0
fi

check_git_status
run_deploy
