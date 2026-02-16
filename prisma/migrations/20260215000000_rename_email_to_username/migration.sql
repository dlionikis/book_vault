-- RenameColumn
ALTER TABLE "users" RENAME COLUMN "email" TO "username";

-- RenameIndex
ALTER INDEX "users_email_key" RENAME TO "users_username_key";
