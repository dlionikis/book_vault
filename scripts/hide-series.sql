-- Hide (or unhide) every book in a series.
--
-- Wrapped in a transaction that prints the affected rows before committing, so
-- you can confirm the count matches what you expect before it lands. See
-- docs/hidden-books.md.
--
-- Usage:
--   psql "$DATABASE_URL" -v series_title="Aether's Revival" -f scripts/hide-series.sql
--
-- To unhide, change `now()` to NULL in the UPDATE below.

\set ON_ERROR_STOP on

BEGIN;

-- 1. Resolve the series and show what is about to change.
SELECT s.id AS series_id, s.title AS series_title, count(bs.book_id) AS total_books
  FROM series s
  LEFT JOIN book_series bs ON bs.series_id = s.id
 WHERE s.title = :'series_title'
 GROUP BY s.id, s.title;

SELECT b.title, bs.sequence, (b.hidden_at IS NOT NULL) AS already_hidden
  FROM books b
  JOIN book_series bs ON bs.book_id = b.id
  JOIN series s ON s.id = bs.series_id
 WHERE s.title = :'series_title'
 ORDER BY bs.sequence NULLS LAST, b.title;

-- 2. Apply. Change now() -> NULL to unhide.
UPDATE books
   SET hidden_at = now()
 WHERE id IN (
   SELECT bs.book_id
     FROM book_series bs
     JOIN series s ON s.id = bs.series_id
    WHERE s.title = :'series_title'
 );

-- 3. Confirm the end state before committing.
SELECT count(*) FILTER (WHERE b.hidden_at IS NOT NULL) AS now_hidden,
       count(*)                                        AS books_in_series
  FROM books b
  JOIN book_series bs ON bs.book_id = b.id
  JOIN series s ON s.id = bs.series_id
 WHERE s.title = :'series_title';

-- Review the output above. If the counts are wrong, ROLLBACK instead.
COMMIT;
