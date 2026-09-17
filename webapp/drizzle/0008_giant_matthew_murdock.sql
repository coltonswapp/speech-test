CREATE TABLE "curriculum_unit" (
	"id" text PRIMARY KEY NOT NULL,
	"title" text NOT NULL,
	"subtitle" text,
	"jlpt_level" integer DEFAULT 5 NOT NULL,
	"order_index" integer DEFAULT 0 NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "teaching_pattern" (
	"id" text PRIMARY KEY NOT NULL,
	"form" text NOT NULL,
	"gloss" text NOT NULL,
	"jlpt_band" integer DEFAULT 5 NOT NULL,
	"category" text NOT NULL,
	"status" text DEFAULT 'seed' NOT NULL,
	"notes" text,
	"order_index" integer DEFAULT 0 NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "dialogue_collection" ADD COLUMN "unit_id" text;--> statement-breakpoint
ALTER TABLE "dialogue_collection" ADD COLUMN "premise" text;--> statement-breakpoint
ALTER TABLE "dialogue_collection" ADD COLUMN "thumbnail_url" text;--> statement-breakpoint
ALTER TABLE "dialogue_collection" ADD COLUMN "thumbnail_small_url" text;--> statement-breakpoint
ALTER TABLE "dialogue_collection" ADD COLUMN "is_active" boolean DEFAULT false NOT NULL;--> statement-breakpoint
ALTER TABLE "dialogue_scenario" ADD COLUMN "published_audio_url" text;--> statement-breakpoint
ALTER TABLE "dialogue_scenario" ADD COLUMN "published_variant_id" uuid;--> statement-breakpoint
ALTER TABLE "dialogue_scenario" ADD COLUMN "published_content_hash" text;--> statement-breakpoint
ALTER TABLE "dialogue_scenario" ADD COLUMN "published_at" timestamp with time zone;--> statement-breakpoint
ALTER TABLE "dialogue_scenario" ADD COLUMN "thumbnail_url" text;--> statement-breakpoint
ALTER TABLE "dialogue_scenario" ADD COLUMN "thumbnail_small_url" text;--> statement-breakpoint
ALTER TABLE "dialogue_scenario" ADD COLUMN "token_sync" jsonb;--> statement-breakpoint
ALTER TABLE "tts_variant" ADD COLUMN "token_sync" jsonb;--> statement-breakpoint
ALTER TABLE "dialogue_collection" ADD CONSTRAINT "dialogue_collection_unit_id_curriculum_unit_id_fk" FOREIGN KEY ("unit_id") REFERENCES "public"."curriculum_unit"("id") ON DELETE set null ON UPDATE no action;