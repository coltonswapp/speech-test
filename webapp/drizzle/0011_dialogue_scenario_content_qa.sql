-- Learner-client content QA (dialogue + quiz looked over). Scenario-scoped.
-- Distinct from Studio take review (tts_variant tokenSync.reviewedAt / flags).
CREATE TABLE "dialogue_scenario_content_qa" (
	"scenario_id" text PRIMARY KEY NOT NULL,
	"dialogue_reviewed_at" timestamp with time zone,
	"quiz_reviewed_at" timestamp with time zone,
	"review_note" text,
	"reviewed_by" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "dialogue_scenario_content_qa" ADD CONSTRAINT "dialogue_scenario_content_qa_scenario_id_dialogue_scenario_id_fk" FOREIGN KEY ("scenario_id") REFERENCES "public"."dialogue_scenario"("id") ON DELETE cascade ON UPDATE no action;
