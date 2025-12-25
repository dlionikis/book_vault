// Mock implementation of jose package to avoid ESM import issues in Jest
module.exports = {
  SignJWT: jest.fn().mockImplementation(() => ({
    setProtectedHeader: jest.fn().mockReturnThis(),
    setExpirationTime: jest.fn().mockReturnThis(),
    setIssuedAt: jest.fn().mockReturnThis(),
    sign: jest.fn().mockResolvedValue('mocked-jwt-token'),
  })),
  jwtVerify: jest.fn().mockResolvedValue({
    payload: { userId: 'test-user-id', email: 'test@example.com' },
  }),
  // Add other jose exports that might be used by next-auth
  compactDecrypt: jest.fn(),
  CompactEncrypt: jest.fn(),
  generateKeyPair: jest.fn(),
  exportJWK: jest.fn(),
  importJWK: jest.fn(),
};
