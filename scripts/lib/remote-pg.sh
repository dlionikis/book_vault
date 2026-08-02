#!/usr/bin/env bash
#
# Shared helper for running SQL against production RDS from inside a running
# ECS task, over `pg` directly.
#
# Why this exists — three things about the Prisma 7 + slim-image setup make the
# obvious approaches fail, and each of them broke a script in this directory:
#
#   1. TLS is not automatic. Prisma 7 delegates connections to the `pg` driver,
#      which attempts no TLS unless told to, and RDS refuses unencrypted
#      connections ("no pg_hba.conf entry ... no encryption"). `sslmode=require`
#      is NOT a fix either: as of pg 8.22 it verifies against the *system* trust
#      store, and RDS serves an Amazon-signed certificate. Verification needs
#      Amazon's CA explicitly — the bundle the Dockerfile ships at
#      $RDS_CA_PATH. Same reasoning as lib/db-ssl.ts, which this mirrors;
#      that module is TypeScript and the runtime image has no TS loader, so it
#      cannot be imported here.
#
#   2. `node -e "...require('pg')..."` fails. package.json sets
#      "type": "module", so inline scripts are parsed as ESM and `require` is
#      undefined. Snippets must be written to a `.cjs` file instead.
#
#   3. Module resolution is relative to the script's directory, so that file has
#      to live under /app (next to node_modules), not /tmp.
#
# There is also no Prisma CLI and no psql in the runtime image, so
# `prisma migrate status` and `psql` are both unavailable there.
#
# Usage:
#   source "$(dirname "$0")/lib/remote-pg.sh"
#   remote_pg_exec "$CLUSTER" "$SERVICE" "$CONTAINER" "$JS_BODY"
#
# $JS_BODY is CommonJS run with `client` already connected and in scope. It must
# resolve/return on its own; the wrapper closes the connection and exits.

RDS_CA_PATH="/app/certs/rds-global-bundle.pem"

# Find a running task ARN for a service, or fail with a useful message.
remote_pg_task_arn() {
    local cluster="$1" service="$2" task_arn
    task_arn=$(aws ecs list-tasks \
        --cluster "$cluster" \
        --service-name "$service" \
        --desired-status RUNNING \
        --query 'taskArns[0]' \
        --output text 2>/dev/null)

    if [[ -z "$task_arn" || "$task_arn" == "None" ]]; then
        echo "ERROR: no running tasks found in service $service" >&2
        return 1
    fi
    echo "$task_arn"
}

# Wrap a CommonJS body in the connect/teardown boilerplate, including the TLS
# config that RDS requires.
remote_pg_wrap() {
    local body="$1"
    cat <<WRAPPER
const fs = require('fs');
const { Client } = require('pg');

// TLS with real verification against Amazon's CA (see header comment).
const client = new Client({
  connectionString: process.env.DATABASE_URL,
  ssl: {
    ca: fs.readFileSync('${RDS_CA_PATH}', 'utf8'),
    rejectUnauthorized: true,
  },
});

(async () => {
  await client.connect();
  try {
${body}
  } catch (e) {
    console.error('ERROR:' + e.message);
    process.exitCode = 1;
  } finally {
    await client.end();
  }
})();
WRAPPER
}

# Run a CommonJS body against production RDS inside a running task.
#
#   remote_pg_exec CLUSTER SERVICE CONTAINER BODY [ARG...]
#
# Everything after BODY is passed to the remote script as argv (readable as
# process.argv[2], [3], ...). Values should always be passed that way rather
# than interpolated into BODY: quoting user input through
# `aws ecs execute-command` -> sh -> node is where the previous versions of
# these scripts kept breaking, and it is also how SQL injection would creep in.
#
# The script itself is base64-encoded for the same reason.
remote_pg_exec() {
    local cluster="$1" service="$2" container="$3" body="$4"
    shift 4
    local task_arn encoded script remote_args=""

    task_arn=$(remote_pg_task_arn "$cluster" "$service") || return 1

    script=$(remote_pg_wrap "$body")
    encoded=$(printf '%s' "$script" | base64 | tr -d '\n')

    # Each argv value is base64-encoded and decoded by the remote shell, so no
    # quoting or escaping of the caller's data is needed anywhere in between.
    local a
    for a in "$@"; do
        remote_args+=" \"\$(echo $(printf '%s' "$a" | base64 | tr -d '\n') | base64 -d)\""
    done

    # Written under /app so `require('pg')` resolves, with a .cjs extension so
    # it is not parsed as ESM. Removed afterwards even on failure.
    aws ecs execute-command \
        --cluster "$cluster" \
        --task "$task_arn" \
        --container "$container" \
        --interactive \
        --command "sh -c 'cd /app && echo ${encoded} | base64 -d > /app/.remote-pg.cjs && node /app/.remote-pg.cjs${remote_args}; rc=\$?; rm -f /app/.remote-pg.cjs; exit \$rc'"
}
