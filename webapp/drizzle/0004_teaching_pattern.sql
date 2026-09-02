CREATE TABLE IF NOT EXISTS "teaching_pattern" (
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
