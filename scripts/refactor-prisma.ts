#!/usr/bin/env tsx
/**
 * Safe Prisma Client Refactoring Script
 *
 * Replaces `new PrismaClient()` with centralized singleton import
 * from @/lib/db across the entire codebase.
 */

import fs from 'fs/promises';
import path from 'path';

interface FileChange {
  file: string;
  success: boolean;
  error?: string;
}

const FILES_TO_UPDATE = [
  // API Routes
  'app/api/books/route.ts',
  'app/api/books/[id]/route.ts',
  'app/api/books/[id]/chapters/route.ts',
  'app/api/authors/[id]/route.ts',
  'app/api/narrators/[id]/route.ts',
  'app/api/categories/[id]/route.ts',
  'app/api/series/[id]/route.ts',
  'app/api/browse/authors/route.ts',
  'app/api/browse/narrators/route.ts',
  'app/api/browse/categories/route.ts',
  'app/api/browse/series/route.ts',
  'app/api/search/route.ts',
  'app/api/progress/route.ts',
  'app/api/library/route.ts',
  'app/api/library/[bookId]/route.ts',
  'app/api/library/check/route.ts',
  'app/api/library/series/[seriesId]/route.ts',
  'app/api/auth/register/route.ts',
  'app/api/user/password/route.ts',

  // Pages
  'app/page.tsx',
  'app/books/[id]/page.tsx',
  'app/books/[id]/play/page.tsx',
  'app/library/page.tsx',
  'app/search/page.tsx',
  'app/authors/[id]/page.tsx',
  'app/narrators/[id]/page.tsx',
  'app/categories/[id]/page.tsx',
  'app/series/[id]/page.tsx',
  'app/browse/authors/page.tsx',
  'app/browse/narrators/page.tsx',
  'app/browse/categories/page.tsx',
  'app/browse/series/page.tsx',

  // Components
  'components/ContinueListeningButton.tsx',
  'components/ContinueListening.tsx',

  // Lib
  'lib/auth.ts',

  // Scripts (these need special handling - keep disconnect)
  'scripts/import-libation.ts',
  'scripts/create-user.ts',
  'scripts/seed-test-user.ts',
];

async function refactorFile(filePath: string): Promise<FileChange> {
  const fullPath = path.join(process.cwd(), filePath);

  try {
    let content = await fs.readFile(fullPath, 'utf-8');
    let modified = false;

    // Step 1: Replace import statement
    if (content.includes("import { PrismaClient } from '@prisma/client';")) {
      content = content.replace(
        /import { PrismaClient } from '@prisma\/client';/g,
        "import { prisma } from '@/lib/db';"
      );
      modified = true;
    }

    // Step 2: Remove PrismaClient instantiation
    if (
      content.includes('const prisma = new PrismaClient();') ||
      content.includes('export const prisma = new PrismaClient();')
    ) {
      content = content.replace(/^const prisma = new PrismaClient\(\);$/gm, '');
      content = content.replace(/^export const prisma = new PrismaClient\(\);$/gm, '');
      modified = true;
    }

    // Step 3: For non-script files, remove $disconnect calls
    const isScript = filePath.startsWith('scripts/');
    if (!isScript) {
      // Remove standalone disconnect calls
      content = content.replace(/^\s*await prisma\.\$disconnect\(\);$/gm, '');

      // Remove empty finally blocks that only had disconnect
      content = content.replace(/\s*} finally {\s*}\s*$/gm, '\n  }\n');
    }

    // Step 4: Clean up extra blank lines
    content = content.replace(/\n{3,}/g, '\n\n');

    if (modified) {
      await fs.writeFile(fullPath, content, 'utf-8');
      return { file: filePath, success: true };
    } else {
      return { file: filePath, success: true, error: 'No changes needed' };
    }
  } catch (error) {
    return {
      file: filePath,
      success: false,
      error: error instanceof Error ? error.message : 'Unknown error',
    };
  }
}

async function main() {
  console.log('🔧 Starting Prisma Client refactoring...\n');

  const results: FileChange[] = [];

  for (const file of FILES_TO_UPDATE) {
    const result = await refactorFile(file);
    results.push(result);

    if (result.success) {
      if (result.error) {
        console.log(`⚪ ${file} - ${result.error}`);
      } else {
        console.log(`✅ ${file}`);
      }
    } else {
      console.log(`❌ ${file} - ${result.error}`);
    }
  }

  console.log('\n📊 Summary:');
  const successful = results.filter((r) => r.success && !r.error).length;
  const skipped = results.filter((r) => r.success && r.error).length;
  const failed = results.filter((r) => !r.success).length;

  console.log(`  ✅ Modified: ${successful}`);
  console.log(`  ⚪ Skipped:  ${skipped}`);
  console.log(`  ❌ Failed:   ${failed}`);

  if (failed > 0) {
    console.log('\n⚠️  Some files failed to update. Please review manually.');
    process.exit(1);
  } else {
    console.log('\n✨ Refactoring complete!');
  }
}

main().catch((error) => {
  console.error('💥 Script failed:', error);
  process.exit(1);
});
