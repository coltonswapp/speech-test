# Firestore LLM usage writer contract

For Studio `/usage` (or any other reader of these docs). Parse the **Firestore period documents**, not the gateway HTTP envelope — those are different contracts.

Writer: `recordUsage` in `services/llm-gateway/src/usage.ts`.
Project: **`shizen-b453f`** (default database). Clients cannot read this collection (`firestore.rules` deny). Studio uses a service account.

No field renames are planned. Hard-code the names below.

---

## Paths

Collection: `llmUsage`.

| Scope | Path |
| --- | --- |
| Product-wide | `llmUsage/_product/periods/{periodId}` |
| Per user | `llmUsage/{uid}/periods/{periodId}` |

`_product` is a literal parent document id. `{uid}` is the Firebase Auth uid.

On every successful `POST /v1/generate`, the same payload is merged into **both** scopes × **three** periods (6 writes). Failed / 4xx / 502 generates write nothing. Prompt text is not stored.

---

## Period ids

**Timezone: UTC only.** Not device local, not America/Denver.

| Period | Document id | Key example |
| --- | --- | --- |
| Day | `day_YYYY-MM-DD` | `day_2026-09-29` |
| Week | `week_YYYY-Www` | `week_2026-W40` |
| Month | `month_YYYY-MM` | `month_2026-09` |

Week is **ISO-8601 week-date in UTC**:

- Weeks Monday–Sunday
- Week 1 is the week containing the first Thursday of the ISO week-year
- Week number is zero-padded to 2 digits
- Week-year can differ from calendar year around 1 January

Implementation (same as `periodKeys` / `isoWeekKey` in `usage.ts`):

```
day:   `${utcYear}-${utcMonth}-${utcDay}`          // YYYY-MM-DD
week:  `${isoWeekYear}-W${isoWeek}`                // YYYY-Www
month: `${utcYear}-${utcMonth}`                    // YYYY-MM
docId: `${period}_${key}`                          // day_… / week_… / month_…
```

`period` and `periodKey` are **not stored on the document**. Parse them from the document id: `{period}_{key}`.

---

## Top-level fields (Firestore)

There is **no** `tokens`, `totalTokens`, `estimatedUsd`, or `estimatedCostUSD` on these docs. Cost is **integer micros**. Tokens are always split.

| Field | Type | Units | How written |
| --- | --- | --- | --- |
| `calls` | number | count | `FieldValue.increment(1)` |
| `promptTokens` | number | tokens | `increment(promptTokenCount)` |
| `outputTokens` | number | billed output tokens | `increment(billedOutput)` |
| `estimatedCostMicros` | number | USD × 1_000_000, `Math.round` | `increment(micros)` |
| `unpricedCalls` | number | count | `increment(1)` **only** when the model has no published rate |
| `updatedAt` | Timestamp | server time | `FieldValue.serverTimestamp()` (last-write) |

**Cost:** `1_000_000` micros = **$1.00**. Display USD as `estimatedCostMicros / 1_000_000`.

**`outputTokens`** is not Gemini `candidatesTokenCount` alone. It is:

```
if totalTokenCount > 0:
  max(candidatesTokenCount, totalTokenCount - promptTokenCount)
else:
  candidatesTokenCount
```

Thinking tokens are therefore billed as output. Gemini `totalTokenCount` is **never written**.

Never a single `tokens` field. If a UI wants a total, sum `promptTokens + outputTokens` (billed total, not a stored field).

Model name is not stored on the period doc. Uid is not stored on user period docs (it is the parent document id).

---

## `byFeature` shape — flat dotted field names

This is the usual parser mismatch.

The writer uses `set(payload, { merge: true })` with keys like `` `byFeature.${feature}.calls` ``. Firebase Admin `set`+merge does **not** expand dots (only `update()` does), so Firestore stores **literal top-level field names**:

```
byFeature.common_uses.calls
byFeature.common_uses.promptTokens
byFeature.common_uses.outputTokens
byFeature.common_uses.estimatedCostMicros
byFeature.common_uses.unpricedCalls    // only if that feature had an unpriced model
```

