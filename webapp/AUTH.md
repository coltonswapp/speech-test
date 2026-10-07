# Studio auth

Published iOS JSON (`/api/public/*`) stays open. Everything else is gated when any of Google, `STUDIO_AGENT_TOKEN`, `CONTENT_QA_CLIENT_TOKEN`, or `APP_PASSPHRASE` is set.

## Humans (Google)

1. Google Cloud Console → OAuth client (Web).
2. Authorized redirect URIs:
   - `http://localhost:3000/api/auth/callback/google`
   - `https://shizen-studio.vercel.app/api/auth/callback/google`
3. Vercel env:
   - `NEXTAUTH_URL=https://shizen-studio.vercel.app`
   - `NEXTAUTH_SECRET` (random 32+ chars)
   - `GOOGLE_CLIENT_ID`
   - `GOOGLE_CLIENT_SECRET`
   - `STUDIO_ALLOWED_EMAILS` (comma-separated, e.g. `coltonbswapp@gmail.com`)

Off-list Google accounts get AccessDenied.

## Agents / MCP

Set `STUDIO_AGENT_TOKEN` on Vercel and in the Studio MCP env. Requests send `Authorization: Bearer …`.

## Learner-client content QA writes

The future iOS/staff review client marks a **scene checked off** via:

`POST /api/client/content-qa/dialogues/:collectionId/scenarios/:slug/check-off`

(not `/api/public`). Set `CONTENT_QA_CLIENT_TOKEN` on Vercel and in the client; requests send `Authorization: Bearer …`. Studio agent bearer and Google sessions also work for demos. Full contract (body, response, idempotency, dialogue/quiz vs checkedOff): `docs/studio-content-qa-review.md`.

## Shizen notes (QA notes to Shohei)

Two endpoints, one contract (`source`, `source_id`, `title?`, `note`, `agent?`, `metadata.url`, `metadata.created_at`, optional `metadata.screenshot_jpeg`):

- `POST /api/client/content-qa/notes`: the iOS QA Note sheet. Bearer `CONTENT_QA_CLIENT_TOKEN` only.
- `POST /hooks/shizen-note`: other callers (Studio, MCP, scripts). Bearer `SHIZEN_NOTE_WEBHOOK_TOKEN` only; this token never ships in the app. Both paths skip the Studio proxy so each route's own token check applies.

Auth is checked before the body is read. Errors are plain text (`401` bad token, `400` e.g. `missing note`, `unknown source`, `bad created_at`). Accepted notes are stored in `shizen_note_job` and return `202 { "job_id": "job_…" }`; the job is then POSTed to `SHOHEI_DELIVERY_URL` with `Authorization: Bearer $SHOHEI_WEBHOOK_KEY` and marked `delivered` or `failed`. Missing `SHOHEI_DELIVERY_URL` or `SHOHEI_WEBHOOK_KEY` leaves the job `queued` with a clear error and does not POST. `agent` defaults to `shohei` and is passed through; Studio does no triage, Shohei's routine routes to Vikram or Hana.

`metadata.screenshot_jpeg` is an optional base64 JPEG (no `data:` prefix) of the lesson view under the QA sheet. Callers that omit it are unchanged. Studio uploads it to the private R2 bucket (`R2_BUCKET_NAME`) under `shizen-notes/<job>-<random>.jpg` and stores only the key. The base64 never goes to Shohei: his webhook ingest may strip large fields. Instead the Shohei POST carries `metadata.screenshot_url`, a signed R2 link valid for about 3 days, plus `metadata.screenshot_instructions` telling the routine to `curl -o screenshot.jpg` and read the file. If the upload fails, the note is still delivered without a screenshot.

## Cron

`GET /api/cron/slides` drafts the next unused spotlight and decomposition decks. Vercel Cron should send `Authorization: Bearer $CRON_SECRET` (also accepted: `STUDIO_AGENT_TOKEN`).

## Local

Leave those unset (or `STUDIO_AUTH_BYPASS=1` in non-production) so localhost MCP keeps working. `APP_PASSPHRASE` remains a fallback login if you still have it on production.

## Deploy notes

- 2026-09-20: Redeploy so prod picks up spoken-line `delivery` (PR #29 / `951a4cd`).
