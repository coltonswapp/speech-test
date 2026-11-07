-- Optimistic concurrency for Generate reclaim/save/cleanup.
-- Apply after 0021_tts_generation_lifecycle.sql.
ALTER TABLE "tts_generation" ADD COLUMN "revision" integer DEFAULT 0 NOT NULL;
