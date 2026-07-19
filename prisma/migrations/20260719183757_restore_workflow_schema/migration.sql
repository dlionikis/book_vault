-- AlterTable
ALTER TABLE "books" ADD COLUMN     "audio_availability" TEXT NOT NULL DEFAULT 'AVAILABLE',
ADD COLUMN     "availability_checked_at" TIMESTAMP(3);

-- CreateTable
CREATE TABLE "media_restore_requests" (
    "id" TEXT NOT NULL,
    "book_id" TEXT NOT NULL,
    "s3_key" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'in_progress',
    "restore_tier" TEXT NOT NULL DEFAULT 'Standard',
    "requested_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "completed_at" TIMESTAMP(3),
    "last_checked_at" TIMESTAMP(3),
    "error_message" TEXT,
    "requested_by_user_id" TEXT,

    CONSTRAINT "media_restore_requests_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "user_device_tokens" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "device_token" TEXT NOT NULL,
    "platform" TEXT NOT NULL DEFAULT 'ios',
    "sns_endpoint_arn" TEXT,
    "is_active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "user_device_tokens_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "media_restore_requests_status_last_checked_at_idx" ON "media_restore_requests"("status", "last_checked_at");

-- CreateIndex
CREATE INDEX "media_restore_requests_book_id_idx" ON "media_restore_requests"("book_id");

-- CreateIndex
CREATE INDEX "media_restore_requests_requested_by_user_id_idx" ON "media_restore_requests"("requested_by_user_id");

-- CreateIndex
CREATE INDEX "user_device_tokens_user_id_idx" ON "user_device_tokens"("user_id");

-- CreateIndex
CREATE UNIQUE INDEX "user_device_tokens_user_id_device_token_key" ON "user_device_tokens"("user_id", "device_token");

-- AddForeignKey
ALTER TABLE "media_restore_requests" ADD CONSTRAINT "media_restore_requests_book_id_fkey" FOREIGN KEY ("book_id") REFERENCES "books"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "media_restore_requests" ADD CONSTRAINT "media_restore_requests_requested_by_user_id_fkey" FOREIGN KEY ("requested_by_user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_device_tokens" ADD CONSTRAINT "user_device_tokens_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
