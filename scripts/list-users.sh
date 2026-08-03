#!/bin/bash
#
# List all users in the database (local or production)
#
# Usage: ./scripts/list-users.sh <local|prod>
#
# Examples:
#   ./scripts/list-users.sh local
#   ./scripts/list-users.sh prod
#
# Prerequisites:
#   - Node.js with Prisma available (npm install)
#   - For local: Docker running with PostgreSQL
#   - For prod: AWS CLI configured, Session Manager plugin installed
#
# Read-only: this script never writes to the database.
#
# Note: there is no soft-delete or "disabled" concept for users — the users
# table has no deleted_at/is_active column, so every row listed here is a live,
# usable account. See scripts/delete-user.sh, which is a hard delete.
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
if [ $# -ne 1 ]; then
    echo -e "${RED}Error: Environment required${NC}"
    echo ""
    echo "Usage: $0 <local|prod>"
    echo ""
    echo "Examples:"
    echo "  $0 local"
    echo "  $0 prod"
    exit 1
fi

ENV="$1"

# Validate environment
if [ "$ENV" != "local" ] && [ "$ENV" != "prod" ]; then
    echo -e "${RED}Error: Environment must be 'local' or 'prod'${NC}"
    exit 1
fi

ENV_UPPER=$(echo "$ENV" | tr '[:lower:]' '[:upper:]')

echo ""
echo -e "${CYAN}Listing users in ${ENV_UPPER} environment${NC}"
echo ""

# The row format is shared by both branches so the rendering below is identical:
#   ROW:<username>\t<admin>\t<created>\t<last_login>\t<last_active>\t<progress>\t<lists>\t<devices>
# A leading COUNT: line carries the total.
#
# LAST LOGIN and LAST ACTIVE are derived, not stored — the users table has no
# last_login/last_active column:
#
#   LAST LOGIN  = newest refresh_tokens.created_at. One row is minted per mobile
#                 login, so this tracks iOS sign-ins only. Web sessions are
#                 stateless NextAuth JWTs and create no row, so a web-only user
#                 shows "never".
#   LAST ACTIVE = newest user_progress.last_played, i.e. real listening activity
#                 on any platform. Usually the more meaningful of the two.

# ============================================================
# LOCAL ENVIRONMENT
# ============================================================
if [ "$ENV" == "local" ]; then
    echo -e "${YELLOW}[INFO]${NC} Reading users from local database..."

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
        const users = await prisma.user.findMany({
            orderBy: { createdAt: 'asc' },
            select: {
                username: true,
                isAdmin: true,
                createdAt: true,
                // Newest first, so [0] is the most recent — see the header note
                // on why these stand in for last login / last active.
                refreshTokens: {
                    select: { createdAt: true },
                    orderBy: { createdAt: 'desc' },
                    take: 1,
                },
                progress: {
                    select: { lastPlayed: true },
                    orderBy: { lastPlayed: 'desc' },
                    take: 1,
                },
                _count: { select: { progress: true, lists: true, deviceTokens: true } },
            },
        });
        const day = (d) => (d ? d.toISOString().slice(0, 10) : 'never');
        console.log('COUNT:' + users.length);
        for (const u of users) {
            console.log([
                'ROW:' + u.username,
                u.isAdmin ? 'yes' : 'no',
                day(u.createdAt),
                day(u.refreshTokens[0]?.createdAt),
                day(u.progress[0]?.lastPlayed),
                u._count.progress,
                u._count.lists,
                u._count.deviceTokens,
            ].join('\t'));
        }
    } catch (e) {
        console.log('ERROR:' + e.message);
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

    echo -e "${YELLOW}[INFO]${NC} Reading users from production database..."

    # Uses the `pg` driver directly — see the note in create-user.sh: the Prisma 7
    # client is TypeScript and the production image has no TS loader.
    #
    # The per-user counts are correlated subqueries rather than JOIN + GROUP BY so
    # that each one counts its own table independently; joining all three would
    # multiply the rows together and inflate every count.
    RESULT=$(remote_pg_exec "$CLUSTER" "$SERVICE" "$CONTAINER" "
    const r = await client.query(\`
      SELECT
        u.username,
        u.is_admin,
        to_char(u.created_at, 'YYYY-MM-DD') AS created,
        COALESCE(to_char((SELECT max(t.created_at) FROM refresh_tokens t WHERE t.user_id = u.id), 'YYYY-MM-DD'), 'never') AS last_login,
        COALESCE(to_char((SELECT max(p.last_played) FROM user_progress p WHERE p.user_id = u.id), 'YYYY-MM-DD'), 'never') AS last_active,
        (SELECT count(*) FROM user_progress p WHERE p.user_id = u.id)      AS progress,
        (SELECT count(*) FROM user_lists l WHERE l.user_id = u.id)         AS lists,
        (SELECT count(*) FROM user_device_tokens d WHERE d.user_id = u.id) AS devices
      FROM users u
      ORDER BY u.created_at ASC
    \`);
    console.log('COUNT:' + r.rowCount);
    for (const u of r.rows) {
      console.log(['ROW:' + u.username, u.is_admin ? 'yes' : 'no', u.created, u.last_login, u.last_active, u.progress, u.lists, u.devices].join('\t'));
    }
" 2>&1)
fi

# ============================================================
# CHECK RESULT
# ============================================================
if echo "$RESULT" | grep -q "ERROR:"; then
    ERROR_MSG=$(echo "$RESULT" | grep -o 'ERROR:.*' | cut -d: -f2-)
    echo -e "${RED}Error: $ERROR_MSG${NC}"
    exit 1
fi

if ! echo "$RESULT" | grep -q "COUNT:"; then
    echo -e "${RED}Error: Unexpected response${NC}"
    echo "$RESULT"
    exit 1
fi

COUNT=$(echo "$RESULT" | grep -o 'COUNT:[0-9]*' | head -1 | cut -d: -f2)

echo -e "${GREEN}[OK]${NC} Found ${COUNT} user(s)"
echo ""

if [ "$COUNT" -eq 0 ]; then
    echo -e "${YELLOW}No users found.${NC}"
    echo ""
    if [ "$ENV" == "local" ]; then
        echo -e "${YELLOW}[TIP]${NC} Seed the test user: npm run db:seed"
    else
        echo -e "${YELLOW}[TIP]${NC} Create one: npm run user:create prod <username>"
    fi
    echo ""
    exit 0
fi

# Strip the ROW: prefix and lay the columns out with the header.
{
    printf 'USERNAME\tADMIN\tCREATED\tLAST LOGIN\tLAST ACTIVE\tPROGRESS\tLISTS\tDEVICES\n'
    echo "$RESULT" | grep '^ROW:' | sed 's/^ROW://'
} | column -t -s "$(printf '\t')"

echo ""
echo -e "${CYAN}${COUNT} user(s) in ${ENV_UPPER}${NC}"
echo ""
