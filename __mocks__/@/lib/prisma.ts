const mockPrisma = {
  book: {
    findMany: jest.fn(),
    findUnique: jest.fn(),
    count: jest.fn(),
    create: jest.fn(),
    update: jest.fn(),
    delete: jest.fn(),
  },
  author: {
    findMany: jest.fn(),
    findUnique: jest.fn(),
    count: jest.fn(),
  },
  narrator: {
    findMany: jest.fn(),
    findUnique: jest.fn(),
    count: jest.fn(),
  },
  series: {
    findMany: jest.fn(),
    findUnique: jest.fn(),
    count: jest.fn(),
  },
  category: {
    findMany: jest.fn(),
    findUnique: jest.fn(),
    findFirst: jest.fn(),
    count: jest.fn(),
    create: jest.fn(),
  },
};

export default mockPrisma;
