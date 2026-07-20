CREATE TABLE "curriculum_unit" (
	"id" text PRIMARY KEY NOT NULL,
	"title" text NOT NULL,
	"subtitle" text,
	"jlpt_level" integer DEFAULT 5 NOT NULL,
	"order_index" integer DEFAULT 0 NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "dialogue_collection" ADD COLUMN "unit_id" text;
--> statement-breakpoint
ALTER TABLE "dialogue_collection" ADD CONSTRAINT "dialogue_collection_unit_id_curriculum_unit_id_fk" FOREIGN KEY ("unit_id") REFERENCES "public"."curriculum_unit"("id") ON DELETE set null ON UPDATE no action;
