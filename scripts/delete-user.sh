#!/bin/bash
#
# Delete a user from the database (local or production)
#
# Usage: ./scripts/delete-user.sh <local|prod> <username>
#
# Examples:
#   ./scripts/delete-user.sh local myuser
#   ./scripts/delete-user.sh prod myuser
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
SERVICE="book-vault-spot"
CONTAINER="book-vault"
REGION="us-east-1"

# Shared TLS/exec plumbing for talking to RDS from inside a task.
# shellcheck source=scripts/lib/remote-pg.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/remote-pg.sh"

# Change to project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

# Validate arguments
if [ $# -ne 2 ]; then
    echo -e "${RED}Error: Environment and username required${NC}"
    echo ""
    echo "Usage: $0 <local|prod> <username>"
    echo ""
    echo "Examples:"
    echo "  $0 local myuser"
    echo "  $0 prod myuser"
    exit 1
fi

ENV="$1"
USERNAME="$2"

# Validate environment
if [ "$ENV" != "local" ] && [ "$ENV" != "prod" ]; then
    echo -e "${RED}Error: Environment must be 'local' or 'prod'${NC}"
    exit 1
fi

ENV_UPPER=$(echo "$ENV" | tr '[:lower:]' '[:upper:]')

echo ""
echo -e "${CYAN}Deleting user in ${ENV_UPPER} environment${NC}"
echo -e "${CYAN}Username: $USERNAME${NC}"
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
        const user = await prisma.user.delete({
            where: { username: '$USERNAME' }
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

    TASK_ARN=$(remote_pg_task_arn "$CLUSTER" "$SERVICE") || exit 1
    echo -e "${GREEN}[OK]${NC} Found task: ${TASK_ARN##*/}"

    echo -e "${YELLOW}[INFO]${NC} Deleting user from production database..."

    # Uses the `pg` driver directly — see the note in create-user.sh: the Prisma 7
    # client is TypeScript and the production image has no TS loader. Every
    # user-owned table cascades at the DB level (ON DELETE CASCADE), so this is
    # equivalent to prisma.user.delete. An empty rowCount means "not found"
    # (Prisma's P2025).
    RESULT=$(remote_pg_exec "$CLUSTER" "$SERVICE" "$CONTAINER" "
    const [, , username] = process.argv;
    const r = await client.query('DELETE FROM users WHERE username = \$1 RETURNING id', [username]);
    if (r.rowCount === 0) {
      console.log('ERROR:User not found');
    } else {
      console.log('SUCCESS:' + r.rows[0].id);
    }
" "$USERNAME" 2>&1)
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
    echo "  Username:    $USERNAME"
    echo "  User ID:     $USER_ID"
    echo ""
elif echo "$RESULT" | grep -q "ERROR:User not found"; then
    echo -e "${RED}Error: User with username '$USERNAME' not found${NC}"
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
