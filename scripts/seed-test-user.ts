import 'dotenv/config';
import { PrismaClient } from '@prisma/client';
import bcrypt from 'bcryptjs';

const prisma = new PrismaClient();

const TEST_USER_EMAIL = process.env.TEST_USER_EMAIL || 'test@example.com';
const TEST_USER_PASSWORD = process.env.TEST_USER_PASSWORD || 'password123';

async function seedTestUser() {
  console.log('🌱 Seeding test user...\n');

  try {
    // Check if test user already exists
    const existingUser = await prisma.user.findUnique({
      where: { email: TEST_USER_EMAIL },
    });

    if (existingUser) {
      console.log(`✅ Test user already exists: ${TEST_USER_EMAIL}`);
      console.log('   (Use this email to login)\n');
      return;
    }

    // Hash password
    const passwordHash = await bcrypt.hash(TEST_USER_PASSWORD, 12);

    // Create test user
    const user = await prisma.user.create({
      data: {
        email: TEST_USER_EMAIL,
        passwordHash,
      },
    });

    console.log(`✅ Test user created successfully!`);
    console.log(`   Email: ${TEST_USER_EMAIL}`);
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
if (require.main === module) {
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
