# Shizen Content Studio MCP

Local stdio MCP server wrapping Content Studio REST APIs. No auth.

Studio should already be running. STUDIO_BASE_URL defaults to http://localhost:3000.

## Tools

- list_curriculum: units, collections, scenario slugs/titles, unpublished flag
- get_scenario: speakers, spoken rows, and stage/ト書き rows as { type, text, visibility, role: "stage" }; B-line lengths, grammar tags, unpublished flag; flags long B lines and a missing opener ト書き
- patch_scenario: patch lines and metadata via existing scenario PATCH. Lines are a flat object: spoken needs speaker+japanese; stage needs type "stage", text, visibility
- get_cast_voices: collection castVoices (Kaito to Orus, etc.)
- set_cast_voices: replace collection castVoices
- generate_take: ensure scenario audio project, then kick a TTS take
- auto_stamp_take: forced-align a take (token karaoke + line marks); optional force to overwrite human stamps

Does not expose waveform, trim, or export tools.

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

## Notes

- B is the learner. Named Kaito is B; otherwise the second speaker in appearance order.
- Long B line: Japanese length excluding inline parentheticals over 24 characters.
- Stage / ト書き: `{ type: "stage", text, visibility: "cold" | "practice" }`. Skipped by TTS. An opener (before the first spoken line, typically visibility "cold") may show on cold listen; mid-scene rows use "practice".
- Missing togaki flag: no opener stage row before the first spoken line.
- Inline togaki: fullwidth or ASCII parentheticals in spoken Japanese text (still reported per line).
