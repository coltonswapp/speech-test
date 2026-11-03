-- Textbook-style 1–2 sentence learner definition for a teaching pattern.
-- Optional; omitted from public/iOS export when empty. Distinct from
-- gloss (shortMeaning / HOW TO USE) and notes (formNote).
ALTER TABLE "teaching_pattern" ADD COLUMN "description" text;
