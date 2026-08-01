import 'dotenv/config';
import { prisma } from '@/lib/db';
import bcrypt from 'bcryptjs';

import { fileURLToPath } from 'url';

// ESM equivalent of `require.main === module` (the package is "type": "module").
const isMain = process.argv[1] === fileURLToPath(import.meta.url);

const TEST_USER_USERNAME = process.env.TEST_USER_USERNAME || 'testuser';
const TEST_USER_PASSWORD = process.env.TEST_USER_PASSWORD || 'password123';

async function seedTestUser() {
  console.log('🌱 Seeding test user...\n');

  try {
    // Check if test user already exists
    const existingUser = await prisma.user.findUnique({
      where: { username: TEST_USER_USERNAME },
    });

    if (existingUser) {
      console.log(`✅ Test user already exists: ${TEST_USER_USERNAME}`);
      console.log('   (Use this username to login)\n');
      return;
    }

    // Hash password
    const passwordHash = await bcrypt.hash(TEST_USER_PASSWORD, 12);

    // Create test user
    const user = await prisma.user.create({
      data: {
        username: TEST_USER_USERNAME,
        passwordHash,
      },
    });

    console.log(`✅ Test user created successfully!`);
    console.log(`   Username: ${TEST_USER_USERNAME}`);
    console.log(`   Password: ${TEST_USER_PASSWORD}`);
    console.log(`   (Use these credentials to login)\n`);
  } catch (error) {
    console.error('❌ Error seeding test user:', error);
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
