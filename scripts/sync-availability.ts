/**
 * CLI wrapper for the nightly availability sync.
 *
 * Usage: npx tsx scripts/sync-availability.ts
 * Requires S3 access (production, or S3_ENABLED=true hybrid mode against the
 * real bucket — see docs/plans/s3-archive-restore-workflow-v2.md).
 */
import { syncAvailability } from '../lib/sync-availability';
import { prisma } from '../lib/db';

import { fileURLToPath } from 'url';

// ESM equivalent of `require.main === module` (the package is "type": "module").
const isMain = process.argv[1] === fileURLToPath(import.meta.url);

if (isMain) {
  syncAvailability()
    .then(async (r) => {
      console.log('✅ sync-availability:', JSON.stringify(r));
      await prisma.$disconnect();
      process.exit(0);
    })
    .catch(async (error) => {
      console.error('❌ sync-availability failed:', error);
      await prisma.$disconnect();
      process.exit(1);
    });
}
