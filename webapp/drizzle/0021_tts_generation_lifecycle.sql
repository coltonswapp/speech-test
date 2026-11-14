-- Lifecycle for Generate clips: pending reservation, expiry, cleanup index.
-- Apply after 0020_tts_generation.sql. Additive; does not touch other tables.
ALTER TABLE "tts_generation" ADD COLUMN "expires_at" timestamp with time zone;
--> statement-breakpoint
ALTER TABLE "tts_generation" ADD COLUMN "status" text DEFAULT 'ready' NOT NULL;
--> statement-breakpoint
ALTER TABLE "tts_generation" ADD COLUMN "error" text;
--> statement-breakpoint
UPDATE "tts_generation"
SET "expires_at" = "created_at" + interval '24 hours'
WHERE "saved_at" IS NULL AND "expires_at" IS NULL;
--> statement-breakpoint
CREATE INDEX "tts_generation_cleanup_idx" ON "tts_generation" ("expires_at") WHERE "saved_at" IS NULL;
