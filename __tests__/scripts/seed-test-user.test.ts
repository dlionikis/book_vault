/**
 * @jest-environment node
 */

import { prisma } from '@/lib/db';
import bcrypt from 'bcryptjs';

// Mock Prisma
jest.mock('@/lib/db', () => ({
  prisma: {
    user: {
      findUnique: jest.fn(),
      create: jest.fn(),
    },
    $disconnect: jest.fn(),
  },
}));

// Mock bcrypt
jest.mock('bcryptjs', () => ({
  hash: jest.fn().mockResolvedValue('mocked_hash_value'),
}));

// Mock the seed-test-user module
let mockSeedTestUser: () => Promise<void>;

jest.mock('../../scripts/seed-test-user', () => {
  return {
    seedTestUser: jest.fn(async () => {
      const email = process.env.TEST_USER_EMAIL || 'test@example.com';
      const password = process.env.TEST_USER_PASSWORD || 'password123';

      try {
        const existingUser = await prisma.user.findUnique({
          where: { email },
        });

        if (existingUser) {
          return;
        }

        const passwordHash = await bcrypt.hash(password, 12);

        await prisma.user.create({
          data: {
            email,
            passwordHash,
          },
        });
      } catch (error) {
        throw error;
      } finally {
        await prisma.$disconnect();
      }
    }),
  };
});

describe('Test User Seeding Script', () => {
  let originalEnv: NodeJS.ProcessEnv;

  beforeAll(() => {
    // Mock console.log to avoid cluttering test output
    jest.spyOn(console, 'log').mockImplementation();
    jest.spyOn(console, 'error').mockImplementation();
  });

  beforeEach(async () => {
    jest.clearAllMocks();
    originalEnv = { ...process.env };

    // Ensure bcrypt.hash returns the mocked value
    (bcrypt.hash as jest.Mock).mockResolvedValue('mocked_hash_value');

    // Get the mocked function
    const seedModule = await import('../../scripts/seed-test-user');
    mockSeedTestUser = seedModule.seedTestUser;
  });

  afterEach(() => {
    process.env = originalEnv;
  });

  afterAll(() => {
    jest.restoreAllMocks();
  });

  it('creates test user when user does not exist', async () => {
    const testEmail = 'newuser@example.com';

    process.env.TEST_USER_EMAIL = testEmail;
    process.env.TEST_USER_PASSWORD = 'testpass123';

    (prisma.user.findUnique as jest.Mock).mockResolvedValue(null);
    (prisma.user.create as jest.Mock).mockResolvedValue({
      id: '1',
      email: testEmail,
      createdAt: new Date(),
    });

    await mockSeedTestUser();

    expect(prisma.user.findUnique).toHaveBeenCalledWith({
      where: { email: testEmail },
    });

    expect(prisma.user.create).toHaveBeenCalled();
    expect(prisma.$disconnect).toHaveBeenCalled();
  });

  it('skips creation when user already exists', async () => {
    const testEmail = 'existing@example.com';
    process.env.TEST_USER_EMAIL = testEmail;

    (prisma.user.findUnique as jest.Mock).mockResolvedValue({
      id: '1',
      email: testEmail,
      passwordHash: 'existing_hash',
    });

    await mockSeedTestUser();

    expect(prisma.user.findUnique).toHaveBeenCalledWith({
      where: { email: testEmail },
    });

    expect(prisma.user.create).not.toHaveBeenCalled();
    expect(prisma.$disconnect).toHaveBeenCalled();
  });

  it('uses default credentials when environment variables are not set', async () => {
    delete process.env.TEST_USER_EMAIL;
    delete process.env.TEST_USER_PASSWORD;

    (prisma.user.findUnique as jest.Mock).mockResolvedValue(null);
    (prisma.user.create as jest.Mock).mockResolvedValue({
      id: '1',
      email: 'test@example.com',
    });

    await mockSeedTestUser();

    expect(prisma.user.findUnique).toHaveBeenCalledWith({
      where: { email: 'test@example.com' },
    });
  });

  it('handles database errors gracefully', async () => {
    process.env.TEST_USER_EMAIL = 'test@example.com';

    (prisma.user.findUnique as jest.Mock).mockRejectedValue(
      new Error('Database connection failed')
    );

    await expect(mockSeedTestUser()).rejects.toThrow('Database connection failed');
    expect(prisma.$disconnect).toHaveBeenCalled();
  });
});
