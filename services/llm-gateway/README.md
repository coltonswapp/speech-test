# shizen-llm-gateway

Minimal Cloud Run service that proxies Shizen LLM features to Gemini with a server-side key.
Callers authenticate with a Firebase ID token; the Gemini key never ships in the app.

- `GET /health` → `{ "ok": true }` (no auth)
- `POST /v1/generate` → Firebase-authenticated; `feature` picks the prompt. `POST /v1/gloss` is an alias kept for the first Common Uses builds.

Stack: Node 22, TypeScript, Hono, `firebase-admin`, `@google/genai`.

Prompts, response schemas, and model choices live in `src/features/`, so they can change with a redeploy instead of an app release.

## API

### `POST /v1/generate`

Headers: `Authorization: Bearer <Firebase ID token>`, `Content-Type: application/json`

The body is `{ "feature": "<name>", ...feature fields }`. Every success response has the same envelope:

```json
{
  "feature": "common_uses",
  "requestId": "11111111-1111-4111-8111-111111111111",
  "feedbackToken": "1750000000.<base64url hmac>",
  "result": { "...": "feature-specific" },
  "model": "gemini-2.5-flash",
  "usage": { "promptTokenCount": 380, "candidatesTokenCount": 50, "totalTokenCount": 430 }
}
```

`result` comes from Gemini structured output, and the iOS clients still apply their own cleanup to it. They record `usage` in the app's local Gemini usage history. `requestId` is also on the `llm ok` log line. `feedbackToken` is not logged. It expires 24 hours after the response and is bound to this user, this input, and this result.

### Features

| `feature` | Request fields | `result` | Default model | iOS client |
| --- | --- | --- | --- | --- |
| `common_uses` | `surface` (≤64), `sentence` (≤500), `dictionaryGloss?` | `inThisSentence`, `otherUses[]`, `kanjiNote` | `gemini-2.5-flash` | `GeminiCommonUses` (`GeminiTokenLookup.swift`) |
| `contextual_gloss` | `surface`, `sentence`, `framing` (`inSentence` or `word`), `dictionaryForm?`, `dictionaryGloss?`, `requestsHeadword?` | `meaning`, `grammarNote`, `relatedWords[{word, note}]`, `headword` | `gemini-2.5-flash-lite` | `GeminiContextualGloss` |
| `sense_fit` | `surface`, `sentence`, `senses[]` (2–30, ≤300 chars each) | `index` (always in range) | `gemini-2.5-flash-lite` | `GeminiVocabSenseRanker` (`VocabSenseRanker.swift`) |
| `dialogue_nuance` | `focused {speaker?, japanese, english?}`, `preceding[]` and `following[]` (≤2 lines each) | `naturalMeaning`, `impliedMeaning`, `notes` | `gemini-2.5-flash` | `GeminiDialogueNuance` |
| `span_gloss` | `surface` (≤120), `sentence` | `meaning`, `note` | `gemini-2.5-flash` | `GeminiSpanGloss` (`GeminiTokenLookup.swift`) |
| `span_breakdown` | `surface` (≤120), `sentence` | `inThisSentence`, `otherUses[]`, `partsNote` | `gemini-2.5-flash` | `GeminiSpanBreakdown` (`GeminiTokenLookup.swift`) |
| `grammar_usage` | `pattern` (≤60), `grammarPointID?`, `lines[{speaker?, japanese, english?, focus?}]` (1–12) | `inThisScene`, `form`, `examples[]` (≤3), `note` | `gemini-2.5-flash` | `GeminiGrammarUsage` |

Optional hint strings are trimmed and truncated (`dictionaryGloss` to 300 characters), not rejected.

To add a feature, create `src/features/<name>.ts` with `defineFeature({ defaultModel, parseInput, build, parseResult })` and register it in `src/features/index.ts`.

### Errors

