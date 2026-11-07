-- Durable ledger of superseded Generate object keys. Apply after 0022.
ALTER TABLE "tts_generation" ADD COLUMN "obsolete_object_keys" jsonb DEFAULT '[]'::jsonb NOT NULL;
