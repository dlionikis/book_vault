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
      const username = process.env.TEST_USER_USERNAME || 'testuser';
      const password = process.env.TEST_USER_PASSWORD || 'password123';

      try {
        const existingUser = await prisma.user.findUnique({
          where: { username },
        });

        if (existingUser) {
          return;
        }

        const passwordHash = await bcrypt.hash(password, 12);

        await prisma.user.create({
          data: {
            username,
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
    const testUsername = 'newuser';

    process.env.TEST_USER_USERNAME = testUsername;
    process.env.TEST_USER_PASSWORD = 'testpass123';

    (prisma.user.findUnique as jest.Mock).mockResolvedValue(null);
    (prisma.user.create as jest.Mock).mockResolvedValue({
      id: '1',
      username: testUsername,
      createdAt: new Date(),
    });

    await mockSeedTestUser();

    expect(prisma.user.findUnique).toHaveBeenCalledWith({
      where: { username: testUsername },
    });

    expect(prisma.user.create).toHaveBeenCalled();
    expect(prisma.$disconnect).toHaveBeenCalled();
  });

  it('skips creation when user already exists', async () => {
    const testUsername = 'existinguser';
    process.env.TEST_USER_USERNAME = testUsername;

    (prisma.user.findUnique as jest.Mock).mockResolvedValue({
      id: '1',
      username: testUsername,
      passwordHash: 'existing_hash',
    });

    await mockSeedTestUser();

    expect(prisma.user.findUnique).toHaveBeenCalledWith({
      where: { username: testUsername },
    });

    expect(prisma.user.create).not.toHaveBeenCalled();
    expect(prisma.$disconnect).toHaveBeenCalled();
  });

  it('uses default credentials when environment variables are not set', async () => {
    delete process.env.TEST_USER_USERNAME;
    delete process.env.TEST_USER_PASSWORD;

    (prisma.user.findUnique as jest.Mock).mockResolvedValue(null);
    (prisma.user.create as jest.Mock).mockResolvedValue({
      id: '1',
      username: 'testuser',
    });

    await mockSeedTestUser();

    expect(prisma.user.findUnique).toHaveBeenCalledWith({
      where: { username: 'testuser' },
    });
  });

  it('handles database errors gracefully', async () => {
    process.env.TEST_USER_USERNAME = 'testuser';

    (prisma.user.findUnique as jest.Mock).mockRejectedValue(
      new Error('Database connection failed')
    );

    await expect(mockSeedTestUser()).rejects.toThrow('Database connection failed');
    expect(prisma.$disconnect).toHaveBeenCalled();
  });
});
