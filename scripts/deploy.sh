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
log_warn() { echo -e "${YELLOW}Warning: $1${NC}"; }
log_error() { echo -e "${RED}Error: $1${NC}"; }

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
echo -e "${GREEN}Deployment complete!${NC}"
echo "   URL: https://bookvault.lionikis.com"
