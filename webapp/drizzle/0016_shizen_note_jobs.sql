CREATE TABLE "shizen_note_job" (
	"id" text PRIMARY KEY NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"source" text NOT NULL,
	"source_id" text NOT NULL,
	"title" text,
	"note" text NOT NULL,
	"agent" text DEFAULT 'shohei' NOT NULL,
	"url" text NOT NULL,
	"note_created_at" timestamp with time zone NOT NULL,
	"status" text DEFAULT 'queued' NOT NULL,
	"error" text
);
