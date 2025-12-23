/**
 * @jest-environment node
 */

import { PrismaClient } from '@prisma/client';
import bcrypt from 'bcryptjs';

// Create a shared mock instance
const mockPrisma = {
  user: {
    findUnique: jest.fn(),
    create: jest.fn(),
  },
  $disconnect: jest.fn(),
};

// Mock Prisma
jest.mock('@prisma/client', () => {
  return {
    PrismaClient: jest.fn(() => mockPrisma),
  };
});

// Mock bcrypt
jest.mock('bcryptjs', () => ({
  hash: jest.fn(),
}));

describe('Test User Seeding Script', () => {
  let originalEnv: NodeJS.ProcessEnv;

  beforeAll(() => {
    // Mock console.log to avoid cluttering test output
    jest.spyOn(console, 'log').mockImplementation();
    jest.spyOn(console, 'error').mockImplementation();
  });

  beforeEach(() => {
    // Reset modules before each test so env vars are read fresh
    jest.resetModules();
    jest.clearAllMocks();

    originalEnv = { ...process.env };
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

    mockPrisma.user.findUnique.mockResolvedValue(null);
    mockPrisma.user.create.mockResolvedValue({
      id: '1',
      email: testEmail,
      createdAt: new Date(),
    });

    const { seedTestUser } = await import('../../scripts/seed-test-user');
    await seedTestUser();

    expect(mockPrisma.user.findUnique).toHaveBeenCalledWith({
      where: { email: testEmail },
    });

    expect(mockPrisma.user.create).toHaveBeenCalled();
    expect(mockPrisma.$disconnect).toHaveBeenCalled();
  });

  it('skips creation when user already exists', async () => {
    const testEmail = 'existing@example.com';
    process.env.TEST_USER_EMAIL = testEmail;

    mockPrisma.user.findUnique.mockResolvedValue({
      id: '1',
      email: testEmail,
      passwordHash: 'existing_hash',
    });

    const { seedTestUser } = await import('../../scripts/seed-test-user');
    await seedTestUser();

    expect(mockPrisma.user.findUnique).toHaveBeenCalledWith({
      where: { email: testEmail },
    });

    expect(mockPrisma.user.create).not.toHaveBeenCalled();
    expect(mockPrisma.$disconnect).toHaveBeenCalled();
  });

  it('uses default credentials when environment variables are not set', async () => {
    delete process.env.TEST_USER_EMAIL;
    delete process.env.TEST_USER_PASSWORD;

    mockPrisma.user.findUnique.mockResolvedValue(null);
    mockPrisma.user.create.mockResolvedValue({
      id: '1',
      email: 'test@example.com',
    });

    const { seedTestUser } = await import('../../scripts/seed-test-user');
    await seedTestUser();

    expect(mockPrisma.user.findUnique).toHaveBeenCalledWith({
      where: { email: 'test@example.com' },
    });
  });

  it('handles database errors gracefully', async () => {
    process.env.TEST_USER_EMAIL = 'test@example.com';

    mockPrisma.user.findUnique.mockRejectedValue(new Error('Database connection failed'));

    const { seedTestUser } = await import('../../scripts/seed-test-user');
    await expect(seedTestUser()).rejects.toThrow('Database connection failed');
    expect(mockPrisma.$disconnect).toHaveBeenCalled();
  });
});
