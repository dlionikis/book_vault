#!/bin/bash
#
# Create a new user in the database (local or production)
#
# Usage: ./scripts/create-user.sh <local|prod> <username> [password]
#
# Examples:
#   ./scripts/create-user.sh local myuser                    # Auto-generates password
#   ./scripts/create-user.sh local myuser MyPassword         # Uses provided password
#   ./scripts/create-user.sh prod myuser                     # Auto-generates password
#   ./scripts/create-user.sh prod myuser MyPassword          # Uses provided password
#
# Prerequisites:
#   - Node.js with bcryptjs available (npm install)
#   - For local: Docker running with PostgreSQL
#   - For prod: AWS CLI configured, Session Manager plugin installed
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
SERVICE="book-vault-spot"
CONTAINER="book-vault"
REGION="us-east-1"

# Change to project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

# Validate arguments
if [ $# -lt 2 ]; then
    echo -e "${RED}Error: Environment and username required${NC}"
    echo ""
    echo "Usage: $0 <local|prod> <username> [password]"
    echo ""
    echo "Examples:"
    echo "  $0 local myuser                    # Auto-generates password"
    echo "  $0 local myuser MyPassword         # Uses provided password"
    echo "  $0 prod myuser MyPassword          # Production (password required)"
    exit 1
fi

ENV="$1"
USERNAME="$2"
PASSWORD="$3"

# Validate environment
if [ "$ENV" != "local" ] && [ "$ENV" != "prod" ]; then
    echo -e "${RED}Error: Environment must be 'local' or 'prod'${NC}"
    exit 1
fi

# Handle password - auto-generate if not provided
if [ -z "$PASSWORD" ]; then
    PASSWORD=$(openssl rand -base64 16 | tr -d '/+=' | head -c 16)
    echo -e "${YELLOW}[INFO]${NC} Auto-generated password"
fi

# Validate password length
if [ ${#PASSWORD} -lt 8 ]; then
    echo -e "${RED}Error: Password must be at least 8 characters${NC}"
    exit 1
fi

ENV_UPPER=$(echo "$ENV" | tr '[:lower:]' '[:upper:]')

echo ""
echo -e "${CYAN}Creating user in ${ENV_UPPER} environment${NC}"
echo -e "${CYAN}Username: $USERNAME${NC}"
echo ""

# Generate bcrypt hash locally
echo -e "${YELLOW}[INFO]${NC} Generating password hash..."
HASH=$(node -e "console.log(require('bcryptjs').hashSync('$PASSWORD', 10))" 2>/dev/null)

if [ -z "$HASH" ]; then
    echo -e "${RED}Error: Failed to generate password hash. Is bcryptjs installed?${NC}"
    echo "Run: npm install"
    exit 1
fi

echo -e "${GREEN}[OK]${NC} Password hash generated"

# ============================================================
# LOCAL ENVIRONMENT
# ============================================================
if [ "$ENV" == "local" ]; then
    echo -e "${YELLOW}[INFO]${NC} Creating user in local database..."

    # Prisma 7 generates a TypeScript client (lib/generated/prisma), so this runs
    # under tsx rather than plain node, and needs the pg driver adapter.
    RESULT=$(npx tsx -e "
import 'dotenv/config';
import { PrismaPg } from '@prisma/adapter-pg';
import { PrismaClient } from './lib/generated/prisma/client';

(async () => {
    const prisma = new PrismaClient({
        adapter: new PrismaPg({ connectionString: process.env.DATABASE_URL }),
    });
    try {
        const user = await prisma.user.create({
            data: {
                username: '$USERNAME',
                passwordHash: '$HASH'
            }
        });
        console.log('SUCCESS:' + user.id);
    } catch (e) {
        if (e.code === 'P2002') {
            console.log('ERROR:User already exists');
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

    echo -e "${YELLOW}[INFO]${NC} Creating user in production database..."

    # Escape special characters in hash for shell
    ESCAPED_HASH=$(printf '%s' "$HASH" | sed 's/\$/\\$/g')

    # Build the Node.js command (minified for shell safety).
    #
    # This uses the `pg` driver directly rather than Prisma: as of Prisma 7 the
    # generated client is TypeScript (lib/generated/prisma), and the production
    # image has no TS loader — only Next's own compiled bundle can import it.
    # `pg` is a real dependency and is present in the standalone output.
    # Postgres error 23505 (unique_violation) is the equivalent of Prisma P2002.
    CREATE_CMD="const{Client}=require('pg');(async()=>{const c=new Client({connectionString:process.env.DATABASE_URL});await c.connect();try{const r=await c.query('INSERT INTO users (id, username, password_hash, created_at, updated_at) VALUES (gen_random_uuid(), \$1, \$2, NOW(), NOW()) RETURNING id',['$USERNAME','$ESCAPED_HASH']);console.log('SUCCESS:'+r.rows[0].id)}catch(e){if(e.code==='23505'){console.log('ERROR:User already exists')}else{console.log('ERROR:'+e.message)}}finally{await c.end()}})();"

    # Execute via ECS Exec
    RESULT=$(aws ecs execute-command \
        --cluster "$CLUSTER" \
        --task "$TASK_ID" \
        --container "$CONTAINER" \
        --command "node -e \"$CREATE_CMD\"" \
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
    echo -e "${GREEN}  User created successfully!${NC}"
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo ""
    echo "  Environment: ${ENV_UPPER}"
    echo "  Username:    $USERNAME"
    echo "  Password:    $PASSWORD"
    echo "  User ID:     $USER_ID"
    echo ""
    if [ "$ENV" == "local" ]; then
        echo -e "${YELLOW}[TIP]${NC} Test login: curl -X POST http://localhost:3000/api/auth/mobile/login -H 'Content-Type: application/json' -d '{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\"}'"
    else
        echo -e "${YELLOW}[TIP]${NC} Test login: curl -X POST https://bookvault.lionikis.com/api/auth/mobile/login -H 'Content-Type: application/json' -d '{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\"}'"
    fi
    echo ""
elif echo "$RESULT" | grep -q "ERROR:User already exists"; then
    echo -e "${RED}Error: User with username '$USERNAME' already exists${NC}"
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
