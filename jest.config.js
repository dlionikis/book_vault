const nextJest = require('next/jest');

const createJestConfig = nextJest({
  // Provide the path to your Next.js app to load next.config.js and .env files in your test environment
  dir: './',
});

// ES modules in node_modules that Jest must transform (jose is ESM-only; jest.setup
// and lib/jwt.ts load the real thing — no stub)
const ESM_ALLOWLIST_PATTERN =
  'node_modules/(?!((.*/)?jose($|/)|react-markdown|remark-.*|micromark.*|mdast-.*|unist-.*|unified|bail|is-plain-obj|trough|vfile|vfile-message|devlop))';

// Settings shared by every project
const sharedConfig = {
  setupFilesAfterEnv: ['<rootDir>/jest.setup.js'],
  moduleNameMapper: {
    '^@/(.*)$': '<rootDir>/$1',
  },
  testPathIgnorePatterns: ['/node_modules/', '/.next/'],
};

// next/jest unconditionally prepends '/node_modules/' to transformIgnorePatterns,
// which makes any user-supplied allowlist pattern unreachable (a file is ignored if
// ANY pattern matches). Replace that entry in the resolved config so ESM packages
// like jose actually get transformed.
function allowEsmPackages(project) {
  return {
    ...project,
    transformIgnorePatterns: (project.transformIgnorePatterns ?? []).map((pattern) =>
      pattern === '/node_modules/' ? ESM_ALLOWLIST_PATTERN : pattern
    ),
  };
}

/**
 * Three projects:
 * - unit-node:   API route handlers, lib, scripts — node environment, no DB required
 * - unit-dom:    components and pages — jsdom environment, no DB required
 * - integration: tests that need the real Postgres (docker-compose up -d first);
 *                run via `npm run test:integration`, excluded from `npm test`
 */
module.exports = async () => {
  const unitNode = allowEsmPackages(
    await createJestConfig({
      ...sharedConfig,
      displayName: 'unit-node',
      testEnvironment: 'node',
      testMatch: [
        '<rootDir>/__tests__/api/**/*.[jt]s?(x)',
        '<rootDir>/__tests__/lib/**/*.[jt]s?(x)',
        '<rootDir>/__tests__/scripts/**/*.[jt]s?(x)',
        '<rootDir>/app/**/*.test.[jt]s',
        '<rootDir>/lib/**/*.test.[jt]s',
        '<rootDir>/scripts/**/*.test.[jt]s',
      ],
    })()
  );

  const unitDom = allowEsmPackages(
    await createJestConfig({
      ...sharedConfig,
      displayName: 'unit-dom',
      testEnvironment: 'jest-environment-jsdom',
      testMatch: [
        '<rootDir>/__tests__/components/**/*.[jt]s?(x)',
        '<rootDir>/__tests__/pages/**/*.[jt]s?(x)',
        '<rootDir>/components/**/*.test.[jt]s?(x)',
      ],
    })()
  );

  const integration = allowEsmPackages(
    await createJestConfig({
      ...sharedConfig,
      displayName: 'integration',
      testEnvironment: 'node',
      testMatch: ['<rootDir>/__tests__/integration/**/*.[jt]s?(x)'],
    })()
  );

  return {
    projects: [unitNode, unitDom, integration],
    collectCoverageFrom: [
      'app/**/*.{js,jsx,ts,tsx}',
      'components/**/*.{js,jsx,ts,tsx}',
      'lib/**/*.{js,jsx,ts,tsx}',
      'scripts/**/*.{js,jsx,ts,tsx}',
      '!**/*.d.ts',
      '!**/node_modules/**',
      '!**/.next/**',
    ],
    // Ratchet, not target: set ~3 points below the measured baseline
    // (July 2026: 37% stmts / 35.4% branch / 38.1% funcs / 37.6% lines)
    // so coverage can only regress deliberately. Raise as coverage grows.
    coverageThreshold: {
      global: {
        statements: 34,
        branches: 32,
        functions: 35,
        lines: 34,
      },
    },
  };
};
