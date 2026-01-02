-- AlterTable: Change sequence column from TEXT to INTEGER
ALTER TABLE "book_series" ALTER COLUMN "sequence" TYPE INTEGER USING (
  CASE 
    WHEN "sequence" ~ '^\d+$' THEN "sequence"::INTEGER
    ELSE NULL
  END
);
