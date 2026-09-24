# Studio: learner-client content QA review

> **Status:** Shipped (API + persistence + Curriculum/editor readiness chip).  
> **Audience:** Colton / client agent building the iOS (or staff) review flow.  
> **Non-goals:** Learner-client UI; Studio take-approve Review queue; Gate B `isActive`.

This is **content QA** (did a reviewer look over the dialogue + quiz for a scene?), not Studio **take review** (`reviewedAt` / flag clear on TTS variants). Do not conflate the two.

Studio surfaces status on the existing readiness chip row (`audio · timing · sync · quiz · thumb · qa`), not a separate Progress page.

---

## 1. Data model

Table: `dialogue_scenario_content_qa` (one row per scenario).

| Column | Meaning |
|---|---|
| `scenario_id` PK | `dialogue_scenario.id` = `collectionId/slug` |
| `dialogue_reviewed_at` | When dialogue/lines were marked looked-over (null = not yet) |
| `quiz_reviewed_at` | When quiz questions were marked looked-over (null = not yet) |
| `review_note` | Freeform note for Studio (nullable) |
| `reviewed_by` | Optional label (email, device id, staff handle) |
| `created_at` / `updated_at` | Row timestamps |

**Grain:** scenario (scene). Lesson/unit rollups are derived in Studio from scenario chips / list API.

**Derived `status`:**

| Status | Rule |
|---|---|
| `pending` | Neither flag set (or no row) |
| `dialogue` | Dialogue reviewed, quiz not |
| `quiz` | Quiz reviewed, dialogue not |
| `done` | Both reviewed |

Chip labels: `qa —` · `qa dial` · `qa quiz` · `qa ✓` · trailing `·` when a note exists.

---

## 2. Auth

`/api/public/*` stays **read-only / unauthenticated**. Content QA writes are **not** public.

When Studio auth is enforced (Google / agent / passphrase / content-QA token configured):

| Caller | How |
|---|---|
| Future learner/staff client | `Authorization: Bearer $CONTENT_QA_CLIENT_TOKEN` |
| Studio MCP / curl demos | `Authorization: Bearer $STUDIO_AGENT_TOKEN` |
| Logged-in Studio human | Google session cookie (or Studio-side upsert route) |

Env: set `CONTENT_QA_CLIENT_TOKEN` on Vercel and in the client. See `webapp/AUTH.md`.

Local with auth unset / `STUDIO_AUTH_BYPASS=1`: writes work without a bearer (same as other Studio APIs).

---

## 3. Endpoints

Base (prod): `https://shizen-studio.vercel.app`

### 3.1 Upsert / get one scenario (client)

```
GET    /api/client/content-qa/dialogues/:collectionId/scenarios/:slug
PUT    /api/client/content-qa/dialogues/:collectionId/scenarios/:slug
PATCH  /api/client/content-qa/dialogues/:collectionId/scenarios/:slug
```

`PUT` and `PATCH` share the same body (idempotent upsert). Prefer `PUT`.

**Request body (Zod):**

```json
{
  "dialogueReviewed": true,
  "quizReviewed": true,
  "reviewNote": "Dialogue pacing feels natural; quiz evidence links check out.",
  "reviewedBy": "colton@example.com"
}
```

All fields optional, but at least one required.

| Field | Type | Behavior |
|---|---|---|
| `dialogueReviewed` | boolean | `true` sets `dialogue_reviewed_at` **once** (keeps first timestamp). `false` clears it. |
| `quizReviewed` | boolean | Same for quiz. |
| `reviewNote` | string \| null | Max 4000. `null` clears. Omit = leave unchanged. |
| `reviewedBy` | string \| null | Max 200. Same null/omit rules. |

**Response `200` / `201`:**