| Status | Body | When |
| --- | --- | --- |
| 400 | `{ "error": "invalid_json" }` | Body isn't a JSON object |
| 400 | `{ "error": "invalid_request", "detail": "..." }` | A feature field is missing, the wrong type, or too long |
| 400 | `{ "error": "unknown_feature" }` | `feature` isn't one of the names above |
| 401 | `{ "error": "unauthorized" }` | Missing, malformed, expired, wrong-project, or anonymous token |
| 413 | `{ "error": "invalid_request", "detail": "body too large" }` | Body over 32 KB |
| 502 | `{ "error": "upstream_error" }` | Gemini failed, timed out (20 s), or returned output that doesn't match the schema, such as an out-of-range `index` (details in server logs) |

The iOS app reads the base URL from `SHIZEN_LLM_GATEWAY_URL` in `shizen/Info.plist`. A scheme env var of the same name overrides it, for example to point at a local `npm run dev`. On a 401, the app refreshes the ID token once and retries.

### Usage (estimated spend)

Each successful generate increments **day, week, and month** rollups in Firestore (`shizen-b453f`, collection `llmUsage`). Prompt text is not stored. Cost uses the same published Gemini rates as the iOS `GeminiPricing` helper (micros in the docs, dollars in the API).

Periods are UTC: `day` is `YYYY-MM-DD`, `week` is ISO `YYYY-Www`, `month` is `YYYY-MM`. Query `?period=day|week|month` (default `week`).

| Endpoint | Who | Body |
| --- | --- | --- |
| `GET /v1/usage` | The signed-in user | `{ period, periodKey, calls, promptTokens, outputTokens, estimatedCostUSD, hasUnpriced, byFeature }` |
| `GET /v1/usage/features` | Product-wide (`_product`) | Same totals plus `features[]` ranked by calls |

```bash
curl -s "$BASE/v1/usage?period=week" -H "Authorization: Bearer $ID_TOKEN"
curl -s "$BASE/v1/usage/features?period=month" -H "Authorization: Bearer $ID_TOKEN"
```

Look up one user in the Firebase console: `llmUsage/{uid}/periods/week_2026-W40`. The Cloud Run service account in `shizen-studio` needs `roles/datastore.user` on `shizen-b453f`. Clients cannot read this collection (see `firestore.rules`). Studio's Firebase Admin reader should also be allowed to read `llmFeedbackStats/**` (sentiment) and, only if a thumbs-down queue is added, `llmFeedback/**`.

### Feedback

`POST /v1/feedback` — same Firebase auth as generate. Body limit 64 KB.

```json
{
  "requestId": "11111111-1111-4111-8111-111111111111",
  "feedbackToken": "<token from generate>",
  "feature": "span_gloss",
  "model": "gemini-2.5-flash",
  "rating": "down",
  "reason": "wrong_meaning",
  "input": { "sentence": "...", "surface": "..." },
  "result": { "meaning": "...", "note": "" },
  "deviceId": "optional-app-uuid"
}
```

`input` is the feature fields (a `feature` key on that object is ignored). The gateway runs the same `parseInput` as generate, then checks the HMAC. `result` is the object from the generate response, not the client's display cleanup. `reason` is optional and only on `down`: `wrong_meaning`, `not_about_sentence`, `confusing`.

Success is `{ "ok": true }`, including a retry of the same vote and a rejected rating change. The document id is `requestId`. The first write sets the rating; a later call can only fill an empty `reason` on a down vote. Stats increment once, on create.

| Status | Body | When |
| --- | --- | --- |
| 400 | `{ "error": "invalid_request", "detail": "..." }` | Bad body, unknown feature, or token rejected / expired |
| 429 | `{ "error": "rate_limited", "detail": "..." }` | More than 40 accepted votes for this uid in the UTC hour |

A `deviceId` over 40 votes in the hour across accounts is logged and still accepted. The uid cap is the block.

Votes are stored in `llmFeedback/{requestId}` (input and result on every down, and about 1 in 10 ups). Counters are `llmFeedbackStats/{uid|_product}/periods/{periodId}` with literal dotted keys `byFeature.<id>.up` and `byFeature.<id>.down`. See [FIRESTORE_USAGE_CONTRACT.md](FIRESTORE_USAGE_CONTRACT.md). Docs expire after `LLM_FEEDBACK_RETENTION_DAYS` (default 90) once a TTL policy is enabled on `expiresAt`.

