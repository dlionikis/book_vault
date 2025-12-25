-- CreateTable
CREATE TABLE "user_downloads" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "book_id" TEXT NOT NULL,
    "downloaded_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "device_id" TEXT,

    CONSTRAINT "user_downloads_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "user_downloads_user_id_downloaded_at_idx" ON "user_downloads"("user_id", "downloaded_at" DESC);

-- CreateIndex
CREATE INDEX "user_downloads_book_id_idx" ON "user_downloads"("book_id");

-- AddForeignKey
ALTER TABLE "user_downloads" ADD CONSTRAINT "user_downloads_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_downloads" ADD CONSTRAINT "user_downloads_book_id_fkey" FOREIGN KEY ("book_id") REFERENCES "books"("id") ON DELETE CASCADE ON UPDATE CASCADE;
