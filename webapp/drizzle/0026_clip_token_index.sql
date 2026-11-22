CREATE TABLE "clip_token_index" (
	"clip_id" text NOT NULL,
	"video_id" text NOT NULL,
	"line_index" integer NOT NULL,
	"line_text" text NOT NULL,
	"token_index" integer NOT NULL,
	"surface" text NOT NULL,
	"reading" text,
	"start_sec" real NOT NULL,
	"end_sec" real NOT NULL,
	"clip_start_sec" real NOT NULL,
	"clip_end_sec" real NOT NULL,
	"listed" boolean NOT NULL,
	"in_feed" boolean NOT NULL,
	"jlpt_level" integer,
	"lemma" text,
	"grammar_tags" text[],
	CONSTRAINT "clip_token_index_pk" PRIMARY KEY("clip_id","line_index","token_index")
);
--> statement-breakpoint
CREATE INDEX "clip_token_index_surface_idx" ON "clip_token_index" ("surface");
--> statement-breakpoint
CREATE INDEX "clip_token_index_reading_idx" ON "clip_token_index" ("reading");
--> statement-breakpoint
CREATE INDEX "clip_token_index_listed_idx" ON "clip_token_index" ("listed","in_feed","jlpt_level");
--> statement-breakpoint
CREATE INDEX "clip_token_index_clip_idx" ON "clip_token_index" ("clip_id");
