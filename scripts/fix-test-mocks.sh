#!/bin/bash

# Fix test mocks to use @/lib/db instead of @prisma/client

TEST_FILES=(
  "__tests__/scripts/import-libation.test.ts"
  "__tests__/scripts/seed-test-user.test.ts"
  "__tests__/pages/book-detail.test.tsx"
  "__tests__/pages/home.test.tsx"
  "__tests__/pages/browse-authors.test.tsx"
)

for file in "${TEST_FILES[@]}"; do
  if [[ -f "$file" ]]; then
    echo "Fixing: $file"

    # Add mock for @/lib/db before other imports
    if ! grep -q "jest.mock('@/lib/db'" "$file"; then
      # Find first import and add mock before it
      sed -i '' "1i\\
// Mock Prisma Client\\
jest.mock('@/lib/db', () => ({\\
  prisma: {\\
    book: { findMany: jest.fn(), findUnique: jest.fn(), count: jest.fn(), create: jest.fn() },\\
    author: { findUnique: jest.fn(), create: jest.fn() },\\
    narrator: { findUnique: jest.fn(), create: jest.fn() },\\
    series: { findFirst: jest.fn(), upsert: jest.fn() },\\
    category: { findFirst: jest.fn(), create: jest.fn() },\\
    user: { findUnique: jest.fn(), create: jest.fn() },\\
    userProgress: { findFirst: jest.fn(), upsert: jest.fn() },\\
    \\\$disconnect: jest.fn(),\\
  },\\
}));\\
" "$file"
    fi

    # Remove old PrismaClient import and mock
    sed -i '' "/import.*PrismaClient.*from '@prisma\/client'/d" "$file"
    sed -i '' "/jest.mock('@prisma\/client'/,/^});/d" "$file"

  fi
done

echo "Done!"
