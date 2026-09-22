# Shizen learner data architecture

Source of truth for how the iOS learner app stores and syncs user data.

## Locks (read first)

1. **Firestore is canonical.** The live learner record lives only under `users/{uid}/…` in Cloud Firestore. Enable and rely on **Firestore offline persistence** for airplane mode and flaky wifi. Do **not** dual-write with on-device JSON as a long-term offline working copy; the SDK offline queue is the offline path.
2. **Must sign in.** Apple and Google only. No Continue-as-guest, no Firebase anonymous Auth, no anonymous→link. First launch requires a real account before creating any learner docs.
3. **Legacy local JSON is disposable.** Files such as `dialogue-progress.json`, kana progress files, `grammar-mastery.json`, `saved-vocabulary.json`, and onboarding UserDefaults may be ignored or deleted as stores are rewritten to Firestore. There is no forever sync with those files. Pre-Auth local data is discardable (sole current user has almost no progress).
4. **Firebase project:** learner Auth + Firestore = **`shizen-b453f`** (iOS `BUNDLE_ID` `com.swappfunc.shizen`). Studio webapp auth (`webapp/AUTH.md`, email allowlist / agent token) is a **separate** system and must stay **off** this learner tree.
5. **Canonical id** = Firebase Auth **`uid`**. Apple/Google subjects are credentials only, never document ids.

---

## Firebase project boundary

| Concern | Project / system |
| --- | --- |
| Learner Auth (Apple, Google) | `shizen-b453f` |
| Learner Firestore (`users/{uid}/…`) | `shizen-b453f` |
| Studio CMS / NextAuth allowlist | Webapp only — see `webapp/AUTH.md` |

Do not put Studio allowlist state, curator tools, or CMS catalogs under `users/{uid}`.

---

## Auth flow

1. First successful Apple or Google sign-in → Firebase Auth issues a `uid` → create `users/{uid}` and `users/{uid}/folders/inbox`.
2. Returning user / new install with the same credential → same `uid`; listen to Auth state and read/write Firestore only under that `uid`.
3. `AuthSession.swift` is currently a stub (including a guest path). It **must be replaced** with real Apple/Google → Firebase Auth. No guest path in the product flow.

Account deletion (App Store requirement: delete Auth user + wipe `users/{uid}`) is a **follow-up**, not a schema blocker.

---

## Document tree

All paths are under Firestore project `shizen-b453f`.

### `users/{uid}` — profile

| Field | Type | Notes |
| --- | --- | --- |
| `schemaVersion` | number | Start at `1`. Bump when shape changes require migration. |
| `createdAt` | timestamp | Server timestamp on create. |
| `updatedAt` | timestamp | Server timestamp on every profile write. |
| `timezone` | string | IANA timezone (e.g. `America/Los_Angeles`). Used for dialogue day keys. |
| `onboardingCompleted` | bool | Once `true`, stays `true` (sticky). |
| `level` | string \| null | Self-reported / survey level. |
| `dailyGoal` | number \| null | Daily scenario goal. |
| `survey` | map | Survey responses (question id → answers). |
| `listeningQuizAnswers` | array | Listening quiz selections from onboarding. |

**Concurrency:** profile fields are last-write-wins (LWW) on `updatedAt`, except `onboardingCompleted` which sticks once true.

### `users/{uid}/progress/dialogue`

Single document. Shape mirrors `DialogueProgressSnapshot` plus doc metadata:

| Field | Type | Notes |
| --- | --- | --- |
| `updatedAt` | timestamp | Server timestamp. |
| `completedScenarioIDs` | array of string | Union across devices. Store as arrays in Firestore (not sets). |
| `dailyProgress` | map | Key = day string in **profile timezone**; value = `{ completedScenarioIDs: string[] }`. |
| `scenarioAttempts` | map | Scenario id → array of attempts. |

**Attempt object** (extend local `DialogueScenarioAttempt`):

| Field | Type | Notes |
| --- | --- | --- |
| `starCount` | number | |
| `points` | number | |
| `at` | timestamp | Required for multi-device append + dedupe. |

**Derived, not stored:** streak is computed from daily completions.

**Day keys:** always use the profile’s IANA timezone when writing new day keys. Do **not** rewrite historical day keys when the user changes timezone.

### `users/{uid}/progress/kanaHiragana` and `…/kanaKatakana`

One document each (glyph map, not per-glyph docs). Align with `KanaProgressSnapshot`:

