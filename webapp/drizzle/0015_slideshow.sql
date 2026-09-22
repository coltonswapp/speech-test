CREATE TABLE "slideshow_photo" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"title" text NOT NULL,
	"tags" text[] DEFAULT '{}' NOT NULL,
	"object_key" text NOT NULL,
	"thumb_object_key" text NOT NULL,
	"content_type" text NOT NULL,
	"byte_count" integer NOT NULL,
	"width" integer NOT NULL,
	"height" integer NOT NULL
);
--> statement-breakpoint
CREATE TABLE "slideshow_deck" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"kind" text NOT NULL,
	"status" text DEFAULT 'draft' NOT NULL,
	"used_subject" text NOT NULL,
	"recipe_id" text DEFAULT 'studio-light' NOT NULL,
	"export_size" text DEFAULT 'story' NOT NULL,
	"photo_set" text DEFAULT 'all' NOT NULL,
	"photo_seed" integer DEFAULT 0 NOT NULL,
	"payload" jsonb DEFAULT '{}'::jsonb NOT NULL
);
