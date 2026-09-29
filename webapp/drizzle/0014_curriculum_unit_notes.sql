-- Studio-only curriculum writer notes on the unit (storyboard, characters,
-- background, freeform). Structured jsonb so authors can update one section
-- without wiping others. Never shipped in public/iOS dialogue export.
ALTER TABLE "curriculum_unit" ADD COLUMN "notes" jsonb;
