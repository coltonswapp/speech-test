# PRD: Reading format (read-along)

**Status:** Product-locked (2026-09-10). Build when prioritized — not necessarily month MVP.  
**Repo:** `coltonswapp/speech-test` (monorepo: `webapp/` Studio + `shizen/` iOS)  
**Owner context:** Colton / Hitomi. Engineering handoff for a local Cursor agent.

---

## Problem

Learners need a **read-along** mode: a story or informational piece is **spoken by a single narrator** while JP text is on screen so they can practice reading. This is not conversational A/B dialogue, but it should live in the same content pipeline (CMS → publish → app).

Inferring “Reading” from “only one speaker” is wrong — one-speaker can still be real dialogue (voicemail, announcement, phone call).

## Goal

Ship an explicit scenario property:

```ts
format: "dialogue" | "reading"  // default: "dialogue"
```

When `format === "reading"`:

1. **Studio / TTS** uses a **single-voice** generate path (still with **per-spoken-line alignment** / `lineSwitchSeconds`).
2. **iOS** uses **Reading chrome**: narrator-oriented presentation, **Follow text on by default**, **hide Practice as B** / role-play.
3. Same spoken-line content model, quiz, and (optional) spoken-evidence links as dialogue.

## Non-goals (v1)

- New line types (`monologue` / `explain` rows) — **reuse spoken (+ stage) lines**.
- Inferring format from speaker count.
- Continuous paragraph/story layout redesign (chat/transcript chrome is OK for v1 if karaoke + follow-along work).
- Faking a silent `speaker2` to satisfy Gemini multi-speaker.
- Gating unit completion on Practice as B for Reading items.
- Requiring Reading for month MVP.

## Product rules (locked)

| Rule | Detail |
|------|--------|
| Explicit flag | `format` on the **scenario** (not inferred). |
| Default | `"dialogue"`. |
| Sanity check | Reading **should** have **one** cast voice; warn in Studio if 0 or 2+. Still do not auto-flip format. |
| Labeling | Surface as **Reading** in app/Studio, not “Dialogue”. |
| Completion | Listen (+ optional quiz / “Heard enough”). No Practice as B. |
| Chrome | Follow text / karaoke highlight natural; Follow text **default on** for Reading. |

## Data model

### Scenario

Add to dialogue scenario schema (Zod + DB jsonb / export / CMS decode):

- `format?: "dialogue" | "reading"` — omit or `"dialogue"` = current behavior.

Round-trip through:

- `webapp/lib/dialogue/types.ts` (scenario schemas + patch)
- DB scenario row / export (`webapp/lib/dialogue/export.ts`)
- Public CMS / content APIs
- iOS `DialogueScenarioCollection` decode → scenario model field

### Cast / TTS project

- Reading: **one** cast voice entry; `speaker1Name` + `speaker1Voice` (or narration-equivalent single voice).
- Do **not** require `speaker2Voice` when `format === "reading"`.
- Spoken lines: all (or overwhelmingly) the narrator’s `speaker` name; stage lines still allowed; inline-question optional but not required.

### Alignment

- Keep **spoken-only** index space (skip stage / inline-question), same as today.
- Generate must still produce usable **per-line** timing (`lineSwitchSeconds` / variant sentence ranges) so follow-along + karaoke can work.
- Token sync remains optional Studio stamp pass (line-level highlight OK if token sync absent).

## Studio (`webapp/`)

1. Scenario editor: control to set **Format = Dialogue | Reading** (default Dialogue).
2. When Reading:
   - Cast UI: single voice; validate/warn if not exactly one.
   - Audio generate: **single-voice path** keyed off `format` (Gemini single-speaker and/or existing OpenAI narration patterns — pick what fits per-line alignment best; **do not** call multi-speaker with a dummy B).
3. Quiz editor / generate-quiz / spoken evidence: unchanged; still valid on Reading.
4. Export + PATCH must persist `format`.

### Known TTS constraint today

Scenario-backed projects currently force `compositionMode: "conversation"` and `generateConversation` errors without both voices (`Select a voice for both speakers`). Reading must branch before that requirement.

## iOS (`shizen/`)

1. Decode `format` on scenario.
2. When `format == .reading` (or equivalent):
   - Reading labeling in menus / chrome where scenario type is shown.
   - **Hide** Practice as B / role-play entry points.
   - **Follow text / token-sync highlight default on** for this scenario (override or seed from format; don’t fight user prefs awkwardly — product: default on for Reading sessions).
   - Prefer narrator-oriented layout (one-sided bubbles OK for v1).
3. Reuse existing:

   - `FuriganaTranscriptLabel` / `JapaneseFuriganaBuilder`
   - Token-sync karaoke (`DialogueTokenSync`, highlight during playback)
   - Follow-along scroll in `DialogueExperimentViewController`
   - Nested listen → quiz pager (`DialogueNestedPagingExperimentViewController`) — completion without role-play already possible when quiz empty / listen finish

4. Quiz spoken evidence (`sourceSpokenStart` / `sourceSpokenEnd`) works with one speaker — no change required beyond decode.

## Acceptance criteria

**Studio**

- [ ] Can set `format: reading` on a scenario; save/reload/export preserves it.
- [ ] Default / omitted `format` behaves as dialogue.
- [ ] Reading generate succeeds with **one** voice and produces multi-line alignment (not one blob with no line switches unless explicitly documented as interim).
- [ ] Dialogue generate still requires two voices as today.
- [ ] Studio warns if Reading cast ≠ 1 voice (does not silently convert format).

**iOS**

- [ ] Reading scenario: no Practice as B / role-play affordance.
- [ ] Follow text / karaoke-style highlight available; default on for Reading.
- [ ] Furigana JP visible; audio + line timing drive follow-along.
- [ ] Optional quiz + spoken evidence still work.
- [ ] Dialogue scenarios unchanged.

**QA path**

1. Create/publish a short Reading scenario (one narrator, 5–10 spoken lines) in Studio; generate audio; stamp line switches (and tokens if easy).
2. Open in app nested dialogue flow → confirm Reading chrome, full listen, no B practice.
3. Control: a one-speaker **dialogue** scenario (e.g. voicemail) with `format: dialogue` still shows dialogue chrome / B if applicable.

## Implementation notes for the agent

- Prefer **path-pure** changes: schema + Studio editor/TTS branch + iOS decode/chrome. Avoid unrelated WIP.
- Do **not** stash-pop unrelated branches.
- Match existing patterns in `types.ts`, scenario editor, audio ensure/variants routes, `DialogueScenarioCollection`.
- Paste-ready commits: batch when a coherent chunk is ready; don’t spam tiny commits unless asked.

## Open / follow-ups (out of v1)

- Continuous paragraph reading layout (less bubble-chat).
- Dedicated Reading shelf in home IA (may be product copy + filter on `format`).
- Gemini single-speaker vs OpenAI narration — choose during implement based on alignment quality.

## References (code)

- `webapp/lib/dialogue/types.ts` — scenario / line schemas
- `webapp/lib/tts/scenario-conversation.ts`, `gemini-tts.ts`, `app/api/tts/projects/[id]/variants/route.ts` — TTS
- `webapp/components/dialogue/scenario-editor.tsx` — Studio UI
- `shizen/Dialogue/DialogueScenarioCollection.swift` — CMS decode
- `shizen/Experiments/DialogueExperimentViewController.swift` — furigana, karaoke, follow-along
- `shizen/Experiments/DialogueNestedPagingExperimentViewController.swift` — pager / quiz / completion
