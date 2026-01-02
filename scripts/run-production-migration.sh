#!/bin/bash
set -e

# Script to run database migrations on local or production database
# Usage: ./scripts/run-production-migration.sh <environment> <migration-file>

if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: $0 <environment> <migration-file>"
  echo "Example: $0 production prisma/migrations/20260102_change_sequence_to_int/migration.sql"
  echo "Example: $0 local prisma/migrations/20260102_change_sequence_to_int/migration.sql"
  exit 1
fi

ENVIRONMENT="$1"
MIGRATION_FILE="$2"

# Validate environment
if [ "$ENVIRONMENT" != "local" ] && [ "$ENVIRONMENT" != "production" ]; then
  echo "Error: Environment must be 'local' or 'production'"
  exit 1
fi

if [ ! -f "$MIGRATION_FILE" ]; then
  echo "Error: Migration file not found: $MIGRATION_FILE"
  exit 1
fi

# Get DATABASE_URL based on environment
if [ "$ENVIRONMENT" = "production" ]; then
  echo "Retrieving production database credentials from AWS Secrets Manager..."
  
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
  
  echo "Production database connection retrieved"
else
  echo "Using local database connection from .env..."
  
  # Load DATABASE_URL from .env file
  if [ ! -f ".env" ]; then
    echo "Error: .env file not found"
    exit 1
  fi
  
  export $(grep "^DATABASE_URL=" .env | xargs)
  
  if [ -z "$DATABASE_URL" ]; then
    echo "Error: DATABASE_URL not found in .env file"
    exit 1
  fi
fi

echo "Running migration: $MIGRATION_FILE"
echo ""

# Run the migration using the full DATABASE_URL
psql "$DATABASE_URL" -f "$MIGRATION_FILE"

if [ $? -eq 0 ]; then
  echo ""
  echo "✅ Migration applied successfully!"
else
  echo ""
  echo "❌ Migration failed!"
  exit 1
fi