## Config

All config is env-only; see [`.env.example`](.env.example). Never commit `.env`.

| Var | Required | Notes |
| --- | --- | --- |
| `GEMINI_API_KEY` | yes | Secret Manager in prod |
| `FIREBASE_PROJECT_ID` | yes | `shizen-b453f`; tokens from other projects are rejected |
| `LLM_FEEDBACK_HMAC_KEY` | yes | Secret Manager in prod. At least 32 characters. Signs feedback tokens. Never put this in the app |
| `LLM_FEEDBACK_RETENTION_DAYS` | no | TTL age for `llmFeedback` docs. Default 90 |
| `GEMINI_MODEL_<FEATURE>` | no | Per-feature model override, e.g. `GEMINI_MODEL_CONTEXTUAL_GLOSS=gemini-2.5-flash`. Change it with `gcloud run services update shizen-llm --region us-central1 --update-env-vars=...`, no rebuild needed |
| `PORT` | no | Cloud Run sets this; defaults to 8080 |

The service exits on startup if a required var is missing.

## Run locally

```bash
cd services/llm-gateway
cp .env.example .env        # fill in GEMINI_API_KEY
npm ci
npm run dev                 # tsx watch, loads .env
# or: npm run build && node --env-file=.env dist/index.js
```

With Docker:

```bash
docker build -t shizen-llm .
docker run --rm -p 8080:8080 --env-file .env shizen-llm
```

**Credentials.** Verifying ID tokens only needs Google's public certs plus `FIREBASE_PROJECT_ID`, so it normally works with no service account. If local verification fails with a credentials error, run `gcloud auth application-default login`. For Docker, also mount those credentials:

```bash
docker run --rm -p 8080:8080 --env-file .env \
  -v "$HOME/.config/gcloud/application_default_credentials.json:/tmp/adc.json:ro" \
  -e GOOGLE_APPLICATION_CREDENTIALS=/tmp/adc.json \
  shizen-llm
```

On Cloud Run the Admin SDK uses the runtime service account automatically.

## Deploy (Cloud Run)

Deployed at `https://shizen-llm-438095805917.us-central1.run.app`.

Defaults: region `us-central1`, min instances 0, public HTTPS (`--allow-unauthenticated`). End-user auth is the Firebase ID token checked in app code, not Cloud Run IAM.

