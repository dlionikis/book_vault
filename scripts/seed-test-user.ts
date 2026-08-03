import 'dotenv/config';
import { prisma } from '@/lib/db';
import bcrypt from 'bcryptjs';

import { fileURLToPath } from 'url';

// ESM equivalent of `require.main === module` (the package is "type": "module").
const isMain = process.argv[1] === fileURLToPath(import.meta.url);

const TEST_USER_USERNAME = process.env.TEST_USER_USERNAME || 'testuser';
const TEST_USER_PASSWORD = process.env.TEST_USER_PASSWORD || 'password123';

/**
 * A second account that is guaranteed NOT to be an admin.
 *
 * The contract suite needs a reliably non-admin login to assert that
 * admin-gated routes return 403. It used to POST /api/auth/register for one,
 * because `testuser`'s admin flag differs between CI and local databases. That
 * endpoint was open registration on a public production site and has been
 * removed, and it leaked one row per test run (109 had accumulated locally).
 *
 * Seeding a fixed account fixes both: deterministic in every environment, and
 * nothing accumulates.
 */
const NONADMIN_USERNAME = process.env.TEST_NONADMIN_USERNAME || 'testuser-nonadmin';
const NONADMIN_PASSWORD = process.env.TEST_NONADMIN_PASSWORD || 'password123';

/**
 * Create a user if absent, or repair its admin flag if it drifted.
 *
 * `isAdmin` is written on every run rather than only at creation: the value is
 * what the contract tests depend on, and a database seeded before this flag
 * mattered would otherwise keep a stale one forever.
 */
async function upsertUser(username: string, password: string, isAdmin: boolean) {
  const existing = await prisma.user.findUnique({
    where: { username },
    select: { id: true, isAdmin: true },
  });

  if (existing) {
    if (existing.isAdmin !== isAdmin) {
      await prisma.user.update({ where: { username }, data: { isAdmin } });
      console.log(`✅ ${username} already existed — corrected isAdmin to ${isAdmin}`);
    } else {
      console.log(`✅ ${username} already exists (isAdmin: ${isAdmin})`);
    }
    return;
  }

  const passwordHash = await bcrypt.hash(password, 12);
  await prisma.user.create({ data: { username, passwordHash, isAdmin } });
  console.log(`✅ Created ${username} / ${password} (isAdmin: ${isAdmin})`);
}

async function seedTestUser() {
  console.log('🌱 Seeding test users...\n');

  try {
    // The primary dev account, seeded as an ADMIN.
    //
    // The contract suite exercises both sides of the admin gate on
    // POST /api/books/{id}/chapters: it expects 200 as TEST_USER and 403 as the
    // non-admin below. That only held when `testuser` happened to be an admin,
    // which is why the suite used to note that the flag "differs between CI and
    // local databases" — reseeding a database silently flipped it and broke the
    // 200 case. Pinning it here makes both assertions deterministic.
    await upsertUser(TEST_USER_USERNAME, TEST_USER_PASSWORD, true);

    // The guaranteed non-admin, for the 403 side of that same gate.
    await upsertUser(NONADMIN_USERNAME, NONADMIN_PASSWORD, false);

    console.log('\n   (Log in with the username, not an email address.)\n');
  } catch (error) {
    console.error('❌ Error seeding test users:', error);
    throw error;
  } finally {
    await prisma.$disconnect();
  }
}

// Run if called directly
if (isMain) {
  seedTestUser()
    .then(() => {
      console.log('✨ Done!');
      process.exit(0);
    })
    .catch((error) => {
      console.error('Fatal error:', error);
      process.exit(1);
    });
}

export { seedTestUser };
