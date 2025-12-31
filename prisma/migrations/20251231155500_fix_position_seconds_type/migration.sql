-- AlterTable: Change position_seconds from INTEGER to DOUBLE PRECISION (Float)
-- This fixes the schema drift between Prisma schema (Float) and the database (INTEGER)
ALTER TABLE "user_progress" ALTER COLUMN "position_seconds" TYPE DOUBLE PRECISION USING "position_seconds"::DOUBLE PRECISION;