There is **no** nested `byFeature` map on disk. A parser that does `doc.byFeature[name].calls` will see empty.

Feature id is the segment after `byFeature.` and before the last `.metric`. Ids are snake_case (`common_uses`, not `commonUses`).

Per-feature metrics match the top-level names exactly:

- `calls`
- `promptTokens`
- `outputTokens`
- `estimatedCostMicros`
- `unpricedCalls` (optional)

Suggested parse:

```
tokens = promptTokens + outputTokens
estUsd = estimatedCostMicros / 1_000_000

for each key matching
  /^byFeature\.(.+)\.(calls|promptTokens|outputTokens|estimatedCostMicros|unpricedCalls)$/
    group by feature id
```

Treat missing numbers as **0**. Do not require every feature or `unpricedCalls`.

---

## Example documents

`_product` and a user doc have the **same schema**; only the path differs. `updatedAt` is a Firestore Timestamp. These examples are reconstructed from the writer (live values will differ).

### `llmUsage/_product/periods/day_2026-09-29`

```json
{
  "calls": 47,
  "promptTokens": 18240,
  "outputTokens": 3910,
  "estimatedCostMicros": 15234,
  "updatedAt": "2026-09-29T06:12:03.184Z",
  "byFeature.common_uses.calls": 20,
  "byFeature.common_uses.promptTokens": 9100,
  "byFeature.common_uses.outputTokens": 1800,
  "byFeature.common_uses.estimatedCostMicros": 8430,
  "byFeature.contextual_gloss.calls": 18,
  "byFeature.contextual_gloss.promptTokens": 6200,
  "byFeature.contextual_gloss.outputTokens": 1400,
  "byFeature.contextual_gloss.estimatedCostMicros": 4120,
  "byFeature.sense_fit.calls": 9,
  "byFeature.sense_fit.promptTokens": 2940,
  "byFeature.sense_fit.outputTokens": 710,
  "byFeature.sense_fit.estimatedCostMicros": 2684
}
```

### `llmUsage/{uid}/periods/week_2026-W40` (sparse)

After only `span_gloss`, including one unpriced-model call:

```json
{
  "calls": 3,
  "promptTokens": 1200,
  "outputTokens": 180,
  "estimatedCostMicros": 0,
  "unpricedCalls": 1,
  "updatedAt": "2026-09-29T06:12:03.184Z",
  "byFeature.span_gloss.calls": 3,
  "byFeature.span_gloss.promptTokens": 1200,
  "byFeature.span_gloss.outputTokens": 180,
  "byFeature.span_gloss.estimatedCostMicros": 0,
  "byFeature.span_gloss.unpricedCalls": 1
}
```

Some Firestore / Studio readers flatten or list keys exactly like this. If a snapshot API returns a nested map instead, it is a client-side reconstruction — the writer did not write a nested `byFeature` object.

---

## Feature ids

Currently registered in `services/llm-gateway/src/features/index.ts` (`FEATURE_NAMES`):

| Feature id |
| --- |
| `common_uses` |
| `contextual_gloss` |
| `sense_fit` |
| `dialogue_nuance` |
| `span_gloss` |
| `span_breakdown` |
| `grammar_usage` |

**Treat as an open set.** A new feature is a gateway deploy (`src/features/<name>.ts` plus register in `index.ts`). The writer passes the request `feature` string through after an allowlist check, so unknown names cannot appear until registered, but a reader should not hard-fail on a new key.

iOS-only local history features (`tokenizer`, `registerLadder`, `verbCombo`) do **not** hit this collection.

---

## Increment / merge rules

