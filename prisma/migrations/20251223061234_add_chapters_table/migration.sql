-- CreateTable
CREATE TABLE "chapters" (
    "id" TEXT NOT NULL,
    "book_id" TEXT NOT NULL,
    "chapter_number" INTEGER NOT NULL,
    "title" TEXT NOT NULL,
    "start_time" DOUBLE PRECISION NOT NULL,
    "end_time" DOUBLE PRECISION NOT NULL,
    "duration" DOUBLE PRECISION NOT NULL,

    CONSTRAINT "chapters_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "chapters_book_id_idx" ON "chapters"("book_id");

-- CreateIndex
CREATE UNIQUE INDEX "chapters_book_id_chapter_number_key" ON "chapters"("book_id", "chapter_number");

-- AddForeignKey
ALTER TABLE "chapters" ADD CONSTRAINT "chapters_book_id_fkey" FOREIGN KEY ("book_id") REFERENCES "books"("id") ON DELETE CASCADE ON UPDATE CASCADE;
