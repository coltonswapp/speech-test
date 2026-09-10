ALTER TABLE "dialogue_collection" ADD COLUMN "is_active" boolean DEFAULT false NOT NULL;
--> statement-breakpoint
UPDATE "dialogue_collection" SET "is_active" = true;