```json
{
  "created": false,
  "review": {
    "scenarioId": "train-station/buying-a-ticket",
    "collectionId": "train-station",
    "dialogueReviewedAt": "2026-09-24T18:00:00.000Z",
    "quizReviewedAt": "2026-09-24T18:01:00.000Z",
    "reviewNote": "…",
    "reviewedBy": "colton@example.com",
    "status": "done",
    "createdAt": "…",
    "updatedAt": "…"
  }
}
```

`GET` with no row yet returns a synthetic `status: "pending"` payload (`createdAt`/`updatedAt` null) — not 404.

`404` only when the scenario id does not exist in `dialogue_scenario`.

### 3.2 Studio list / summary

```
GET /api/content/content-qa
GET /api/content/content-qa?collectionId=train-station
```

Returns `{ reviews, summary }` where `summary` counts `total` / `pending` / `dialogueOnly` / `quizOnly` / `done` / `withNotes`.

### 3.3 Studio seed / demo upsert

```
PUT|PATCH /api/content/content-qa/dialogues/:collectionId/scenarios/:slug
```

Same body as the client route. Use this from a Studio session when the iOS client is not ready.

Curriculum / collection APIs already embed QA into each scenario’s `readiness.contentQa` (+ `contentQaHasNote`) for chips — no extra fetch required for the chip row.

---

## 4. Idempotency

- Re-sending `dialogueReviewed: true` when already reviewed **does not** refresh `dialogue_reviewed_at`.
- Same for quiz.
- Notes / `reviewedBy` overwrite when provided.
- Clearing uses explicit `false` / `null`.

---

## 5. What the flags mean

| Flag | Means | Does **not** mean |
|---|---|---|
| Dialogue reviewed | A reviewer looked over the spoken dialogue/lines for that scene | Take karaoke approved; Gate A publish; audio green |
| Quiz reviewed | A reviewer looked over the quiz questions | Quiz “published” readiness; evidence links complete |
| Review note | Freeform feedback for Studio operators | Structured bug tickets |

Gate A (CDN publish) and Gate B (`isActive`) are unchanged — see `docs/studio-two-gate-publish.md`. Content QA is a separate curriculum-readiness signal.

---

## 6. Demo (curl)

Replace collection/slug with a real scenario. Use a bearer when auth is enforced.

```bash
# Mark both gates + note (client token or Studio agent token)
curl -sS -X PUT \
  "https://shizen-studio.vercel.app/api/client/content-qa/dialogues/train-station/scenarios/buying-a-ticket" \
  -H "Authorization: Bearer $CONTENT_QA_CLIENT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "dialogueReviewed": true,
    "quizReviewed": true,
    "reviewNote": "Dial + quiz OK for ship",
    "reviewedBy": "curl-demo"
  }'
```

Then open Studio → **Curriculum** (or the lesson editor). The scene’s chip row should show `qa ✓·` (note indicator). Refresh if the dialogues query was already cached.

Studio-auth demo without client token:

```bash
curl -sS -X PUT \
  "http://localhost:3000/api/content/content-qa/dialogues/train-station/scenarios/buying-a-ticket" \
  -H "Content-Type: application/json" \
  -d '{"dialogueReviewed":true,"quizReviewed":false,"reviewNote":"Dialogue only so far"}'
```

---

## 7. Repo anchors

| Area | Path |
|---|---|
| Schema / migration | `webapp/lib/db/schema.ts`, `webapp/drizzle/0011_dialogue_scenario_content_qa.sql` |
| Zod + status helpers | `webapp/lib/dialogue/content-qa.ts` |
| Persistence | `webapp/lib/dialogue/content-qa-store.ts` |
| Client write API | `webapp/app/api/client/content-qa/...` |
| Studio list + seed | `webapp/app/api/content/content-qa/...` |
| Chip wiring | `scenario-readiness.ts`, `scenario-readiness-chips.tsx`, `load-scenario-readiness.ts` |
| Auth | `webapp/lib/studio-auth.ts`, `webapp/proxy.ts`, `webapp/AUTH.md` |
