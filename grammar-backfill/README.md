# Grammar backfill — mapping instructions

You are proposing mappings, not editing content. Read `collections/<slug>.json` and `patterns.json`, then write one `mappings/<slug>.json` per collection. Never write to Studio. Hana reviews every file and applies the approved ones.

## What you're mapping

Each scene has grammar highlights stored as labels (`{"label": "〜ましょう"}`). For each label, you'll:

1. Pick the matching pattern `id` from `patterns.json`.
2. Find the spoken line or lines where a learner actually hears that pattern, and record the inclusive range.

## Line indices

- `spokenLines[].i` is 0-based and counts spoken lines only. Stage lines are never in the dump.
- `sourceSpokenStart` and `sourceSpokenEnd` are inclusive. A pattern on one line uses the same number for both.
- Pick the clearest single line where the pattern is said. Use a multi-line range only when the pattern is split across lines.
- If the pattern shows up on more than one line, pick the one where it's clearest or most central to the scene, set `ambiguous: true`, and list the other indices in `note`.

## Matching rules

- Match on meaning and form, not exact string. 〜ましょうか matches a 〜ましょうか pattern if one exists. Otherwise it matches 〜ましょう with a note.
- Every pattern you map has to appear in a spoken line. If a label doesn't appear in any line, set `orphan: true`, leave `patternId` null, and say why in `note` ("not in any spoken line").
- If a label has no catalog entry, set `orphan: true`, leave `patternId` null, and put a suggested label and one-line meaning in `note`. Do not invent catalog ids.
- Labels should be single patterns with no slashes. If you see a slash pair, flag it as `ambiguous` and don't split it yourself.
- Don't add highlights the scene doesn't already have, and don't remove any. One item per existing label, in the same order.
- Don't write meanings or explanations onto the scene. Meaning lives in `patterns.json`.

## Output shape

```json
{
  "collectionId": "dinner-out",
  "scenes": [
    {
      "sceneId": "getting-to-know-emi",
      "items": [
        {
          "label": "〜をください",
          "patternId": "wo-kudasai",
          "sourceSpokenStart": 0,
          "sourceSpokenEnd": 0,
          "orphan": false,
          "ambiguous": false,
          "note": null
        }
      ]
    }
  ]
}
```

Include every scene in the collection, even ones with no grammar labels (use `"items": []`).

## When you're done

At the end of each run, write `mappings/_summary.md` listing:

- collections mapped
- total items, orphans, and ambiguous items
- every orphan as `collection / scene / label / reason`, all in one list, because Colton decides on orphans
