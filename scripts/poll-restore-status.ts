/**
 * CLI wrapper for the restore-status poller.
 *
 * Usage: npx tsx scripts/poll-restore-status.ts
 */
import { pollRestoreStatus } from '../lib/poll-restore-status';
import { prisma } from '../lib/db';

if (require.main === module) {
  pollRestoreStatus()
    .then(async (r) => {
      console.log('✅ poll-restore-status:', JSON.stringify(r));
      await prisma.$disconnect();
      process.exit(0);
    })
    .catch(async (error) => {
      console.error('❌ poll-restore-status failed:', error);
      await prisma.$disconnect();
      process.exit(1);
    });
}
