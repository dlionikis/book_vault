# Hidden Books

Soft-hide a book so it stops appearing anywhere in the UI, without deleting it.

Driven by one nullable column, `books.hidden_at`. Set it and the book vanishes
from every list surface on **both web and iOS** — the filtering is entirely
server-side, so there is no client release involved. Clear it and the book comes
back exactly as it was.

## Hiding and unhiding

There is no admin UI yet; this is a SQL operation.

```sql
-- Hide a single book
UPDATE books SET hidden_at = now() WHERE asin = 'B0XXXXXXXX';

-- Hide every book in a series
UPDATE books SET hidden_at = now()
 WHERE id IN (SELECT book_id FROM book_series WHERE series_id = '<series-uuid>');

-- Unhide
UPDATE books SET hidden_at = NULL WHERE asin = 'B0XXXXXXXX';

-- What is currently hidden?
SELECT title, hidden_at FROM books WHERE hidden_at IS NOT NULL ORDER BY title;
```

Find a series id by title:

```sql
SELECT id, title FROM series WHERE title ILIKE '%aether%';
```

## What hiding does and does not do

**Hidden from** (all of these filter on `hidden_at IS NULL`):

| Surface                                                         | Endpoint                                              |
| --------------------------------------------------------------- | ----------------------------------------------------- |
| Catalog listing                                                 | `GET /api/books`                                      |
| Search                                                          | `GET /api/search`                                     |
| Search suggestions                                              | `GET /api/search/suggestions`                         |
| Browse authors / series / categories, **and their book counts** | `GET /api/browse/*`                                   |
| Series-grouped shelves (Catalog + Library toggle)               | `GET /api/browse/{catalog,library}-series-view`       |
| Author / narrator / series / category detail pages              | `GET /api/{authors,narrators,series,categories}/{id}` |
| Personal library                                                | `GET /api/library`                                    |
| Custom list book counts                                         | `GET /api/library/lists`                              |
| Bulk "add series to library"                                    | `POST /api/library/series/{seriesId}`                 |

**Still works, deliberately:**

- `GET /api/books/{id}` — the detail page still resolves.
- `GET /api/books/{id}/stream` — playback still works.
- Downloads, including the download history log.

The book is _shelved_, not revoked. Anyone already mid-book keeps their place and
can keep listening; nobody gets a broken player because an admin tidied a shelf.
If you need a book to be genuinely unreachable, that is a different change —
these three endpoints would need the filter too, plus 404 handling checked on
both clients.

## Things to know

- **Already-downloaded copies stay on the device.** iOS caches downloaded
  audiobooks locally. Hiding is a server-side filter and cannot reach them, so a
  user who downloaded the book before it was hidden keeps their offline copy.
- **Entities disappear when their last visible book does.** Hiding every book in
  a series removes the series from Browse rather than leaving an empty "0 books"
  row. Same for authors, narrators, and categories.
- **User data is preserved.** A hidden book stays in `user_list_books`,
  `user_progress`, and `user_downloads` — it is filtered out of responses, not
  deleted. Unhiding restores it to the user's library untouched.
- **Series covers skip hidden books.** A series shelf derives its cover from its
  lowest-sequence _visible_ book, so it will not display the artwork of a book
  nobody can reach.

## Implementation

The filter is one shared constant, `VISIBLE_BOOK_WHERE` in
[`lib/book-transformer.ts`](../lib/book-transformer.ts), spread into each
query's `where`. Adding a new endpoint that lists books means adding it there
too.

Two patterns, depending on whether the query starts from books:

```typescript
// Direct book query
prisma.book.findMany({ where: { ...VISIBLE_BOOK_WHERE } });

// Through a join table (bookSeries, bookAuthor, userListBook, …)
prisma.bookSeries.findMany({ where: { seriesId, book: VISIBLE_BOOK_WHERE } });
```

Watch for two traps:

1. **Where the `where` is `{ OR: [...] }`** (search, suggestions), the filter
   must sit _beside_ `OR`, not inside it. As an `OR` branch it would match
   hidden books instead of excluding them.
2. **`_count` aggregates need their own filter.** An unfiltered `_count` reports
   "12 books" next to a page that lists 11.

Covered by [`__tests__/integration/hidden-books.test.ts`](../__tests__/integration/hidden-books.test.ts),
which runs against a real database.
