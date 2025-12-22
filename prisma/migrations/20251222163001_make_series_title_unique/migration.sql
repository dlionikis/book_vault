/*
  Warnings:

  - A unique constraint covering the columns `[title]` on the table `series` will be added. If there are existing duplicate values, this will fail.

*/
-- CreateIndex
CREATE UNIQUE INDEX "series_title_key" ON "series"("title");