| Field | Type | Notes |
| --- | --- | --- |
| `updatedAt` | timestamp | Server timestamp. |
| `glyphMastery` | map | Glyph → mastery (`easeFactor`, `intervalDays`, `repetitions`, `practiceCorrectCount`, `nextReviewDate`, `lastReviewDate`). |
| `completedLessonRowIDs` | array of string | |
| `completedReviewRowIDs` | array of string | |
| `lastOpenedRowID` | string \| null | LWW on doc `updatedAt`. |

### `users/{uid}/progress/grammar`

One document. Align with `GrammarMasterySnapshot`:

| Field | Type | Notes |
| --- | --- | --- |
| `updatedAt` | timestamp | Server timestamp. |
| `records` | map | Grammar id → mastery record (`grammarId`, `masteryState`, `timesEncountered`, `firstSeenScenarioId`, `lastPracticedAt`, `correctStreak`). |

### `users/{uid}/folders/{folderId}`

| Field | Type | Notes |
| --- | --- | --- |
| `name` | string | Folder display name. |
| `createdAt` | timestamp | Server timestamp on create. |
| `updatedAt` | timestamp | Server timestamp. |
| `items` | array of maps | **Embedded** vocabulary items (v1). |

**Inbox:** always create `folders/inbox` when creating the user (`id` = `inbox`, name e.g. `Inbox`).

**Item shape** (align with `SavedVocabularyItem`, plus `updatedAt` for merge):

| Field | Type |
| --- | --- |
| `id` | string |
| `surface` | string |
| `dictionaryForm` | string \| null |
| `reading` | string \| null |
| `gloss` | string \| null |
| `sentence` | string \| null |
| `createdAt` | timestamp |
| `updatedAt` | timestamp |
| `deletedAt` | timestamp \| null | Tombstone (see Deletes). |

**Future split path** (name now, unused in v1): if an embedded folder nears the **1 MiB** document limit, migrate items to `users/{uid}/folders/{folderId}/items/{itemId}`.

---

## Sync and concurrency (Firestore-canonical)

- All durable writes go to Firestore. Offline = Firestore SDK persistence + write queue. No parallel JSON store as the working copy.
- Prefer **transactions** (or conditional writes checking `updatedAt`) for progress and folder documents so concurrent devices do not clobber.
- Use **server timestamps** for document `updatedAt`.

### Multi-device merge (both devices wrote offline, then sync)

| Data | Merge rule |
| --- | --- |
| Dialogue `completedScenarioIDs` | Union |
| Dialogue `dailyProgress` day sets | Union of scenario ids per day key |
| Dialogue `scenarioAttempts` | Append; dedupe on attempt `at` |
| Kana row id arrays | Union |
| Kana / grammar per-id records | Later `updatedAt` / field timestamp wins; else stronger mastery wins |
| Vocab items | Union by item `id`; LWW per item fields on item `updatedAt` |
| Folder rename | LWW on folder `updatedAt` |
| Folder moves | After merge, an item id must appear in at most one folder; LWW on item `updatedAt` decides which folder keeps it |

### Deletes

**Recommended:** soft-delete with **tombstones** (`deletedAt` on items; optional `deletedAt` on folders). Clients filter tombstoned rows out of UI; sync preserves the tombstone so the other device drops the item instead of resurrecting it.

Do not rely on “v1 has no cross-device delete sync” — tombstones are the chosen approach.

---

## Security rules (intent)

Entire `users/{uid}` tree:

- Read and write only when `request.auth.uid == uid`.
- Separate **create** vs **update** (create once for profile / inbox; updates thereafter).
- No public reads.
- Clients never write another user’s `uid`.

Studio webapp rules and allowlists do not grant access to this tree.

---

## Off this tree (explicit)

Keep these out of `users/{uid}/…`:

- Experiment / curator toggles
- Recent searches
- Tutor TTS audio bytes (Firebase Storage later if ever needed)
- JMDict / CMS catalogs
- Studio webapp AUTH allowlist (`webapp/AUTH.md`)

---

## Implementation notes

- Replace `AuthSession` stub; gate first-run so learner docs are created only after a real Apple/Google session.
- Rewrite local stores (`DialogueProgressStore`, `KanaProgressStore`, `GrammarMasteryStore`, `SavedVocabularyStore`, onboarding persistence) to read/write Firestore under the signed-in `uid`. Legacy files may be deleted or ignored — no ongoing bidirectional sync with them.
- Enable Firestore offline persistence in the iOS Firebase setup for `shizen-b453f`.
- Do not copy API keys or plist secrets into docs or source comments; configure via `GoogleService-Info.plist` / build settings only.
