import 'dotenv/config';
import { prisma } from '@/lib/db';
import bcrypt from 'bcryptjs';
import crypto from 'crypto';

// Generate a random password
function generateRandomPassword(length: number = 16): string {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%^&*';
  const randomBytes = crypto.randomBytes(length);
  let password = '';

  for (let i = 0; i < length; i++) {
    password += chars[randomBytes[i] % chars.length];
  }

  return password;
}

async function createUser(email: string) {
  console.log('🔐 Creating new user...\n');

  try {
    // Check if user already exists
    const existingUser = await prisma.user.findUnique({
      where: { email },
    });

    if (existingUser) {
      console.log(`❌ User with email ${email} already exists\n`);
      return;
    }

    // Generate random password
    const password = generateRandomPassword();

    // Hash password
    const passwordHash = await bcrypt.hash(password, 12);

    // Create user
    const user = await prisma.user.create({
      data: {
        email,
        passwordHash,
      },
    });

    console.log('✅ User created successfully!\n');
    console.log('═══════════════════════════════════════');
    console.log('📧 Email:    ', email);
    console.log('🔑 Password: ', password);
    console.log('═══════════════════════════════════════');
    console.log('\n⚠️  Please save these credentials and send them to the user.');
    console.log('⚠️  The password cannot be recovered after this script ends.\n');
  } catch (error) {
    console.error('❌ Error creating user:', error);
    throw error;
  } finally {
    await prisma.$disconnect();
  }
}

// Run if called directly
if (require.main === module) {
  const email = process.argv[2];

  if (!email) {
    console.error('❌ Usage: npm run user:create <email>\n');
    console.error('Example: npm run user:create john@example.com\n');
    process.exit(1);
  }

  // Validate email format
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  if (!emailRegex.test(email)) {
    console.error('❌ Invalid email format\n');
    process.exit(1);
  }

  createUser(email)
    .then(() => {
      process.exit(0);
    })
    .catch((error) => {
      console.error('Fatal error:', error);
      process.exit(1);
    });
}

export { createUser, generateRandomPassword };
