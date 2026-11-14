-- One-off Generate workspace. Audio keys live under tts/generate/ only.
CREATE TABLE "tts_generation" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"saved_at" timestamp with time zone,
	"title" text DEFAULT '' NOT NULL,
	"kind" text DEFAULT 'tts' NOT NULL,
	"model" text,
	"request_id" text,
	"content_hash" text,
	"lines" jsonb NOT NULL,
	"line_timings" jsonb,
	"token_sync" jsonb,
	"transcript" text,
	"wav_object_key" text,
	"mp3_object_key" text,
	"sample_rate" real,
	"duration_seconds" real NOT NULL,
	"byte_count" integer
);
--> statement-breakpoint
CREATE UNIQUE INDEX "tts_generation_request_id_idx" ON "tts_generation" ("request_id");
