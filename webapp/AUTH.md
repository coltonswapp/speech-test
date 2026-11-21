# Studio auth

Published iOS JSON (`/api/public/*`) stays open. Everything else goes through one gate, `isStudioRequestAllowed` in `lib/generate/access.ts`, run by `proxy.ts`. Production always enforces it, even if no credentials are configured.

| Credential | Where it works |
|---|---|
| Google session (next-auth JWT, decrypted with `NEXTAUTH_SECRET`, email on `STUDIO_ALLOWED_EMAILS`) | Everywhere |
| `STUDIO_AGENT_TOKEN` env bearer, or a named per-agent token from Settings → Agent tokens | Everywhere |
| `CRON_SECRET` bearer | `/api/cron/*` only |
| `CONTENT_QA_CLIENT_TOKEN` bearer (DEBUG iOS builds only) | `/api/client/*` only |
| Firebase ID token with the `staff: true` claim (Release iOS) | `/api/client/*` only |

`/api/client/*` skips the proxy; each of those routes calls `requireClientQaAccess` (`lib/client-auth.ts`), which verifies Firebase ID tokens with firebase-admin. Grant the claim with `services/llm-gateway/scripts/set-staff-claim.ts`.

A cookie named `next-auth.session-token` is not trusted until it decrypts: before 2026-11-13 the proxy only checked that it existed, so `next-auth.session-token=x` got in.

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

Create a named token per bot at **Settings → Agent tokens** (`/settings/agent-tokens`). Put that value in the bot's env as `STUDIO_AGENT_TOKEN` and send `Authorization: Bearer …`. Rotating or revoking one token does not lock the others out.

The shared Vercel env `STUDIO_AGENT_TOKEN` is still accepted during migration. Do not put a per-agent token in Vercel env unless you want every bot to share it. Studio stores only a SHA-256 of named tokens (plaintext is shown once at creation).

## Learner-client content QA writes

The future iOS/staff review client marks a **scene checked off** via:

`POST /api/client/content-qa/dialogues/:collectionId/scenarios/:slug/check-off`

(not `/api/public`). Set `CONTENT_QA_CLIENT_TOKEN` on Vercel and in the client; requests send `Authorization: Bearer …`. Studio agent bearer and Google sessions also work for demos. Full contract (body, response, idempotency, dialogue/quiz vs checkedOff): `docs/studio-content-qa-review.md`.

## Shizen notes (QA notes to Shohei)

Two endpoints, one contract (`source`, `source_id`, `title?`, `note`, `agent?`, `metadata.url`, `metadata.created_at`, optional `metadata.screenshot_jpeg`). `source` is `dialogue`, `quiz`, or `screen` (a debug screenshot of a surface with no lesson):

- `POST /api/client/content-qa/notes`: the iOS QA Note sheet. Bearer `CONTENT_QA_CLIENT_TOKEN` only.
- `POST /hooks/shizen-note`: other callers (Studio, MCP, scripts). Bearer `SHIZEN_NOTE_WEBHOOK_TOKEN` only; this token never ships in the app. Both paths skip the Studio proxy so each route's own token check applies.

Auth is checked before the body is read. Errors are plain text (`401` bad token, `400` e.g. `missing note`, `unknown source`, `bad created_at`). Accepted notes are stored in `shizen_note_job` and return `202 { "job_id": "job_…" }`; the job is then POSTed to `SHOHEI_DELIVERY_URL` with `Authorization: Bearer $SHOHEI_WEBHOOK_KEY` and marked `delivered` or `failed`. Missing `SHOHEI_DELIVERY_URL` or `SHOHEI_WEBHOOK_KEY` leaves the job `queued` with a clear error and does not POST. `agent` defaults to `shohei` and is passed through; Studio does no triage, Shohei's routine routes to Vikram or Hana.

`metadata.screenshot_jpeg` is an optional base64 JPEG (no `data:` prefix) of the lesson view under the QA sheet. Callers that omit it are unchanged. Studio uploads it to the private R2 bucket (`R2_BUCKET_NAME`) under `shizen-notes/<job>-<random>.jpg` and stores only the key. The base64 never goes to Shohei: his webhook ingest may strip large fields. Instead the Shohei POST carries `metadata.screenshot_url`, a signed R2 link valid for about 3 days, plus `metadata.screenshot_instructions` telling the routine to `curl -o screenshot.jpg` and read the file. If the upload fails, the note is still delivered without a screenshot.

## Clip audio uploads (clip audio script)

`GET`/`POST /hooks/clip-upload/:id` skips the Studio proxy; `public/clip-fetch.mjs` calls it from an editor's machine. Studio serves that script at `/clip-fetch.mjs` with no login (it holds no secrets), so the command Studio shows can `curl` it and pipe it into `node` from any folder. Auth is a one-time bearer token that Studio issues when a clip's details are saved (`POST /api/experiments/clip-uploads`, behind the normal Studio gate) and shows once inside the command. Only its SHA-256 is stored, in `experiments/clip-uploads/<id>/pending.json` in R2. The token works for that one id, for 24 hours, until the audio is accepted, the pending clip is discarded, or a new command is issued. It can fetch that clip's video id and range, get a 15-minute signed R2 `PUT` for `experiments/clip-uploads/<id>/source.wav`, and finalize, which creates clip `<id>` (or `<id>-01`, `<id>-02`, … when the audio is split) and never overwrites an existing clip; nothing else.

## Cron

`GET /api/cron/slides` drafts the next unused spotlight and decomposition decks. Vercel Cron should send `Authorization: Bearer $CRON_SECRET` (also accepted: the env `STUDIO_AGENT_TOKEN` or a named per-agent token).

## Local

Leave those unset (or `STUDIO_AUTH_BYPASS=1` in non-production) so localhost MCP keeps working. The `APP_PASSPHRASE` login was removed on 2026-11-13.

## Deploy notes

- 2026-09-20: Redeploy so prod picks up spoken-line `delivery` (PR #29 / `951a4cd`).