The service runs in the GCP project **`shizen-studio`** (already billed), while tokens are verified against the Firebase project **`shizen-b453f`** via `FIREBASE_PROJECT_ID`. Token verification only uses Google's public certs, so the two projects don't need to match. (`shizen-b453f` couldn't be linked to billing because the billing account is at its project limit.)

One-time setup:

```bash
gcloud config set project shizen-studio
gcloud services enable run.googleapis.com cloudbuild.googleapis.com \
  artifactregistry.googleapis.com secretmanager.googleapis.com

PROJECT_NUMBER=$(gcloud projects describe shizen-studio --format='value(projectNumber)')
COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

# Source deploys build as the default compute SA, which needs this role
gcloud projects add-iam-policy-binding shizen-studio \
  --member="serviceAccount:${COMPUTE_SA}" --role=roles/run.builder

# Create the secret (paste the key, then Ctrl-D)
gcloud secrets create GEMINI_API_KEY --data-file=-

# Let the Cloud Run runtime service account read it
gcloud secrets add-iam-policy-binding GEMINI_API_KEY \
  --member="serviceAccount:${COMPUTE_SA}" \
  --role=roles/secretmanager.secretAccessor

# Feedback HMAC secret (openssl rand -base64 32). Same accessor binding as the Gemini key.
gcloud secrets create LLM_FEEDBACK_HMAC_KEY --data-file=-
gcloud secrets add-iam-policy-binding LLM_FEEDBACK_HMAC_KEY \
  --member="serviceAccount:${COMPUTE_SA}" \
  --role=roles/secretmanager.secretAccessor
```

Rotate the key later with `gcloud secrets versions add GEMINI_API_KEY --data-file=-` and redeploy (or it picks up `latest` on the next cold start).

Deploy. Run this from `services/llm-gateway/`, **not** the repo root, or `--source .` packages the wrong tree:

```bash
cd services/llm-gateway
gcloud run deploy shizen-llm --source . --region us-central1 \
  --min-instances=0 --max-instances=3 \
  --allow-unauthenticated \
  --set-secrets=GEMINI_API_KEY=GEMINI_API_KEY:latest,LLM_FEEDBACK_HMAC_KEY=LLM_FEEDBACK_HMAC_KEY:latest \
  --set-env-vars=FIREBASE_PROJECT_ID=shizen-b453f
```

`--max-instances=3` is a cheap cost backstop, not a rate limit (see below).

## curl

```bash
BASE=http://localhost:8080   # or the Cloud Run URL
curl -s $BASE/health

# 401
curl -s -X POST $BASE/v1/generate -H 'Content-Type: application/json' \
  -d '{"surface":"行く","sentence":"明日行く。","feature":"common_uses"}'

# 200
curl -s -X POST $BASE/v1/generate \
  -H "Authorization: Bearer $ID_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"surface":"行く","sentence":"明日行く。","feature":"common_uses"}'

curl -s -X POST $BASE/v1/generate \
  -H "Authorization: Bearer $ID_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"feature":"sense_fit","surface":"かける","sentence":"眼鏡をかける。","senses":["to hang","to wear (glasses)","to make a call"]}'
```

### Getting `$ID_TOKEN`

ID tokens expire after about an hour.

- **From the app (Apple/Google sign-in).** Shizen only offers Apple and Google sign-in, so the easiest path is a debug build that temporarily prints the token for a signed-in test user. Don't commit this.

  ```swift
  if let token = try? await Auth.auth().currentUser?.getIDToken() { print("ID_TOKEN", token) }
  ```

- **Email/password test user (optional).** If you enable the Email/Password provider in Firebase Auth and create a test user, use the `API_KEY` from `GoogleService-Info.plist`:

  ```bash
  ID_TOKEN=$(curl -s "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$FIREBASE_WEB_API_KEY" \
    -H 'Content-Type: application/json' \
    -d '{"email":"test@example.com","password":"...","returnSecureToken":true}' | jq -r .idToken)
  ```

## Logs

Logs are one JSON object per line, so Cloud Logging turns them into filterable `jsonPayload` fields. Uids are never logged. `user` is the first 12 hex characters of `sha256(uid)`, enough to spot one user repeating a call.

| `message` | Severity | Fields |
| --- | --- | --- |
| `llm ok` | INFO | `feature`, `user`, `model`, `request` (the parsed feature input), `result`, `tokens`, `latencyMs` |
| `llm upstream error` | ERROR | same context plus `error` and `cause` |
| `llm bad model output` | ERROR | same context plus `error` and `rawOutput` (first 1000 chars) |
| `verifyIdToken failed` | WARNING | `code` (Firebase error code; no token) |

Example Logs Explorer queries:

```text
resource.type="cloud_run_revision" resource.labels.service_name="shizen-llm"
jsonPayload.message="llm ok"
jsonPayload.feature="contextual_gloss"
```

```text
resource.type="cloud_run_revision" resource.labels.service_name="shizen-llm"
severity>=ERROR
```

Cloud Logging keeps these for 30 days by default.

## Notes

- **Abuse / rate limits.** `verifyIdToken` only proves the caller is *some* signed-in Firebase user. It does not stop one user, or anyone who can create an account, from burning Gemini spend on this public URL. A per-uid cap (in-memory or Firestore counter) is the next step once curl works. Until then the backstops are `--max-instances` and a quota on the Gemini API key.
- **CORS** is not enabled because v1 is iOS-only. Add `hono/cors` if Studio web calls this later.
- **Features.** `src/features.ts` holds the single feature switch. Add new cases (e.g. `best_fit_sense`) there.
