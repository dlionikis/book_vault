// Mock implementation of next-auth to avoid ESM import issues with jose
module.exports = {
  getServerSession: jest.fn(),
  unstable_getServerSession: jest.fn(),
};
