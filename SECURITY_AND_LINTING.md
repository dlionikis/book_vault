# Security & Code Quality Tools

This project uses several tools to maintain code quality and security:

## Linting & Formatting

### ESLint

- Configured with Next.js, TypeScript, and security rules
- Run: `npm run lint` to check for issues
- Run: `npm run lint:fix` to auto-fix issues

### Prettier

- Enforces consistent code formatting
- Run: `npm run format` to format all files
- Run: `npm run format:check` to check formatting

### TypeScript

- Type checking enabled
- Run: `npm run type-check` to check types

## Security

### npm audit

- Checks for known vulnerabilities in dependencies
- Run: `npm run security:audit` to check for vulnerabilities
- Run: `npm run security:fix` to attempt automatic fixes

### ESLint Security Plugin

- Detects common security issues in code
- Runs automatically with `npm run lint`

## Git Hooks (Husky)

### Pre-commit Hook

- Automatically runs on every commit
- Runs linting and formatting on staged files
- Prevents commits with linting errors

## Usage

### Before Committing

```bash
npm run validate  # Runs format check, lint, and type-check
```

### Fix All Issues

```bash
npm run format    # Format code
npm run lint:fix  # Fix linting issues
```

### Manual Checks

```bash
npm run lint              # Check for linting issues
npm run format:check      # Check formatting
npm run type-check        # Check TypeScript types
npm run security:audit    # Check for vulnerabilities
```

## Configuration Files

- `.eslintrc.json` - ESLint configuration
- `.prettierrc.json` - Prettier configuration
- `.prettierignore` - Files to ignore in formatting
- `.lintstagedrc.json` - Pre-commit hook configuration
- `.husky/pre-commit` - Git pre-commit hook

## CI/CD Integration

Add these checks to your CI/CD pipeline:

```yaml
- name: Install dependencies
  run: npm ci

- name: Run validation
  run: npm run validate

- name: Security audit
  run: npm run security:audit
```
