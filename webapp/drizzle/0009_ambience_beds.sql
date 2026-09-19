CREATE TABLE "ambience_asset" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"title" text NOT NULL,
	"kind" text NOT NULL,
	"audio_object_key" text NOT NULL,
	"content_type" text NOT NULL,
	"duration_seconds" real NOT NULL,
	"sample_rate" real,
	"byte_count" integer NOT NULL
);
--> statement-breakpoint
ALTER TABLE "dialogue_scenario" ADD COLUMN "ambience_asset_id" uuid;--> statement-breakpoint
ALTER TABLE "dialogue_scenario" ADD COLUMN "ambience_gain_db" real;--> statement-breakpoint
ALTER TABLE "dialogue_scenario" ADD COLUMN "ambience_offset_seconds" real;--> statement-breakpoint
ALTER TABLE "dialogue_scenario" ADD COLUMN "published_ambience_hash" text;--> statement-breakpoint
ALTER TABLE "dialogue_scenario" ADD CONSTRAINT "dialogue_scenario_ambience_asset_id_ambience_asset_id_fk" FOREIGN KEY ("ambience_asset_id") REFERENCES "public"."ambience_asset"("id") ON DELETE set null ON UPDATE no action;
