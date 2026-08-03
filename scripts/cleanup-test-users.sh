#!/bin/bash
#
# Remove test accounts from an environment after testing is finished.
#
# Usage: ./scripts/cleanup-test-users.sh <local|prod> [--check] [--yes]
#
# Examples:
#   ./scripts/cleanup-test-users.sh prod --check   # Report only, change nothing
#   ./scripts/cleanup-test-users.sh prod           # Delete, with confirmation
#   ./scripts/cleanup-test-users.sh prod --yes     # Delete without prompting (CI)
#
# Prerequisites:
#   - Node.js with Prisma available (npm install)
#   - For local: Docker running with PostgreSQL
#   - For prod: AWS CLI configured, Session Manager plugin installed
#
# WHY THIS EXISTS
#
# The seeded `testuser` account uses the password published in this repository
# (CLAUDE.md, README.md, .env.example, docs/*). The repo is public, so any
# environment reachable from the internet that still has this account is
# accepting a publicly documented credential. It was found live in production
# on 2026-08-03: the account authenticated, listed the full catalog, and
# obtained audio streaming URLs. It could not reach /api/admin/* (403).
#
# `testuser` is legitimately needed in production for short App Store review and
# smoke-test windows. This script is the "we're done testing" step: run it with
# --check to see whether an account is lingering, and without --check to remove
# it.
#
# Deleting a user is a HARD delete and cascades to every user-owned table
# (progress, lists, downloads, device tokens, refresh tokens, restore
# requests). See scripts/delete-user.sh. There is no soft-delete or disabled
# flag on the users table.
#
# Accounts targeted (weak/shared credentials only — see TEST_USERNAMES below).
# Real accounts are never touched; use scripts/delete-user.sh for those.
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

# Accounts this script is allowed to delete, matched exactly. Deliberately an
# explicit list rather than a loose pattern: a prefix match like "test%" would
# eventually catch a real account. `app-review-tester` is intentionally NOT here
# — it is a deliberate App Store review account with its own password, so
# removing it is a judgement call, not cleanup.
TEST_USERNAMES=("testuser")

# Throwaway accounts created by the contract suite, matched as a LIKE prefix.
#
# __tests__/api/openapi-contract.test.ts registers `contract-nonadmin-<epoch_ms>`
# to prove the admin gate returns 403 and never removes it, so one row leaks per
# contract-test run (109 had accumulated locally by 2026-08-03). The timestamp
# suffix means these cannot be listed by name.
#
# The trailing digits are required by the pattern, so a human account would have
# to be literally named `contract-nonadmin-<digits>` to match.
TEST_USERNAME_PREFIXES=("contract-nonadmin-")

# Shared TLS/exec plumbing for talking to RDS from inside a task.
# shellcheck source=scripts/lib/remote-pg.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/remote-pg.sh"

# Change to project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

# Parse arguments
ENV=""
CHECK_ONLY=0
ASSUME_YES=0

for arg in "$@"; do
    case "$arg" in
        --check) CHECK_ONLY=1 ;;
        --yes|-y) ASSUME_YES=1 ;;
        local|prod) ENV="$arg" ;;
        *)
            echo -e "${RED}Error: unknown argument '$arg'${NC}"
            echo ""
            echo "Usage: $0 <local|prod> [--check] [--yes]"
            exit 1
            ;;
    esac
done

if [ -z "$ENV" ]; then
    echo -e "${RED}Error: Environment required${NC}"
    echo ""
    echo "Usage: $0 <local|prod> [--check] [--yes]"
    echo ""
    echo "Examples:"
    echo "  $0 prod --check   # Report only, change nothing"
    echo "  $0 prod           # Delete, with confirmation"
    echo "  $0 prod --yes     # Delete without prompting"
    exit 1
fi

ENV_UPPER=$(echo "$ENV" | tr '[:lower:]' '[:upper:]')
NAMES_CSV=$(IFS=,; echo "${TEST_USERNAMES[*]}")
PREFIXES_CSV=$(IFS=,; echo "${TEST_USERNAME_PREFIXES[*]}")

echo ""
if [ "$CHECK_ONLY" -eq 1 ]; then
    echo -e "${CYAN}Checking for test accounts in ${ENV_UPPER}${NC}"
else
    echo -e "${CYAN}Removing test accounts from ${ENV_UPPER}${NC}"
fi
echo -e "${CYAN}Targets: ${NAMES_CSV}, ${PREFIXES_CSV}<digits>${NC}"
echo ""

