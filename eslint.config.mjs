import nextCoreWebVitals from 'eslint-config-next/core-web-vitals';
import storybook from 'eslint-plugin-storybook';

// eslint-config-next 16 and eslint-plugin-storybook both ship native flat configs,
// so we import them directly instead of the old FlatCompat/.eslintrc shim (which
// broke on next 16's config shape).
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
  ...nextCoreWebVitals,
  ...storybook.configs['flat/recommended'],
  {
    rules: {
      'no-console': ['warn', { allow: ['warn', 'error'] }],
    },
  },
  // eslint-config-next 16 promoted react-hooks/set-state-in-effect to an error.
  // It correctly catches cascading-render bugs, so we keep it as an error
  // everywhere EXCEPT the handful of files using known-good SSR patterns it can't
  // distinguish: hydration `mounted` guards (setState(true) in a []-effect) and a
  // one-shot initial fetch. Reviewed individually during the Next 16 migration.
  {
    files: [
      'components/ThemeToggle.tsx',
      'components/SearchBar.tsx',
      'app/settings/page.tsx',
      'app/admin/dashboard/tabs/EcsHealthTab.tsx',
    ],
    rules: {
      'react-hooks/set-state-in-effect': 'off',
    },
  },
  // Allow console.log in test files, scripts, e2e harness, and dev server
  {
    files: [
      '**/__tests__/**',
      '**/*.test.ts',
      '**/*.test.tsx',
      '**/*.spec.ts',
      'scripts/**',
      'e2e/**',
      'server.js',
    ],
    rules: {
      'no-console': 'off',
    },
  },
];

export default eslintConfig;
