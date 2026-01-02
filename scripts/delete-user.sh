#!/bin/bash
#
# Delete a user from the database (local or production)
#
# Usage: ./scripts/delete-user.sh <local|prod> <email>
#
# Examples:
#   ./scripts/delete-user.sh local user@example.com
#   ./scripts/delete-user.sh prod user@example.com
#
# Prerequisites:
#   - Node.js with Prisma available (npm install)
#   - For local: Docker running with PostgreSQL
#   - For prod: AWS CLI configured, Session Manager plugin installed
#
# Note: This will also delete all associated data (progress, library entries, etc.)
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
CLUSTER="book-vault"
SERVICE="book-vault-service"
CONTAINER="book-vault"
REGION="us-east-1"

# Change to project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

# Validate arguments
if [ $# -ne 2 ]; then
    echo -e "${RED}Error: Environment and email required${NC}"
    echo ""
    echo "Usage: $0 <local|prod> <email>"
    echo ""
    echo "Examples:"
    echo "  $0 local user@example.com"
    echo "  $0 prod user@example.com"
    exit 1
fi

ENV="$1"
EMAIL="$2"

# Validate environment
if [ "$ENV" != "local" ] && [ "$ENV" != "prod" ]; then
    echo -e "${RED}Error: Environment must be 'local' or 'prod'${NC}"
    exit 1
fi

# Validate email format (basic check)
if [[ ! "$EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    echo -e "${RED}Error: Invalid email format${NC}"
    exit 1
fi

ENV_UPPER=$(echo "$ENV" | tr '[:lower:]' '[:upper:]')

echo ""
echo -e "${CYAN}Deleting user in ${ENV_UPPER} environment${NC}"
echo -e "${CYAN}Email: $EMAIL${NC}"
echo ""

# Confirmation prompt
echo -e "${YELLOW}WARNING: This will permanently delete the user and all associated data.${NC}"
read -p "Are you sure you want to continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo -e "${YELLOW}Aborted.${NC}"
    exit 0
fi

# ============================================================
# LOCAL ENVIRONMENT
# ============================================================
if [ "$ENV" == "local" ]; then
    echo -e "${YELLOW}[INFO]${NC} Deleting user from local database..."

    # Use Prisma via Node.js with local DATABASE_URL
    RESULT=$(node -e "
const { PrismaClient } = require('@prisma/client');

(async () => {
    const prisma = new PrismaClient();
    try {
        const user = await prisma.user.delete({
            where: { email: '$EMAIL' }
        });
        console.log('SUCCESS:' + user.id);
    } catch (e) {
        if (e.code === 'P2025') {
            console.log('ERROR:User not found');
        } else {
            console.log('ERROR:' + e.message);
        }
    } finally {
        await prisma.\$disconnect();
    }
})();
" 2>&1)

# ============================================================
# PRODUCTION ENVIRONMENT
# ============================================================
else
    echo -e "${YELLOW}[INFO]${NC} Finding running ECS task..."

    TASK_ARN=$(aws ecs list-tasks \
        --cluster "$CLUSTER" \
        --service-name "$SERVICE" \
        --region "$REGION" \
        --query 'taskArns[0]' \
        --output text 2>/dev/null)

    if [ -z "$TASK_ARN" ] || [ "$TASK_ARN" == "None" ]; then
        echo -e "${RED}Error: No running tasks found in $SERVICE${NC}"
        exit 1
    fi

    TASK_ID=$(echo "$TASK_ARN" | awk -F'/' '{print $NF}')
    echo -e "${GREEN}[OK]${NC} Found task: $TASK_ID"

    echo -e "${YELLOW}[INFO]${NC} Deleting user from production database..."

    # Build the Node.js command (minified for shell safety)
    DELETE_CMD="const{PrismaClient}=require('@prisma/client');(async()=>{const p=new PrismaClient();try{const u=await p.user.delete({where:{email:'$EMAIL'}});console.log('SUCCESS:'+u.id)}catch(e){if(e.code==='P2025'){console.log('ERROR:User not found')}else{console.log('ERROR:'+e.message)}}finally{await p.\$disconnect()}})();"

    # Execute via ECS Exec
    RESULT=$(aws ecs execute-command \
        --cluster "$CLUSTER" \
        --task "$TASK_ID" \
        --container "$CONTAINER" \
        --command "node -e \"$DELETE_CMD\"" \
        --interactive \
        --region "$REGION" 2>&1)
fi

# ============================================================
# CHECK RESULT
# ============================================================
if echo "$RESULT" | grep -q "SUCCESS:"; then
    USER_ID=$(echo "$RESULT" | grep -o 'SUCCESS:[a-f0-9-]*' | cut -d: -f2)
    echo ""
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo -e "${GREEN}  User deleted successfully!${NC}"
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo ""
    echo "  Environment: ${ENV_UPPER}"
    echo "  Email:       $EMAIL"
    echo "  User ID:     $USER_ID"
    echo ""
elif echo "$RESULT" | grep -q "ERROR:User not found"; then
    echo -e "${RED}Error: User with email '$EMAIL' not found${NC}"
    exit 1
elif echo "$RESULT" | grep -q "ERROR:"; then
    ERROR_MSG=$(echo "$RESULT" | grep -o 'ERROR:.*' | cut -d: -f2-)
    echo -e "${RED}Error: $ERROR_MSG${NC}"
    exit 1
else
    echo -e "${RED}Error: Unexpected response${NC}"
    echo "$RESULT"
    exit 1
fi
