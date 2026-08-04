#!/bin/bash
#
# Block committing obvious secrets. Runs from .husky/pre-commit.
#
# WHY, given GitHub already scans:
#
# GitHub secret scanning and push protection are both enabled on this repo (free
# on public repos) and are better than this script at what they do — they
# recognize hundreds of provider token formats and can validate them live.
#
# What they do NOT catch:
#   1. `.env` / `.env.local` files. There is no provider pattern for
#      "DATABASE_URL with a real password", so a committed .env sails through.
#   2. Anything at all, before it reaches GitHub. Push protection fires on push;
#      by then the secret is in your local history and removing it means a
#      rewrite. Catching it pre-commit means just `git reset`.
#   3. Private keys in formats their patterns miss.
#
# So this is deliberately narrow: filenames that should never be committed, plus
# a couple of unambiguous content patterns. It is NOT a general-purpose scanner —
# adding fuzzy entropy heuristics here would produce false positives on test
# fixtures and train everyone to use --no-verify, which is worse than no check.
#
# Bypass (rare, and think first): git commit --no-verify
#
# Usage:
#   ./scripts/check-staged-secrets.sh                 # staged changes (pre-commit)
#   ./scripts/check-staged-secrets.sh --range A..B     # every file changed in a range (CI)

set -euo pipefail

RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# In --range mode the "added lines" for each file are taken from that range
# rather than from the index, so CI can scan a whole PR without touching HEAD.
DIFF_ARGS=(--cached)
if [ "${1:-}" = "--range" ]; then
    [ -n "${2:-}" ] || { echo "--range needs a revision range" >&2; exit 2; }
    DIFF_ARGS=("$2")
fi

staged=$(git diff "${DIFF_ARGS[@]}" --name-only --diff-filter=ACM)
[ -z "$staged" ] && exit 0

fail=0

# ── 1. Filenames that are never legitimate ───────────────────────────────────
#
# .env.example is fine (placeholders only). certs/rds-global-bundle.pem is
# Amazon's PUBLIC RDS CA bundle — a trust anchor, 108 certificates and zero
# private keys — and is deliberately committed so the container can verify TLS.
while IFS= read -r file; do
    [ -z "$file" ] && continue
    case "$file" in
        .env.example|*.env.example) continue ;;
        certs/rds-global-bundle.pem) continue ;;
    esac

    case "$file" in
        .env|.env.*|*/.env|*/.env.*|*.pem|*.p8|*.p12|*.pfx|*.jks|*.keystore|id_rsa|id_dsa|id_ecdsa|id_ed25519|*.mobileprovision)
            echo -e "${RED}✖ refusing to commit${NC} $file"
            fail=1
            ;;
    esac
done <<< "$staged"

# ── 2. Content patterns with no plausible false positive ─────────────────────
#
# Checked against the staged diff, not the worktree, so it matches exactly what
# is about to be committed.
for file in $staged; do
    [ -f "$file" ] || continue
    case "$file" in
        # This script documents the patterns it looks for; skip itself and the
        # docs that discuss it.
        scripts/check-staged-secrets.sh|docs/*|*.md) continue ;;
    esac

    added=$(git diff "${DIFF_ARGS[@]}" -U0 -- "$file" | grep '^+' | grep -v '^+++' || true)
    [ -z "$added" ] && continue

    if printf '%s' "$added" | grep -qE -- '-----BEGIN [A-Z ]*PRIVATE KEY-----'; then
        echo -e "${RED}✖ private key material in${NC} $file"
        fail=1
    fi
    # AWS long-lived access key id. Genuinely unambiguous prefix + length.
    if printf '%s' "$added" | grep -qE 'AKIA[0-9A-Z]{16}'; then
        echo -e "${RED}✖ AWS access key id in${NC} $file"
        fail=1
    fi
    # A postgres URL carrying a non-placeholder password.
    if printf '%s' "$added" | grep -qE 'postgres(ql)?://[^:@/[:space:]]+:[^@/[:space:]]+@' \
        && ! printf '%s' "$added" | grep -qE 'postgres(ql)?://[^:@/[:space:]]+:(postgres|password|dev_password_change_in_production|<[^>]*>|\$\{[^}]*\})@'; then
        echo -e "${YELLOW}⚠ database URL with an embedded password in${NC} $file"
        echo "  Use an env var or AWS Secrets Manager. If this is a placeholder, make it obviously fake."
        fail=1
    fi
done

if [ "$fail" -ne 0 ]; then
    echo ""
    echo -e "${RED}Commit blocked.${NC} Unstage the file(s) above, or move the value to"
    echo "an environment variable / AWS Secrets Manager."
    echo ""
    echo "If this is a false positive: git commit --no-verify (and please tighten"
    echo "the pattern in scripts/check-staged-secrets.sh so the next person isn't"
    echo "trained to bypass the hook)."
    exit 1
fi

exit 0