# ============================================================
# FIND
# ============================================================
# Emits one FOUND:<username> line per existing target, then FOUND_COUNT:<n>.
if [ "$ENV" == "local" ]; then
    echo -e "${YELLOW}[INFO]${NC} Querying local database..."

    # Prisma 7 generates a TypeScript client (lib/generated/prisma), so this runs
    # under tsx rather than plain node, and needs the pg driver adapter.
    FOUND=$(TARGETS="$NAMES_CSV" PREFIXES="$PREFIXES_CSV" npx tsx -e "
import 'dotenv/config';
import { PrismaPg } from '@prisma/adapter-pg';
import { PrismaClient } from './lib/generated/prisma/client';

(async () => {
    const prisma = new PrismaClient({
        adapter: new PrismaPg({ connectionString: process.env.DATABASE_URL }),
    });
    try {
        const names = process.env.TARGETS ? process.env.TARGETS.split(',') : [];
        const prefixes = process.env.PREFIXES ? process.env.PREFIXES.split(',') : [];
        const users = await prisma.user.findMany({
            where: {
                OR: [
                    { username: { in: names } },
                    ...prefixes.map((p) => ({ username: { startsWith: p } })),
                ],
            },
            select: { username: true },
            orderBy: { createdAt: 'asc' },
        });
        // The prefix match is broader than the pattern documented at the top of
        // this script (startsWith has no \\d+ anchor), so require trailing digits
        // here to keep the two consistent.
        const keep = users.filter(
            (u) =>
                names.includes(u.username) ||
                prefixes.some((p) => u.username.startsWith(p) && /^[0-9]+\$/.test(u.username.slice(p.length)))
        );
        for (const u of keep) console.log('FOUND:' + u.username);
        console.log('FOUND_COUNT:' + keep.length);
    } catch (e) {
        console.log('ERROR:' + e.message);
    } finally {
        await prisma.\$disconnect();
    }
})();
" 2>&1)
else
    echo -e "${YELLOW}[INFO]${NC} Finding running ECS task..."
    TASK_ARN=$(remote_pg_task_arn "$CLUSTER" "$SERVICE") || exit 1
    echo -e "${GREEN}[OK]${NC} Found task: ${TASK_ARN##*/}"

    echo -e "${YELLOW}[INFO]${NC} Querying production database..."

    # Uses the `pg` driver directly — see the note in create-user.sh: the Prisma 7
    # client is TypeScript and the production image has no TS loader. Usernames
    # travel as argv rather than interpolated SQL.
    # argv is <name-count> then that many exact names, then the prefixes.
    FOUND=$(remote_pg_exec "$CLUSTER" "$SERVICE" "$CONTAINER" "
    const argv = process.argv.slice(2);
    const nameCount = parseInt(argv[0], 10);
    const names = argv.slice(1, 1 + nameCount);
    const prefixes = argv.slice(1 + nameCount);
    // '<prefix>%' with a digits-only remainder, matching the exact-name list
    // plus the documented contract-suite pattern and nothing else.
    const r = await client.query(
      \"SELECT username FROM users WHERE username = ANY(\$1) OR EXISTS (SELECT 1 FROM unnest(\$2::text[]) pfx WHERE username LIKE pfx || '%' AND substring(username from length(pfx) + 1) ~ '^[0-9]+$') ORDER BY created_at ASC\",
      [names, prefixes]
    );
    for (const row of r.rows) console.log('FOUND:' + row.username);
    console.log('FOUND_COUNT:' + r.rowCount);
" "${#TEST_USERNAMES[@]}" "${TEST_USERNAMES[@]}" "${TEST_USERNAME_PREFIXES[@]}" 2>&1)
fi

if echo "$FOUND" | grep -q "ERROR:"; then
    ERROR_MSG=$(echo "$FOUND" | grep -o 'ERROR:.*' | cut -d: -f2-)
    echo -e "${RED}Error: $ERROR_MSG${NC}"
    exit 1
fi

if ! echo "$FOUND" | grep -q "FOUND_COUNT:"; then
    echo -e "${RED}Error: Unexpected response${NC}"
    echo "$FOUND"
    exit 1
fi

FOUND_COUNT=$(echo "$FOUND" | grep -o 'FOUND_COUNT:[0-9]*' | head -1 | cut -d: -f2)
FOUND_NAMES=$(echo "$FOUND" | grep '^FOUND:' | sed 's/^FOUND://')

# ============================================================
# CLEAN
# ============================================================
if [ "$FOUND_COUNT" -eq 0 ]; then
    echo ""
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo -e "${GREEN}  Clean — no test accounts present${NC}"
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo ""
    echo "  Environment: ${ENV_UPPER}"
    echo "  Checked:     ${NAMES_CSV}, ${PREFIXES_CSV}<digits>"
    echo ""
    exit 0
fi

echo ""
echo -e "${YELLOW}Found ${FOUND_COUNT} test account(s):${NC}"
while IFS= read -r name; do
    [ -n "$name" ] && echo "  - $name"
done <<< "$FOUND_NAMES"
echo ""

if [ "$CHECK_ONLY" -eq 1 ]; then
    if [ "$ENV" == "prod" ]; then
        echo -e "${RED}These accounts use the password published in this public repository.${NC}"
        echo -e "${RED}Anyone can authenticate and stream the catalog.${NC}"
        echo ""
    fi
    echo -e "${YELLOW}[TIP]${NC} Remove them: npm run user:cleanup ${ENV}"
    echo ""
    # Non-zero so CI can fail on a lingering account.
    exit 2
fi

if [ "$ASSUME_YES" -ne 1 ]; then
    echo -e "${YELLOW}WARNING: this permanently deletes each account and all of its data${NC}"
    echo -e "${YELLOW}(progress, lists, downloads, device tokens, refresh tokens).${NC}"
    echo ""
    read -p "Delete these ${FOUND_COUNT} account(s) from ${ENV_UPPER}? (yes/no): " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        echo -e "${YELLOW}Aborted.${NC}"
        exit 0
    fi
    echo ""
fi

# The delete is issued here rather than by shelling out to delete-user.sh.
#
# Piping `yes` into that script does not work for prod: it answers the
# confirmation prompt, but `aws ecs execute-command --interactive` then inherits
# an exhausted stdin and fails, so the wrapper reported FAIL even though the row
# was deleted. Confirmation has already been handled above, so the prompt is not
# wanted here anyway. Use scripts/delete-user.sh for one-off interactive deletes.
#
# Both branches count deletions from what the database actually reports, not
# from the exit status, so a partial failure is visible.
DELETED=0
NAMES_TO_DELETE=$(echo "$FOUND_NAMES" | grep -v '^$' | tr '\n' ',' | sed 's/,$//')

# The full list is already printed above; a leak can run to hundreds of names,
# so only the count is echoed here.
echo -e "${YELLOW}[INFO]${NC} Deleting ${FOUND_COUNT} account(s)..."

if [ "$ENV" == "local" ]; then
    # Prisma 7 generates a TypeScript client (lib/generated/prisma), so this runs
    # under tsx rather than plain node, and needs the pg driver adapter.
    DEL_RESULT=$(TARGETS="$NAMES_TO_DELETE" npx tsx -e "
import 'dotenv/config';
import { PrismaPg } from '@prisma/adapter-pg';
import { PrismaClient } from './lib/generated/prisma/client';

(async () => {
    const prisma = new PrismaClient({
        adapter: new PrismaPg({ connectionString: process.env.DATABASE_URL }),
    });
    try {
        const names = process.env.TARGETS.split(',');
        // Every user-owned table cascades at the DB level (ON DELETE CASCADE).
        const r = await prisma.user.deleteMany({ where: { username: { in: names } } });
        console.log('DELETED_COUNT:' + r.count);
    } catch (e) {
        console.log('ERROR:' + e.message);
    } finally {
        await prisma.\$disconnect();
    }
})();
" 2>&1)
else
    # Usernames travel as argv, never interpolated into the SQL.
    DEL_RESULT=$(remote_pg_exec "$CLUSTER" "$SERVICE" "$CONTAINER" "
    const names = process.argv.slice(2);
    const r = await client.query('DELETE FROM users WHERE username = ANY(\$1)', [names]);
    console.log('DELETED_COUNT:' + r.rowCount);
" $(echo "$FOUND_NAMES" | grep -v '^$' | tr '\n' ' ') 2>&1)
fi

if echo "$DEL_RESULT" | grep -q "DELETED_COUNT:"; then
    DELETED=$(echo "$DEL_RESULT" | grep -o 'DELETED_COUNT:[0-9]*' | head -1 | cut -d: -f2)
elif echo "$DEL_RESULT" | grep -q "ERROR:"; then
    ERROR_MSG=$(echo "$DEL_RESULT" | grep -o 'ERROR:.*' | cut -d: -f2-)
    echo -e "${RED}Error: $ERROR_MSG${NC}"
    exit 1
else
    echo -e "${RED}Error: Unexpected response${NC}"
    echo "$DEL_RESULT"
    exit 1
fi

echo ""
if [ "$DELETED" -eq "$FOUND_COUNT" ]; then
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo -e "${GREEN}  Removed ${DELETED} test account(s)${NC}"
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo ""
    echo "  Environment: ${ENV_UPPER}"
    echo ""
    echo -e "${YELLOW}[TIP]${NC} Verify: npm run user:list ${ENV}"
    echo ""
else
    echo -e "${RED}Removed ${DELETED} of ${FOUND_COUNT} — rerun or use scripts/delete-user.sh${NC}"
    echo ""
    exit 1
fi
