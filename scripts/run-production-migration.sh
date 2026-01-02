#!/bin/bash
set -e

# Script to run database migrations on production RDS using AWS Secrets Manager
# Usage: ./scripts/run-production-migration.sh <migration-file>

if [ -z "$1" ]; then
  echo "Usage: $0 <migration-file>"
  echo "Example: $0 prisma/migrations/20260102_change_sequence_to_int/migration.sql"
  exit 1
fi

MIGRATION_FILE="$1"

if [ ! -f "$MIGRATION_FILE" ]; then
  echo "Error: Migration file not found: $MIGRATION_FILE"
  exit 1
fi

echo "Retrieving database credentials from AWS Secrets Manager..."

# Retrieve the DATABASE_URL from Secrets Manager
DATABASE_URL=$(aws secretsmanager get-secret-value \
  --secret-id book-vault/database \
  --profile book_vault \
  --region us-east-1 \
  --query SecretString \
  --output text | jq -r '.DATABASE_URL')

if [ -z "$DATABASE_URL" ]; then
  echo "Error: Failed to retrieve database credentials"
  exit 1
fi

# Parse the DATABASE_URL
# Format: postgresql://user:password@host:port/database
DB_USER=$(echo "$DATABASE_URL" | sed -n 's|postgresql://\([^:]*\):.*|\1|p')
DB_PASS=$(echo "$DATABASE_URL" | sed -n 's|postgresql://[^:]*:\([^@]*\)@.*|\1|p')
DB_HOST=$(echo "$DATABASE_URL" | sed -n 's|postgresql://[^@]*@\([^:]*\):.*|\1|p')
DB_PORT=$(echo "$DATABASE_URL" | sed -n 's|postgresql://[^@]*@[^:]*:\([0-9]*\)/.*|\1|p')
DB_NAME=$(echo "$DATABASE_URL" | sed -n 's|postgresql://[^/]*/\(.*\)|\1|p')

echo "Database: $DB_NAME"
echo "Host: $DB_HOST"
echo "Running migration: $MIGRATION_FILE"
echo ""

# Run the migration
PGPASSWORD="$DB_PASS" psql \
  -h "$DB_HOST" \
  -p "$DB_PORT" \
  -U "$DB_USER" \
  -d "$DB_NAME" \
  -f "$MIGRATION_FILE"

if [ $? -eq 0 ]; then
  echo ""
  echo "✅ Migration applied successfully!"
else
  echo ""
  echo "❌ Migration failed!"
  exit 1
fi
