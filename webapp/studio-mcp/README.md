# Shizen Content Studio MCP

Local stdio MCP server wrapping Content Studio REST APIs. No auth.

Studio should already be running. STUDIO_BASE_URL defaults to http://localhost:3000.

## Tools

- list_curriculum: units, collections, scenario slugs/titles, unpublished flag
- get_scenario: speakers, spoken rows (optional `delivery` Gemini TTS audio tags), and stage/ト書き rows as { type, text, visibility, role: "stage" }; B-line lengths, grammar tags, unpublished flag; `sourceScript` (original Claude markdown brief, Studio-only); flags long B lines and a missing opener ト書き
- patch_scenario: patch lines and metadata via existing scenario PATCH. Lines are a flat object: spoken needs speaker+japanese (optional `delivery` for Gemini audio tags, e.g. `[softly]`); stage needs type "stage", text, visibility; optional `sourceScript` (Claude `.md` brief, Studio-only; null clears)
- get_cast_voices: collection castVoices (Kaito to Orus, etc.)
- set_cast_voices: replace collection castVoices
- generate_take: ensure scenario audio project, then kick a TTS take
- auto_stamp_take: forced-align a take (token karaoke + line marks); optional force to overwrite human stamps
- set_lesson_thumbnail: upload lesson (collection) card thumbnail (JPEG/PNG/WebP/GIF ≤5MB)
- set_scene_thumbnail: upload scene (scenario) thumbnail override; falls back to lesson when cleared
- clear_lesson_thumbnail: remove lesson thumbnail
- clear_scene_thumbnail: remove scene override (lesson thumbnail applies again)

Does not expose waveform, trim, or export tools.

## Thumbnails (Hana)

Lesson = collection card art. Scene overrides the lesson for that scenario only; clearing the scene restores the lesson fallback.

Provide **exactly one** image source:

- **imageUrl** (preferred): HTTP(S) URL the MCP can fetch. Use this when you already have a public or Studio URL.
- **imageBase64**: raw base64 bytes, or a `data:image/...;base64,...` data URL. Pass **contentType** (`image/jpeg` | `image/png` | `image/webp` | `image/gif`) unless the value is a data URL or **filename** ends in `.jpg`/`.jpeg`/`.png`/`.webp`/`.gif`.

Optional **filename** sets the multipart file name and can help MIME inference. Requires published R2 on Studio (`R2_PUBLISHED_*`).

## How to run

Install this folder dependencies, then run the TypeScript entry src/index.ts over stdio.

## AddMcpServer

Use the local TypeScript runner against src/index.ts
Set STUDIO_BASE_URL if Studio is not at http://localhost:3000

## APIs each tool hits

- list_curriculum: GET /api/content/units and GET /api/content/dialogues
- get_scenario: GET /api/content/dialogues/:collectionId/scenarios/:slug
- patch_scenario: PATCH /api/content/dialogues/:collectionId/scenarios/:slug
- get_cast_voices: GET /api/content/dialogues/:collectionId
- set_cast_voices: PATCH /api/content/dialogues/:collectionId (castVoices)
- generate_take: POST /api/content/dialogues/:collectionId/scenarios/:slug/audio then POST /api/tts/projects/:projectId/variants
- auto_stamp_take: POST /api/tts/projects/:projectId/variants/:variantId/auto-stamp
- set_lesson_thumbnail: POST /api/content/dialogues/:collectionId/thumbnail (multipart field `file`)
- clear_lesson_thumbnail: DELETE /api/content/dialogues/:collectionId/thumbnail
- set_scene_thumbnail: POST /api/content/dialogues/:collectionId/scenarios/:slug/thumbnail (multipart field `file`)
- clear_scene_thumbnail: DELETE /api/content/dialogues/:collectionId/scenarios/:slug/thumbnail

## Notes

- B is the learner. Named Kaito is B; otherwise the second speaker in appearance order.
- Long B line: Japanese length excluding inline parentheticals over 24 characters.
- Stage / ト書き: `{ type: "stage", text, visibility: "cold" | "practice" }`. Skipped by TTS. An opener (before the first spoken line, typically visibility "cold") may show on cold listen; mid-scene rows use "practice".
- Spoken `delivery`: optional Gemini TTS audio tags (e.g. `[softly]`, `[curious]`). Steers Generate Take only; never baked into japanese/romaji/english and not exported to the app.
- `sourceScript`: original Claude markdown brief used to author the scene. Studio-only; paste via Studio or `patch_scenario`; never exported to `/api/public/dialogues` or the iOS app.
- Missing togaki flag: no opener stage row before the first spoken line.
- Inline togaki: fullwidth or ASCII parentheticals in spoken Japanese text (still reported per line).
