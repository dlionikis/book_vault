-- AlterTable
ALTER TABLE "books" ADD COLUMN     "hidden_at" TIMESTAMP(3);

-- CreateIndex
CREATE INDEX "books_hidden_at_idx" ON "books"("hidden_at");