- One successful generate increments **day + week + month** for **uid and `_product`**.
- All counters use `FieldValue.increment`. First write on a missing field starts at `0 + delta`.
- Writes use `set(..., { merge: true })`. Omitted fields are left alone. Nothing is zeroed or reset at period boundaries. A new period id is a new document.
- **Totals (increment):** `calls`, `promptTokens`, `outputTokens`, `estimatedCostMicros`, `unpricedCalls`, and the matching `byFeature.<id>.*` fields.
- **Last-write:** `updatedAt` only.
- **Sparse:** a `byFeature.<id>.*` group appears only after that feature has succeeded at least once in that period.
- `unpricedCalls` (top-level and per-feature) is omitted entirely until an unknown model is used. `estimatedCostMicros` is still incremented by `0` on those calls.
- Write failures are logged and do **not** fail the generate response.

---

## Stable vs do-not-use

**Hard-code these (stable):**

- Paths, UTC period ids, ISO week rule
- Split `promptTokens` / `outputTokens` (never `tokens` / `totalTokens`)
- Cost as `estimatedCostMicros` (never USD on the doc)
- Flat `byFeature.<featureId>.<metric>` field names
- Metric names: `calls`, `promptTokens`, `outputTokens`, `estimatedCostMicros`, optional `unpricedCalls`
- `updatedAt`
- Open feature-id set

**Not on Firestore** (HTTP API only — `GET /v1/usage` and `GET /v1/usage/features`):

- `period`, `periodKey`
- `estimatedCostUSD` (micros converted to dollars)
- `hasUnpriced` (`unpricedCalls > 0`)
- Nested `byFeature` maps / ranked `features[]`

That HTTP reader looks at `data.byFeature`, which these `set`+merge docs do not have. Do not use the HTTP aliases as the Firestore parser.

**No planned renames.** Do not wait for `tokens`, `totalTokens`, or `estimatedUsd` aliases. Do not change the writer to nested maps without a dual-read: existing docs are flat dotted keys.

---

## Pricing (for interpreting micros)

Same published Gemini rates as iOS `GeminiPricing`. Unknown models report no cost (`costMicros = 0` and `unpricedCalls += 1`).

| Model | Input / 1M | Output / 1M |
| --- | --- | --- |
| `gemini-2.5-flash` | $0.30 | $2.50 |
| `gemini-2.5-flash-lite` | $0.10 | $0.40 |
| `gemini-3.1-flash-lite` | $0.25 | $1.50 |
| `gemini-3.6-flash` (before 2027-01-01 UTC) | $0.75 | $3.75 |
| `gemini-3.6-flash` (on/after 2027-01-01 UTC) | $1.50 | $7.50 |

`usdToMicros(usd) = Math.round(usd * 1_000_000)`.

---

## Feedback stats (`llmFeedbackStats`)

Sentiment counters are a separate collection from `llmUsage`. The writer is `services/llm-gateway/src/feedback.ts`. It uses the same period ids and the same `set(merge)` dotted-field rule.

Paths:

```
llmFeedbackStats/_product/periods/{periodId}
llmFeedbackStats/{firebaseUid}/periods/{periodId}
```

`periodId` is `day_YYYY-MM-DD`, `week_YYYY-Www`, or `month_YYYY-MM`, identical to usage.

### Flat dotted field names

Admin `set`+merge does **not** expand dots. Stored keys are literal top-level names, not a nested `byFeature` map:

```
up
down
byFeature.span_gloss.up
byFeature.span_gloss.down
updatedAt
```

A reader that does `doc.byFeature[name].up` will see empty. Parse:

```
/^byFeature\.(.+)\.(up|down)$/
```

Feature id is the segment after `byFeature.` and before `.up` or `.down`. Ids are snake_case (`span_gloss`, not `spanGloss`). Treat the set as open, same as usage.

Do **not** fold `up` / `down` into the usage parser's `BY_FEATURE_FIELD_RE` (that pattern is calls and tokens only). A separate regex keeps a vote from looking like a broken usage row.

**No planned rename** to a nested `byFeature` map.

Totals `up` and `down` are incremented once per accepted vote (create only). A reason-chip update does not increment. A retry of the same `requestId` does not increment.

