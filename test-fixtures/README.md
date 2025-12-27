# Test Fixtures

Shared JSON test fixtures for backend and iOS testing.

## Files

- `books-list.json` - Paginated book list (5 books)
- `book-detail.json` - Single book with all relations
- `user-progress.json` - User progress for a book
- `chapters-list.json` - Chapter list for a book
- `search-results.json` - Search results
- `author-books.json` - Author with their books
- `browse-authors.json` - Browse authors list

## Usage

### Backend Tests (TypeScript)

```typescript
import booksListFixture from '@/../test-fixtures/books-list.json';

test('API returns correct structure', () => {
  expect(response.data).toMatchObject(booksListFixture);
});
```

### iOS Tests (Swift)

```swift
let fixture = Bundle.main.url(forResource: "books-list", withExtension: "json")!
let data = try Data(contentsOf: fixture)
let books = try JSONDecoder().decode([Book].self, from: data)
```

## Regenerating Fixtures

```bash
# Get fresh auth token
TOKEN=$(curl -s -X POST http://localhost:3000/api/auth/mobile/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"password123"}' \
  | jq -r .accessToken)

# Fetch and save
curl -H "Authorization: Bearer $TOKEN" \
  "http://localhost:3000/api/books?page=1&limit=5" \
  | jq '.' > books-list.json
```
