ALTER TABLE "dialogue_scenario" ADD COLUMN "published_audio_url" text;--> statement-breakpoint
ALTER TABLE "dialogue_scenario" ADD COLUMN "published_variant_id" uuid;--> statement-breakpoint
ALTER TABLE "dialogue_scenario" ADD COLUMN "published_content_hash" text;--> statement-breakpoint
ALTER TABLE "dialogue_scenario" ADD COLUMN "published_at" timestamp with time zone;
