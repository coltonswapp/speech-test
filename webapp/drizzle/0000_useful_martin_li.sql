CREATE TABLE "app_settings" (
	"key" text PRIMARY KEY NOT NULL,
	"value" jsonb NOT NULL
);
--> statement-breakpoint
CREATE TABLE "dialogue_collection" (
	"id" text PRIMARY KEY NOT NULL,
	"title" text NOT NULL,
	"subtitle" text,
	"scene_image" text,
	"order_index" integer DEFAULT 0 NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "dialogue_scenario" (
	"id" text PRIMARY KEY NOT NULL,
	"collection_id" text NOT NULL,
	"order_index" integer NOT NULL,
	"menu_title" text NOT NULL,
	"menu_subtitle" text,
	"japanese" text NOT NULL,
	"romaji" text NOT NULL,
	"english" text NOT NULL,
	"target_substring" text,
	"audio_key" text,
	"grammar_point_ids" text[] DEFAULT '{}' NOT NULL,
	"setting" text,
	"lines" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"highlights" jsonb,
	"quiz" jsonb,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "grammar_checkpoint" (
	"id" text PRIMARY KEY NOT NULL,
	"order_index" integer NOT NULL,
	"title" text NOT NULL,
	"subtitle" text,
	"point_ids" text[] DEFAULT '{}' NOT NULL
);
--> statement-breakpoint
CREATE TABLE "grammar_curriculum_bundle_snapshot" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"jlpt_level" integer NOT NULL,
	"object_key" text NOT NULL
);
--> statement-breakpoint
CREATE TABLE "grammar_point" (
	"id" text PRIMARY KEY NOT NULL,
	"order_index" integer NOT NULL,
	"title" text NOT NULL,
	"headline_english" text NOT NULL,
	"blurb" text,
	"forms" text[] DEFAULT '{}' NOT NULL,
	"formation" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"formation_examples" text[],
	"usage" jsonb,
	"usage_ladders" jsonb,
	"related_point_ids" text[] DEFAULT '{}' NOT NULL,
	"examples" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"drills" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"pattern" text,
	"reading" text,
	"short_definition" text,
	"structure" text,
	"register" text,
	"contrast_drills" jsonb,
	"status" text DEFAULT 'draft' NOT NULL,
	"review_notes" text,
	"provenance" jsonb,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "recent_point_view" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"point_id" text NOT NULL,
	"viewed_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "tts_dialogue_group" (
	"id" text PRIMARY KEY NOT NULL,
	"title" text NOT NULL
);
--> statement-breakpoint
CREATE TABLE "tts_dialogue_line" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"project_id" uuid NOT NULL,
	"speaker" text NOT NULL,
	"text" text NOT NULL,
	"order_index" integer NOT NULL
);
--> statement-breakpoint
CREATE TABLE "tts_export" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"variant_id" uuid NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"format" text NOT NULL,
	"object_key" text NOT NULL,
	"byte_count" integer NOT NULL,
	"duration_seconds" real NOT NULL,
	"source_byte_count" integer NOT NULL
);
--> statement-breakpoint
CREATE TABLE "tts_project" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"prompt_text" text DEFAULT '' NOT NULL,
	"instructions" text,
	"provider" text NOT NULL,
	"voice" text NOT NULL,
	"model" text NOT NULL,
	"selected_variant_id" uuid,
	"composition_mode" text DEFAULT 'narration' NOT NULL,
	"speaker1_voice" text,
	"speaker2_voice" text,
	"speaker1_name" text,
	"speaker2_name" text,
	"track_name" text,
	"group_id" text,
	"source_scenario_id" text,
	"group_order_index" integer
);
--> statement-breakpoint
CREATE TABLE "tts_variant" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"project_id" uuid NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"audio_object_key" text NOT NULL,
	"sample_rate" real NOT NULL,
	"audio_byte_count" integer NOT NULL,
	"trim_sample_lower" integer,
	"trim_sample_upper" integer,
	"dialogue_line_switch_samples" integer[],
	"notes" text,
	"rating" integer,
	"is_selected" boolean DEFAULT false NOT NULL,
	"voice" text NOT NULL,
	"provider" text NOT NULL,
	"content_hash" text
);
--> statement-breakpoint
CREATE TABLE "tts_variant_sentence" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"variant_id" uuid NOT NULL,
	"index" integer NOT NULL,
	"text" text NOT NULL,
	"sample_lower" integer NOT NULL,
	"sample_upper" integer NOT NULL,
	"peaks" real[]
);
--> statement-breakpoint
CREATE TABLE "voice_preview" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"provider" text NOT NULL,
	"voice" text NOT NULL,
	"audio_object_key" text NOT NULL,
	"sample_rate" real NOT NULL
);
--> statement-breakpoint
ALTER TABLE "dialogue_scenario" ADD CONSTRAINT "dialogue_scenario_collection_id_dialogue_collection_id_fk" FOREIGN KEY ("collection_id") REFERENCES "public"."dialogue_collection"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "recent_point_view" ADD CONSTRAINT "recent_point_view_point_id_grammar_point_id_fk" FOREIGN KEY ("point_id") REFERENCES "public"."grammar_point"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "tts_dialogue_line" ADD CONSTRAINT "tts_dialogue_line_project_id_tts_project_id_fk" FOREIGN KEY ("project_id") REFERENCES "public"."tts_project"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "tts_export" ADD CONSTRAINT "tts_export_variant_id_tts_variant_id_fk" FOREIGN KEY ("variant_id") REFERENCES "public"."tts_variant"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "tts_project" ADD CONSTRAINT "tts_project_group_id_tts_dialogue_group_id_fk" FOREIGN KEY ("group_id") REFERENCES "public"."tts_dialogue_group"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "tts_project" ADD CONSTRAINT "tts_project_source_scenario_id_dialogue_scenario_id_fk" FOREIGN KEY ("source_scenario_id") REFERENCES "public"."dialogue_scenario"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "tts_variant" ADD CONSTRAINT "tts_variant_project_id_tts_project_id_fk" FOREIGN KEY ("project_id") REFERENCES "public"."tts_project"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "tts_variant_sentence" ADD CONSTRAINT "tts_variant_sentence_variant_id_tts_variant_id_fk" FOREIGN KEY ("variant_id") REFERENCES "public"."tts_variant"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "tts_project_source_scenario_idx" ON "tts_project" USING btree ("source_scenario_id");--> statement-breakpoint
CREATE UNIQUE INDEX "voice_preview_provider_voice_idx" ON "voice_preview" USING btree ("provider","voice");