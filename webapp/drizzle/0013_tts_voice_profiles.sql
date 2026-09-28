CREATE TABLE "tts_voice_profile" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"provider" text NOT NULL,
	"voice" text NOT NULL,
	"gender" text DEFAULT 'unknown' NOT NULL,
	"notes" text DEFAULT '' NOT NULL
);
--> statement-breakpoint
CREATE TABLE "tts_voice_pair_rating" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"provider" text NOT NULL,
	"voice_a" text NOT NULL,
	"voice_b" text NOT NULL,
	"rating" text NOT NULL,
	"notes" text
);
--> statement-breakpoint
CREATE UNIQUE INDEX "tts_voice_profile_provider_voice_idx" ON "tts_voice_profile" USING btree ("provider","voice");
--> statement-breakpoint
CREATE UNIQUE INDEX "tts_voice_pair_rating_provider_voices_idx" ON "tts_voice_pair_rating" USING btree ("provider","voice_a","voice_b");
