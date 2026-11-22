# Shizen Content Studio MCP

Local stdio MCP server wrapping Content Studio REST APIs. No auth.

Studio should already be running. STUDIO_BASE_URL defaults to http://localhost:3000.

## Tools

- list_curriculum: units (including Studio-only `notes`), collections, scenario slugs/titles, unpublished flag
- patch_unit_notes: update unit writer notes (`storyboard` / `characters` / `background` / `freeform`); partial sections; `clear:true` wipes all. Studio-only — not public/iOS export
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

## Clip tools (Experiments → Clips)

Registered from `src/clips.ts`. Slow work runs as **background jobs** (`src/jobs.ts`): the tool returns a `jobId` (optionally after `waitSeconds` ≤ 55), and `get_clip_job` polls it. Jobs live in this server process; finished steps are saved in Studio, so after a restart re-run `run_clip_steps` mode `missing`.

Read
- list_clips: summaries with pipeline state, level, feed verdict + reason; filters (feed, level, unrated, unfinished, channel, search, orientation, deprecated); pending uploads
- get_clip: transcript as `index · ja · en · tokens` (`今日(きょう) | は`) with per-line warnings (low aligner score < 0.3, reading fallback, untimed, basic split, missing English, reviewed), feed rules, missing steps, cost. `view: "full"` adds token timings
- get_public_clip / list_public_clips: exactly what the iOS app receives
- clip_report: feed / level / channel counts, why clips are out of the feed, `needsLook` buckets of clip ids, cost by step / model / day (`since`)

Edit
- patch_clip: transcript, split/merge at token boundaries (keeps tokens and alignment), English, one line's tokens, **swap** (one-word surface/reading change; keeps timings and the feed verdict), clearFlags, highlights, jlptLevel, feedEligible, deprecated, shiftSec, orientation. Returns the new checks and what to re-run
- delete_clip (`confirm: true`; prefer `deprecated` for clips that have been live)

Pipeline and jobs
- run_clip_steps: `mode: "missing"` (what each clip lacks, retry once) or `"steps"`; `model`, `retokenize`, `onlyUntimed`, `concurrency`
- get_clip_job, list_clip_jobs, cancel_clip_job

Create and queue
- create_clip_from_youtube: id + video id/link + range → saves details, runs `public/clip-fetch.mjs` (yt-dlp + ffmpeg on this machine), then every step
- discard_clip_pending
- list_clip_queue, set_clip_queue_status
- run_clip_queue_batch (`pnpm clip:queue-batch`: count, channel, dryRun, resume)
- seed_clip_queue (`pnpm clip:queue-seed`)

Add Shorts to the queue (`src/queue-add.ts`, lookups in `src/youtube.ts`)
- find_channel_shorts: channel URL / @handle / UC id / name + count → recent Shorts as candidates (job). A name is used only when exactly one search result matches it exactly; otherwise the matches come back to choose from
- review_youtube_videos: 1–20 links or ids → one candidate per input, in order (job)
- add_to_clip_queue: the approved ids → `queued` entries. Doesn't process; follow with run_clip_queue_batch. Safe to retry
- Candidate verdicts: addable, in-queue, skipped-in-queue, already-clipped, fetching, unavailable (deleted / private / live / age-restricted), ineligible (not vertical, over 120 s), duplicate-input, invalid-input. Queue warnings (under 20 s, outside feed length, no Japanese title, music title) don't block adding
- Needs yt-dlp on PATH (or `YT_DLP_PATH`); no YouTube API key. Queue checks and the write are `POST /api/experiments/clip-queue` (`dryRun` for review), backfill_clip_index (`pnpm clip:index-backfill`), compare_clip_asr (`pnpm clip:asr-compare` locally; `POST /api/experiments/clips/:id/asr-compare` on the server when STUDIO_BASE_URL isn't localhost, or `server: true`)

The script tools run from `webapp/` with `webapp/.env.local` (production R2 and database for seed / backfill / ASR compare); `--write` style changes are off unless `write: true`. Batch and step tools talk to `STUDIO_BASE_URL`; against prod set `STUDIO_AGENT_TOKEN` to a named per-agent token from Studio **Settings → Agent tokens** (the shared env token is still accepted during migration).

Server side: `GET /api/experiments/clip-report` (`?ids=`, `?since=`) computes the per-clip checks (`lib/experiments/clips/checks.ts`) and totals, so agents see the same rules as the Studio editor.

## Learner clip feedback (`src/feedback.ts`)

Agents work the reports learners send from the app, one at a time. Each take is an attempt in Studio with server-side before/after snapshots of the clip (see docs/clip-agent-tickets-plan.md).

- list_clip_feedback: open reports (or `status`), with reason, note, the reported line and word, each report's attempts, and the Studio issue URL
- claim_clip_feedback / get_content_issue / claim_content_issue: take a report by `cfb_…`, `clip-cfb_…`, or the Studio issue URL copied from Content Issues. Returns `attemptId`, the clip, and the playbook for the report's reason. Fails while another attempt is working (`takeOver` for a dead run)
- finish_clip_feedback: close with `fixed` / `no_change_needed` (resolves the report), `needs_review` (a person compares and accepts), or `could_not_fix`. Returns the diff

Studio's **Send to agent** posts the same report to Grok Bot or OpenBot by webhook; the bot then calls claim and finish like anyone else.

## Speech audio (`src/audio.ts`)

- generate_audio: say a line with Studio's Gemini TTS (`POST /api/generate`) and download the MP3s. Arguments: `text`, `voice`, optional `delivery` ("Casual, like asking a friend a quick question" or `[whispering]`-style tags), `takes` (1 by default, up to 5), `title`, `save` (keeps the generations in Studio's Generate library past their ~24 h expiry), and `outputDir` (default `<tmp>/shizen-audio`)
- list_tts_voices: the Gemini voice catalog (73 ja-JP Tokyo library voices with casting names, plus 30 prebuilt voices), filtered by `language`, `gender` or `search`

## Thumbnails (Hana)

Lesson = collection card art. Scene overrides the lesson for that scenario only; clearing the scene restores the lesson fallback.

Provide **exactly one** image source:

- **imageUrl** (preferred): HTTP(S) URL the MCP can fetch. Use this when you already have a public or Studio URL.
- **imageBase64**: raw base64 bytes, or a `data:image/...;base64,...` data URL. Pass **contentType** (`image/jpeg` | `image/png` | `image/webp` | `image/gif`) unless the value is a data URL or **filename** ends in `.jpg`/`.jpeg`/`.png`/`.webp`/`.gif`.

Optional **filename** sets the multipart file name and can help MIME inference. Requires published R2 on Studio (`R2_PUBLISHED_*`).

## How to run

Install this folder dependencies, then run the TypeScript entry src/index.ts over stdio.

## AddMcpServer

Registered for Claude Code in the repo's `.mcp.json` and for Cursor in `.cursor/mcp.json` (server name `shizen-studio`). Elsewhere: run `node_modules/.bin/tsx src/index.ts` over stdio.
Set STUDIO_BASE_URL if Studio is not at http://localhost:3000

## APIs each tool hits

- list_curriculum: GET /api/content/units and GET /api/content/dialogues
- patch_unit_notes: GET /api/content/units then PATCH /api/content/units/:unitId (`notes`)
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
