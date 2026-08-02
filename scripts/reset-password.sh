#!/bin/bash
#
# Reset a user's password in the database (local or production)
#
# Usage: ./scripts/reset-password.sh <local|prod> <username> [password]
#
# Examples:
#   ./scripts/reset-password.sh local myuser              # Auto-generates password
#   ./scripts/reset-password.sh local myuser NewPassword  # Uses provided password
#   ./scripts/reset-password.sh prod myuser               # Auto-generates password
#   ./scripts/reset-password.sh prod myuser NewPassword   # Uses provided password
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

# Shared TLS/exec plumbing for talking to RDS from inside a task.
# shellcheck source=scripts/lib/remote-pg.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/remote-pg.sh"

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
    echo "  $0 local myuser              # Auto-generates password"
    echo "  $0 local myuser NewPassword  # Uses provided password"
    echo "  $0 prod myuser               # Auto-generates password"
    echo "  $0 prod myuser NewPassword   # Uses provided password"
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
echo -e "${CYAN}Resetting password in ${ENV_UPPER} environment${NC}"
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
    echo -e "${YELLOW}[INFO]${NC} Updating password in local database..."

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
        const user = await prisma.user.update({
            where: { username: '$USERNAME' },
            data: { passwordHash: '$HASH' }
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

    echo -e "${YELLOW}[INFO]${NC} Updating password in production database..."

    # Uses the `pg` driver directly — see the note in create-user.sh: the Prisma 7
    # client is TypeScript and the production image has no TS loader. An empty
    # rowCount means "not found" (Prisma's P2025).
    #
    # Hash and username travel as argv; bcrypt hashes contain `$`, which the
    # old hand-rolled sed escaping could not reliably survive.
    RESULT=$(remote_pg_exec "$CLUSTER" "$SERVICE" "$CONTAINER" "
    const [, , hash, username] = process.argv;
    const r = await client.query(
      'UPDATE users SET password_hash = \$1, updated_at = NOW() WHERE username = \$2 RETURNING id',
      [hash, username]
    );
    if (r.rowCount === 0) {
      console.log('ERROR:User not found');
    } else {
      console.log('SUCCESS:' + r.rows[0].id);
    }
" "$HASH" "$USERNAME" 2>&1)
fi

# ============================================================
# CHECK RESULT
# ============================================================
if echo "$RESULT" | grep -q "SUCCESS:"; then
    USER_ID=$(echo "$RESULT" | grep -o 'SUCCESS:[a-f0-9-]*' | cut -d: -f2)
    echo ""
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo -e "${GREEN}  Password reset successfully!${NC}"
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo ""
    echo "  Environment: ${ENV_UPPER}"
    echo "  Username:    $USERNAME"
    echo "  Password:    $PASSWORD"
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