Studio can read these with the same Firebase Admin client it uses for `llmUsage` (`getUsageFirestore()`, project `shizen-b453f`). One doc get per period. Security rules deny the iOS client; they do not apply to the Admin SDK. The Studio service account needs read on `llmFeedbackStats/**` for sentiment. Read on `llmFeedback/**` is only for a thumbs-down queue, which is not part of the usage aggregate.

### Vote documents (`llmFeedback`)

```
llmFeedback/{requestId}
```

`requestId` is the document id (one create, then the rating is immutable).

| Field | When |
| --- | --- |
| `rating` | `up` or `down` |
| `reason` | optional, down only: `wrong_meaning`, `not_about_sentence`, `confusing` |
| `feature`, `model`, `requestId`, `uid` | every vote |
| `createdAt`, `expiresAt` | every vote |
| `input`, `result` | every down, and about 1 in 10 ups |

`expiresAt` is `createdAt` + `LLM_FEEDBACK_RETENTION_DAYS` (default 90). Enable a Firestore TTL policy on collection group `llmFeedback`, field `expiresAt`, so payload docs (learner sentences from nuance and tutor context) do not become a standing corpus. Stats period docs have no sentence text and are not TTL'd.

```bash
gcloud firestore fields ttls update expiresAt \
  --collection-group=llmFeedback \
  --enable-ttl \
  --project=shizen-b453f
```

Hourly caps live in `llmFeedbackRate/{uid}/hours/{YYYY-MM-DDTHH}` and `llmFeedbackRate/device_{hash}/hours/...`. Clients cannot read them (no matching allow rule). They are not a Studio surface.

---

## Lesson feedback (`lessonFeedback`, `lessonFeedbackStats`)

Writer: `recordLessonFeedback` in `services/llm-gateway/src/lesson-feedback.ts`, behind `POST /v1/lesson-feedback`. iOS asks on a sample of finished dialogue scenes for 1–5 ratings. It is not tied to a generate call, so there is no feedback token.

Dimensions (open set, same advice as feature ids): `audio`, `content`, `highlighting` (word highlighting synced to audio), `quiz`. Every dimension is optional, and each request has at least one.

`sceneKey` is `${collectionId}__${scenarioId}`. `scenarioId` is the Studio scene slug, so it matches `/content/dialogues/{collectionId}/{scenarioSlug}`. The writer rejects ids containing `/` or `__`.

### Rating documents

```
lessonFeedback/{attemptId}
```

`attemptId` is a client UUID. A retry of the same attempt is a no-op.

| Field | When |
| --- | --- |
| `uid`, `sceneKey`, `collectionId`, `scenarioId` | every rating |
| `ratings` | nested map, e.g. `{ "audio": 4, "quiz": 2 }` (this is a real map: it is written with `set`, not dotted keys) |
| `score` | nested map `{ correct, total, stars }` |
| `publishedVariantId`, `publishedContentHash` | when the scene had a published take |
| `englishPeeks`, `appVersion`, `deviceHash` | optional |
| `createdAt`, `expiresAt` | every rating; `expiresAt` uses `LLM_FEEDBACK_RETENTION_DAYS` |

Studio lists recent ratings for one scene with `where("sceneKey", "==", key).orderBy("createdAt", "desc")`. That needs the composite index in `firestore.indexes.json`. Add a TTL policy on `lessonFeedback.expiresAt` the same way as `llmFeedback`.

### Stats documents

```
lessonFeedbackStats/{sceneKey}
lessonFeedbackStats/_product
```

No periods: these are all-time totals per scene. Same literal dotted field names as usage (`set`+merge):

```
count                  // accepted rating requests
audio.sum              // sum of 1–5 values
audio.n                // number of audio ratings
audio.h1 … audio.h5    // histogram
content.* / highlighting.* / quiz.*
collectionId, scenarioId   // scene docs only, plain strings
updatedAt
```

Average for a dimension is `sum / n`. Treat missing numbers as 0. A histogram bucket appears only after its first rating.

Hourly caps: `lessonFeedbackRate/{uid}/hours/{YYYY-MM-DDTHH}` (20 per hour). Not a Studio surface.
