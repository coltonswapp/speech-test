# Compound Meaning Game (POC)

Throwaway experiment: see two kanji → guess the English compound meaning → get a hand-authored closeness rank → unlock component hints → reveal literal breakdown + stub dialogue.

## How to open

1. Run the **shizen** app (branch `japanese`).
2. Open **Settings** (gear on the main screen → `SavedGenerationsViewController`).
3. Under the debug / experiments list, tap **Compound meaning**.

Files live under `shizen/Experiments/CompoundMeaning/`. The Xcode project uses a synchronized `shizen` root group, so new files here are picked up automatically (no `pbxproj` edit).

## Loop

1. Board shows the compound kanji. Type an English gloss. Default `maxGuesses = 6`.
2. Each guess gets an integer rank (`1` = exact / accepted gloss). Color bands from knobs.
3. After guess 3: unlock component A (gloss + readings). After 4: unlock B.
4. Optional commit interstitial (`読 + 書 → ?`) after `commitAfterGuess`.
5. Reveal: kanji · reading · gloss + literal blurb. On a miss, also shows best rank.
6. Stub dialogue line on reveal. `audioPayoff` defaults to `false` (no TTS).

## Knobs

Edit defaults in `CompoundMeaningPuzzles.json`, or tap the **slider** button in the nav bar while playing.

| Knob | Default | Notes |
| --- | --- | --- |
| `maxGuesses` | 6 | Tries before forced reveal |
| `unlockComponentAAfterGuess` | 3 | Show first character hint |
| `unlockComponentBAfterGuess` | 4 | Show second character hint |
| `showCommitInterstitial` | true | `A + B → ?` beat |
| `commitAfterGuess` | 5 | When interstitial appears |
| `audioPayoff` | false | Flag only — TTS not wired |
| `colorBands` | JSON | Edit hex/`maxRank` in JSON |

Knob overrides from the in-app sheet persist in `UserDefaults` (`CompoundMeaningKnobsOverride`). Use **Reset knobs to JSON defaults** in the sheet to clear.

## Content

Five hardcoded literal-aha puzzles in the JSON (skip “liar” compounds like 子供):

- 読書 · 火山 · 手紙 · 告白 · 入口

Ranks / synonyms / near-misses are hand-authored — **no embeddings API**.

## Play again

Reveal → **Play again** advances to the next puzzle (wraps).

## Non-goals

Daily/streaks/accounts/share/analytics/big content pack/onboarding/embeddings/deep dissect integration.
