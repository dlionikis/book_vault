# Contributing to Book Vault

## AI-First Development

This project is developed with significant AI assistance. When contributing, please:

1. **Read Context First**: Review the `.ai/` directory files to understand the project
2. **Update Documentation**: Keep docs in sync with code changes
3. **Follow Architecture**: Stick to the patterns in `ARCHITECTURE.md`
4. **Commit Often**: Small, focused commits with clear messages

## Development Setup

1. Clone the repository
2. Copy `.env.example` to `.env.local` and configure
3. Install dependencies: `npm install`
4. Start database: `docker-compose up -d`
5. Run migrations: `npm run db:migrate`
6. Start dev server: `npm run dev`

## Code Style

- TypeScript for all code
- ESLint + Prettier for formatting
- Run `npm run lint` before committing
- Run `npm test` before committing

## Commit Message Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types**: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`

**Examples**:
- `feat(api): add book search endpoint`
- `fix(player): resolve audio seeking issue`
- `docs(readme): update setup instructions`

## Pull Request Process

1. Create a feature branch
2. Make your changes
3. Update relevant documentation
4. Ensure tests pass
5. Submit PR with clear description

## Questions?

This is a personal project, but feedback and suggestions are welcome!
