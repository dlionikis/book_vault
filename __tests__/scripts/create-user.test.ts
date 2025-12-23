import { generateRandomPassword } from '@/scripts/create-user';

describe('User Creation Script', () => {
  describe('generateRandomPassword', () => {
    it('generates a password of default length (16)', () => {
      const password = generateRandomPassword();
      expect(password).toHaveLength(16);
    });

    it('generates a password of specified length', () => {
      const password = generateRandomPassword(12);
      expect(password).toHaveLength(12);
    });

    it('generates different passwords on each call', () => {
      const password1 = generateRandomPassword();
      const password2 = generateRandomPassword();
      expect(password1).not.toBe(password2);
    });

    it('generates password with valid characters only', () => {
      const password = generateRandomPassword();
      const validChars = /^[A-HJ-NP-Za-hj-np-z2-9!@#\$%^&*]+$/;
      expect(password).toMatch(validChars);
    });

    it('does not include confusing characters (I, l, 1, 0, O)', () => {
      const password = generateRandomPassword(100); // Generate long password for better test coverage
      expect(password).not.toMatch(/[Il1O0]/);
    });

    it('generates password with mixed character types', () => {
      // Generate multiple passwords to ensure we get variety
      const passwords = Array.from({ length: 10 }, () => generateRandomPassword());
      const combined = passwords.join('');

      // Should have uppercase, lowercase, numbers, and special chars across all passwords
      expect(combined).toMatch(/[A-Z]/);
      expect(combined).toMatch(/[a-z]/);
      expect(combined).toMatch(/[0-9]/);
      expect(combined).toMatch(/[!@#$%^&*]/);
    });
  });
});
