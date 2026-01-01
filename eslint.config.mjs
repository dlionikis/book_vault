import { dirname } from 'path';
import { fileURLToPath } from 'url';
import { FlatCompat } from '@eslint/eslintrc';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const compat = new FlatCompat({
  baseDirectory: __dirname,
});

const eslintConfig = [
  {
    ignores: [
      '.next/**',
      'node_modules/**',
      'out/**',
      'storybook-static/**',
      'coverage/**',
      'lib/api-types.ts',
      'ios/**',
    ],
  },
  ...compat.extends('next/core-web-vitals'),
  ...compat.extends('plugin:storybook/recommended'),
  {
    rules: {
      'no-console': ['warn', { allow: ['warn', 'error'] }],
    },
  },
  // Allow console.log in test files, scripts, and dev server
  {
    files: ['**/__tests__/**', '**/*.test.ts', '**/*.test.tsx', 'scripts/**', 'server.js'],
    rules: {
      'no-console': 'off',
    },
  },
];

export default eslintConfig;
