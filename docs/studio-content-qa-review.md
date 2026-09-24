# Studio: learner-client content QA review

> **Status:** Shipped (API + persistence + Curriculum/editor readiness chip).  
> **Audience:** Colton / client agent building the iOS (or staff) review flow.  
> **Non-goals:** Learner-client UI (menu / “mark as reviewed” button); Studio take-approve Review queue; Gate B `isActive`; separate Progress page.

This is **content QA** (did a reviewer look over the dialogue + quiz for a scene?), not Studio **take review** (`reviewedAt` / flag clear on TTS variants). Do not conflate the two.

Studio surfaces status on the existing readiness chip row (`audio · timing · sync · quiz · thumb · qa`), not a separate Progress page.

---

## 0. Primary client action — scene check-off

**This is the endpoint the learner client should call later** to mark a scene reviewed / checked off.

```
POST /api/client/content-qa/dialogues/:collectionId/scenarios/:slug/check-off
```

| | |
|---|---|
| **Method** | `POST` |
| **Auth** | `Authorization: Bearer $CONTENT_QA_CLIENT_TOKEN` (required when Studio auth is enforced). Also accepts `STUDIO_AGENT_TOKEN` or a Studio Google session for demos. **Not** a public/unauthenticated write. |
| **Scope** | One **scene** (`collectionId` + `slug` → `dialogue_scenario.id`) |
| **Idempotent** | Yes — calling again when already checked off returns `200` with `alreadyCheckedOff: true` and does not change first-reviewed timestamps |
| **Effect** | Sets **both** `dialogueReviewed` and `quizReviewed` (see §1). Studio `qa` chip → `qa ✓` |

### Request body (optional JSON; empty body OK)

```json
{
  "reviewNote": "Dial + quiz OK for ship",
  "reviewedBy": "staff@example.com"
}
```

| Field | Type | Required | Behavior |
|---|---|---|---|
| `reviewNote` | string \| null | no | Max 4000. Omit = leave unchanged; `null` clears. |
| `reviewedBy` | string \| null | no | Max 200. Same omit/`null` rules. |

### Response `200` / `201`

```json
{
  "created": false,
  "alreadyCheckedOff": true,
  "review": {
    "scenarioId": "train-station/buying-a-ticket",
    "collectionId": "train-station",
    "dialogueReviewedAt": "2026-09-24T18:00:00.000Z",
    "quizReviewedAt": "2026-09-24T18:00:00.000Z",
    "reviewNote": "Dial + quiz OK for ship",
    "reviewedBy": "staff@example.com",
    "status": "done",
    "checkedOff": true,
    "createdAt": "…",
    "updatedAt": "…"
  },
  "readiness": {
    "contentQa": "done",
    "contentQaHasNote": true,
    "checkedOff": true
  }
}
```

| Field | For |
|---|---|
| `review.checkedOff` / `readiness.checkedOff` | Future client UI state (`true` ⇔ scene fully checked off) |
| `readiness.contentQa` | Same enum Studio chips use: `pending` \| `dialogue` \| `quiz` \| `done` |
| `readiness.contentQaHasNote` | Note indicator on the chip (`qa ✓·`) |
| `alreadyCheckedOff` | `true` if both flags were already set before this call |
| `404` | Scenario does not exist |

### Curl (copy/paste)

```bash
export CONTENT_QA_CLIENT_TOKEN=…   # or STUDIO_AGENT_TOKEN
export BASE=https://shizen-studio.vercel.app

curl -sS -X POST \
  "$BASE/api/client/content-qa/dialogues/train-station/scenarios/buying-a-ticket/check-off" \
  -H "Authorization: Bearer $CONTENT_QA_CLIENT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "reviewNote": "Dial + quiz OK for ship",
    "reviewedBy": "curl-demo"
  }'
```

Local (auth often bypassed):

```bash
curl -sS -X POST \
  "http://localhost:3000/api/client/content-qa/dialogues/train-station/scenarios/buying-a-ticket/check-off" \
  -H "Content-Type: application/json" \
  -d '{"reviewNote":"OK"}'
```

Then open Studio → **Curriculum**. Scene chip row shows `qa ✓·`. Refresh if the dialogues query was cached.

---

## 1. Data model — how “checked off” relates to dialogue / quiz

Table: `dialogue_scenario_content_qa` (one row per scenario).

| Column | Meaning |
|---|---|
| `scenario_id` PK | `dialogue_scenario.id` = `collectionId/slug` |
| `dialogue_reviewed_at` | When dialogue/lines were marked looked-over (null = not yet) |
| `quiz_reviewed_at` | When quiz questions were marked looked-over (null = not yet) |
| `review_note` | Freeform note for Studio (nullable) |
| `reviewed_by` | Optional label (email, device id, staff handle) |
| `created_at` / `updated_at` | Row timestamps |

There is **no separate DB column** for “checked off.” It is derived:

