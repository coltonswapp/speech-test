ALTER TABLE "dialogue_scenario" ADD COLUMN "ambience_layers" jsonb;--> statement-breakpoint
UPDATE "dialogue_scenario"
SET "ambience_layers" = jsonb_build_array(
  jsonb_build_object(
    'id', gen_random_uuid()::text,
    'assetId', "ambience_asset_id",
    'gainDb', coalesce("ambience_gain_db", -22),
    'offsetSeconds', coalesce("ambience_offset_seconds", 0),
    'startSeconds', 0,
    'endSeconds', null
  )
)
WHERE "ambience_asset_id" IS NOT NULL;
