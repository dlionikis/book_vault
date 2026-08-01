const nextJest = require('next/jest');

const createJestConfig = nextJest({
  // Provide the path to your Next.js app to load next.config.js and .env files in your test environment
  dir: './',
});

// ES modules in node_modules that Jest must transform:
// - jose is ESM-only (jest.setup and lib/jwt.ts load the real thing — no stub)
// - @aws-sdk / @smithy ship `export` statements in their dist-cjs builds since
//   v3.1090 (page tests import the real book-transformer → lib/s3 → @aws-sdk)
// Each entry becomes an alternative inside a negative lookahead, so a match here
// means "do NOT ignore — transform it".
const ESM_ALLOWLIST_PACKAGES = [
  '(.*/)?jose($|/)',
  '@aws-sdk/',
  '@smithy/',
  'react-markdown',
  'remark-.*',
  'micromark.*',
  'mdast-.*',
  'unist-.*',
  'unified',
  'bail',
  'is-plain-obj',
  'trough',
  'vfile',
  'vfile-message',
  'devlop',
];

// Settings shared by every project
const sharedConfig = {
  setupFilesAfterEnv: ['<rootDir>/jest.setup.js'],
  moduleNameMapper: {
    '^@/(.*)$': '<rootDir>/$1',
  },
  testPathIgnorePatterns: ['/node_modules/', '/.next/'],
};

// next/jest emits transformIgnorePatterns that ignore all of node_modules (a file
// is ignored if ANY pattern matches), which makes our ESM deps (jose, @aws-sdk)
// fail to transform. next/jest 16 changed the pattern shape — it's no longer a
// plain '/node_modules/' string but a complex regex with negative lookaheads for
// its own packages (geist, next/dist/...). Rather than match an exact string
// (brittle across Next versions), we inject our allowlist packages into the FIRST
// pattern that targets node_modules, extending its negative lookahead.
function allowEsmPackages(project) {
  const allowlist = ESM_ALLOWLIST_PACKAGES.join('|');
  let injected = false;
  const patterns = (project.transformIgnorePatterns ?? []).map((pattern) => {
    // Match the first "/node_modules/(?!...)" style pattern and widen its lookahead.
    if (!injected && typeof pattern === 'string' && pattern.includes('node_modules')) {
      injected = true;
      // Prepend one more negative lookahead so our packages are never ignored.
      return pattern.replace(/node_modules\//, `node_modules/(?!(${allowlist})/?)`);
    }
    return pattern;
  });
  if (!injected) {
    // Fallback: no node_modules pattern found — add an explicit allowlist entry.
    patterns.unshift(`node_modules/(?!(${allowlist})/?)`);
  }
  return { ...project, transformIgnorePatterns: patterns };
}

/**
 * Three projects:
 * - unit-node:   API route handlers, lib, scripts — node environment, no DB required
 * - unit-dom:    components and pages — jsdom environment, no DB required
 * - integration: tests that need the real Postgres (docker-compose up -d first);
 *                run via `npm run test:integration`, excluded from `npm test`
 *
 * The integration project is gated behind JEST_INTEGRATION=true instead of CLI
 * `--selectProjects` because Jest ignores positional test-path patterns whenever
 * --selectProjects is present — which silently broke `npm test -- <pattern>`
 * (and CI's `npm test -- openapi-contract` ran the entire suite).
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

  const projects = [unitNode, unitDom];
  if (process.env.JEST_INTEGRATION === 'true') {
    projects.push(integration);
  }

  return {
    projects,
    collectCoverageFrom: [
      'app/**/*.{js,jsx,ts,tsx}',
      'components/**/*.{js,jsx,ts,tsx}',
      'lib/**/*.{js,jsx,ts,tsx}',
      'scripts/**/*.{js,jsx,ts,tsx}',
      '!**/*.d.ts',
      '!**/node_modules/**',
      '!**/.next/**',
    ],
    // Ratchet, not target: pinned at the measured floor (rounded down) so
    // coverage can only regress deliberately. Raise as coverage grows.
    // Measured July 13, 2026 on the post-#79 unit tree (unit-node + unit-dom):
    // 37.21% stmts / 36.52% branch / 38.0% funcs / 37.55% lines.
    coverageThreshold: {
      global: {
        statements: 37,
        branches: 36,
        functions: 38,
        lines: 37,
      },
    },
  };
};