| Concept | Definition |
|---|---|
| **`checkedOff`** (API boolean) | `dialogue_reviewed_at != null` **AND** `quiz_reviewed_at != null` |
| **`status: "done"`** | Same condition |
| Studio chip `qa ✓` | Same condition |

So:

- **Scene check-off** (`POST …/check-off`) = set **both** dialogue + quiz reviewed → `checkedOff: true`.
- Granular upsert can set dialogue only or quiz only → partial chip (`qa dial` / `qa quiz`) until both are set.
- `checkedOff: false` on the granular PUT clears **both** timestamps.

**Derived `status`:**

| Status | Rule | Chip |
|---|---|---|
| `pending` | Neither flag (or no row) | `qa —` |
| `dialogue` | Dialogue only | `qa dial` |
| `quiz` | Quiz only | `qa quiz` |
| `done` | Both (= checked off) | `qa ✓` |

Trailing `·` on the chip when a note exists.

**Grain:** scenario (scene). Lesson/unit rollups are derived in Studio from scenario chips / list API.

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

## 3. Other endpoints

Base (prod): `https://shizen-studio.vercel.app`

### 3.1 Get / granular upsert (client)

```
GET    /api/client/content-qa/dialogues/:collectionId/scenarios/:slug
PUT    /api/client/content-qa/dialogues/:collectionId/scenarios/:slug
PATCH  /api/client/content-qa/dialogues/:collectionId/scenarios/:slug
```

Use when the client needs **partial** progress (dialogue only, quiz only, note-only edit). For full scene check-off, prefer §0.

`PUT` and `PATCH` share the same body (idempotent upsert). Prefer `PUT`.

**Request body (Zod):**

```json
{
  "checkedOff": true,
  "dialogueReviewed": true,
  "quizReviewed": true,
  "reviewNote": "Dialogue pacing feels natural; quiz evidence links check out.",
  "reviewedBy": "colton@example.com"
}
```

All fields optional, but at least one required.

| Field | Type | Behavior |
|---|---|---|
| `checkedOff` | boolean | `true` = both dialogue + quiz reviewed (same as §0). `false` clears both. |
| `dialogueReviewed` | boolean | `true` sets `dialogue_reviewed_at` **once** (keeps first timestamp). `false` clears it. Ignored when `checkedOff` is set. |
| `quizReviewed` | boolean | Same for quiz. Ignored when `checkedOff` is set. |
| `reviewNote` | string \| null | Max 4000. `null` clears. Omit = leave unchanged. |
| `reviewedBy` | string \| null | Max 200. Same null/omit rules. |

**Response** matches §0 (`review` + `readiness` + `created` + `alreadyCheckedOff`).

`GET` with no row yet returns a synthetic `status: "pending"` / `checkedOff: false` payload (`createdAt`/`updatedAt` null) — not 404.

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

Same body as §3.1. Use this from a Studio session when the iOS client is not ready. Still prefer documenting §0 as the production client path.

Curriculum / collection APIs already embed QA into each scenario’s `readiness.contentQa` (+ `contentQaHasNote`) for chips — no extra fetch required for the chip row after a successful write (client may still want `readiness` from the write response for local UI).

---

## 4. Idempotency

- Re-sending check-off / `dialogueReviewed: true` / `quizReviewed: true` when already set **does not** refresh first-reviewed timestamps.
- Notes / `reviewedBy` overwrite when provided.
- Clearing uses explicit `checkedOff: false` or `dialogueReviewed`/`quizReviewed: false` / `null` notes.

---

## 5. What the flags mean

| Flag | Means | Does **not** mean |
|---|---|---|
| Dialogue reviewed | A reviewer looked over the spoken dialogue/lines for that scene | Take karaoke approved; Gate A publish; audio green |
| Quiz reviewed | A reviewer looked over the quiz questions | Quiz “published” readiness; evidence links complete |
| Checked off | Both of the above (`status: done`) | Gate B live; lesson `isActive` |
| Review note | Freeform feedback for Studio operators | Structured bug tickets |

Gate A (CDN publish) and Gate B (`isActive`) are unchanged — see `docs/studio-two-gate-publish.md`. Content QA is a separate curriculum-readiness signal.

---

## 6. Repo anchors

| Area | Path |
|---|---|
| **Scene check-off route** | `webapp/app/api/client/content-qa/dialogues/[collectionId]/scenarios/[slug]/check-off/route.ts` |
| Schema / migration | `webapp/lib/db/schema.ts`, `webapp/drizzle/0011_dialogue_scenario_content_qa.sql` |
| Zod + status helpers | `webapp/lib/dialogue/content-qa.ts` |
| Persistence | `webapp/lib/dialogue/content-qa-store.ts` |
| Granular client API | `webapp/app/api/client/content-qa/dialogues/.../route.ts` |
| Studio list + seed | `webapp/app/api/content/content-qa/...` |
| Chip wiring | `scenario-readiness.ts`, `scenario-readiness-chips.tsx`, `load-scenario-readiness.ts` |
| Auth | `webapp/lib/studio-auth.ts`, `webapp/proxy.ts`, `webapp/AUTH.md` |
