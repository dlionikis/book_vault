#!/bin/bash
set -eo pipefail

# Deployment script for Book Vault
# Usage:
#   npm run deploy          - Full validation (web + iOS) + deploy
#   npm run deploy:dry-run  - Full validation only (no deploy)
#   npm run deploy:web      - Web validation + deploy
#   npm run deploy:only     - Deploy only (no validation)
#
# Logs are written to: logs/deploy.log

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Setup logging
LOG_DIR="$PROJECT_ROOT/logs"
LOG_FILE="$LOG_DIR/deploy.log"
mkdir -p "$LOG_DIR"

# Log with timestamp to file and display to console
exec > >(tee -a "$LOG_FILE") 2>&1
echo ""
echo "========================================"
echo "Deploy started: $(date)"
echo "========================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_step() { echo -e "${GREEN}==>${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# Shared validation steps (same source of truth as scripts/validate.sh, so the
# deploy gate and validate:full can never diverge in what they run).
# Provides: run_web_gate, require_database, run_db_suites, run_ios_gate,
# CURRENT_STEP, install_step_trap.
# shellcheck source=scripts/lib/validation-steps.sh
source "$SCRIPT_DIR/lib/validation-steps.sh"
install_step_trap

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
  log_step "Running web validation (same web gate + DB suites as validate:full)..."
  run_web_gate
  require_database
  run_db_suites
}

run_ios_validation() {
  log_step "Running iOS validation (same iOS gate as ios:validate)..."
  run_ios_gate
}

run_deploy() {
  # ECS task definition revision the services run on. This revision declares
  # runtimePlatform=ARM64/LINUX, so the image we build+push MUST be arm64.
  #
  # We build natively on the (arm64) build host rather than cross-compiling to
  # amd64: Next 16's SWC compiler segfaults under qemu-emulated amd64 on Apple
  # Silicon (`next build` -> "qemu: uncaught target signal 11"), which is what
  # broke the deploy. Native arm64 build + Graviton Fargate avoids emulation
  # entirely (Fargate Spot supports ARM64 since Oct 2024) and is ~20% cheaper.
  TASK_DEF="book-vault:5"

  CURRENT_STEP="Docker build (native arm64)"
  log_step "Building Docker image (native arm64)..."
  docker build -t book-vault:arm64 .

  # Guard: the image arch must match the task def's runtimePlatform (ARM64).
  IMAGE_ARCH=$(docker image inspect book-vault:arm64 --format '{{.Architecture}}')
  if [ "$IMAGE_ARCH" != "arm64" ]; then
    log_error "Built image arch is '$IMAGE_ARCH', expected 'arm64' (task def $TASK_DEF is ARM64). Aborting."
    return 1
  fi
  log_step "  Image architecture: $IMAGE_ARCH ✓"

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
  docker tag book-vault:arm64 "${ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/book-vault:latest"
  DOCKER_CONFIG=/tmp/docker-config docker push "${ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/book-vault:latest"

  CURRENT_STEP="ECS deployment"
  log_step "Deploying to ECS (spot + fallback) on $TASK_DEF..."
  # Pin the ARM64 task definition explicitly. --force-new-deployment alone keeps
  # whatever revision the service is on; passing --task-definition is what moves
  # a service from the old x86_64 revision onto the arm64 one.
  for SERVICE in book-vault-spot book-vault-fallback; do
    log_step "  Updating $SERVICE..."
    aws ecs update-service \
      --cluster book-vault \
      --service "$SERVICE" \
      --task-definition "$TASK_DEF" \
      --force-new-deployment \
      --profile book_vault \
      --region us-east-1 \
      --query 'service.{status:status,runningCount:runningCount,desiredCount:desiredCount,taskDef:taskDefinition}' \
      --output json
  done

  CURRENT_STEP="ECS service stabilization"
  log_step "Monitoring deployment..."
  echo "Waiting for spot service to stabilize..."
  aws ecs wait services-stable \
    --cluster book-vault \
    --services book-vault-spot \
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
  echo "   Log: $LOG_FILE"
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

[ "$SKIP_WEB_CHECKS" = false ] && log_step "All web validations passed."
[ "$SKIP_IOS_CHECKS" = false ] && log_step "All iOS validations passed."

# Deployment phase
if [ "$DRY_RUN" = true ]; then
  log_warn "Dry run - skipping actual deployment"
  exit 0
fi

check_git_status
run_deploy

[ "$SKIP_WEB_CHECKS" = false ] && log_step "All web validations passed."
[ "$SKIP_IOS_CHECKS" = false ] && log_step "All iOS validations passed."
log_step "Deployment finished successfully."
