import 'dotenv/config';
import { prisma } from '@/lib/db';
import bcrypt from 'bcryptjs';

/**
 * Seed the deterministic fixtures the Playwright web smoke (Phase 6) depends on:
 *   1. A test user (same credentials as scripts/seed-test-user.ts).
 *   2. A single known book that is searchable, playable, and add-to-library-able.
 *
 * The book is intentionally MEDIA-FREE: `audioUrl` is set (so the play page
 * renders the player instead of the "No Audio Available" fallback), but no real
 * audio bytes exist. The smoke asserts the player UI appears and its state
 * toggles on click — it does NOT decode audio. Actual streaming is covered by
 * the iOS device smoke, not here.
 *
 * The book has NO series, so "Add to Library" adds in one click without opening
 * the series dialog.
 *
 * Idempotent: safe to run repeatedly (upserts by unique keys).
 */

const TEST_USER_USERNAME = process.env.TEST_USER_USERNAME || 'testuser';
const TEST_USER_PASSWORD = process.env.TEST_USER_PASSWORD || 'password123';

// Stable, unique fixture identifiers the spec imports so selectors never drift.
export const E2E_BOOK = {
  asin: 'E2ESMOKE001',
  // A distinctive title so search matches exactly one book regardless of other data.
  title: 'Zephyr Protocol (E2E Smoke Fixture)',
  author: 'Ada E2E Author',
  narrator: 'Nora E2E Narrator',
  audioUrl: 'e2e-fixtures/zephyr-protocol.m4b',
} as const;

async function seedUser(): Promise<void> {
  const existing = await prisma.user.findUnique({
    where: { username: TEST_USER_USERNAME },
  });
  if (existing) {
    console.log(`✅ Test user already exists: ${TEST_USER_USERNAME}`);
    return;
  }
  const passwordHash = await bcrypt.hash(TEST_USER_PASSWORD, 12);
  await prisma.user.create({
    data: { username: TEST_USER_USERNAME, passwordHash },
  });
  console.log(`✅ Test user created: ${TEST_USER_USERNAME}`);
}

async function seedBook(): Promise<void> {
  const book = await prisma.book.upsert({
    where: { asin: E2E_BOOK.asin },
    update: {
      title: E2E_BOOK.title,
      audioUrl: E2E_BOOK.audioUrl,
      runtimeMinutes: 60,
    },
    create: {
      asin: E2E_BOOK.asin,
      title: E2E_BOOK.title,
      description: 'A deterministic fixture book for the Playwright web smoke test.',
      audioUrl: E2E_BOOK.audioUrl,
      runtimeMinutes: 60,
    },
  });

  // Author + link (idempotent).
  const author = await prisma.author.upsert({
    where: { name: E2E_BOOK.author },
    update: {},
    create: { name: E2E_BOOK.author },
  });
  await prisma.bookAuthor.upsert({
    where: { bookId_authorId: { bookId: book.id, authorId: author.id } },
    update: {},
    create: { bookId: book.id, authorId: author.id },
  });

  // Narrator + link (idempotent).
  const narrator = await prisma.narrator.upsert({
    where: { name: E2E_BOOK.narrator },
    update: {},
    create: { name: E2E_BOOK.narrator },
  });
  await prisma.bookNarrator.upsert({
    where: { bookId_narratorId: { bookId: book.id, narratorId: narrator.id } },
    update: {},
    create: { bookId: book.id, narratorId: narrator.id },
  });

  // One chapter so the play page's chapter list has content.
  await prisma.chapter.upsert({
    where: { bookId_chapterNumber: { bookId: book.id, chapterNumber: 1 } },
    update: { title: 'Chapter 1', startTime: 0, endTime: 3600, duration: 3600 },
    create: {
      bookId: book.id,
      chapterNumber: 1,
      title: 'Chapter 1',
      startTime: 0,
      endTime: 3600,
      duration: 3600,
    },
  });

  // Reset mutable state the smoke asserts on: the test adds this book to the
  // library and expects to start from "not in library". Remove any prior
  // membership (and progress) so the run is idempotent no matter how many times
  // the smoke has run before.
  await prisma.userListBook.deleteMany({ where: { bookId: book.id } });
  await prisma.userProgress.deleteMany({ where: { bookId: book.id } });

  console.log(`✅ E2E book seeded + state reset: "${E2E_BOOK.title}" (${book.id})`);
}

export async function seedE2E(): Promise<void> {
  console.log('🌱 Seeding E2E fixtures (user + book)...\n');
  await seedUser();
  await seedBook();
  console.log('\n✨ E2E seed complete.');
}

if (require.main === module) {
  seedE2E()
    .then(async () => {
      await prisma.$disconnect();
      process.exit(0);
    })
    .catch(async (error) => {
      console.error('❌ E2E seed failed:', error);
      await prisma.$disconnect();
      process.exit(1);
    });
}
