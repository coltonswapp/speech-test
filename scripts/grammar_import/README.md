# Grammar import (build-time)

Imports JLPT N5 grammar from [JLPT Sensei](https://jlptsensei.com) into draft JSON for editorial review. **Not used at runtime.**

## Requirements

- Python 3.9+
- Network access when fetching live pages

## Fetch full N5 list

```bash
cd scripts/grammar_import
python3 import.py --output ../../shizen/Resources/Grammar/n5.grammar.json
```

Options:

- `--limit 5` — smoke test on first five pages
- `--merge-existing` — keep hand-authored points in the output file when IDs match
- `--html-dir ./cached` — parse local `*.html` files instead of HTTP
- `--delay 1.5` — polite delay between requests

## After import

1. Rewrite `formation` and `usage` blocks in Shizen voice (importer placeholders are intentional).
2. Trim examples to 3–5 per point; fix `targetSubstring` for spot-grammar drills.
3. Review auto-generated `drills` distractors.
4. Run lint output from the script; fix errors before committing.
5. Keep the hand-authored `checkpoints` array in sync when adding or reordering points (each point must belong to exactly one checkpoint).

See [ATTRIBUTION.md](../../shizen/Resources/Grammar/ATTRIBUTION.md) for redistribution notes.

## Content pipeline (per-point files)

Editorial workflow uses one JSON file per grammar point under `content/n5/points/`, plus `content/n5/checkpoints.json`. Review and generate in **Shizen Studio** (`webapp/`).

### Split bundled curriculum into per-point files

```bash
python3 scripts/grammar_import/split_curriculum.py
```

### Merge approved points back into the app bundle

```bash
python3 scripts/grammar_import/merge_curriculum.py
```

Or via the Swift executable in GrammarContentKit:

```bash
swift run --package-path GrammarContentKit merge-grammar-content content/n5 shizen/Resources/Grammar/n5.grammar.json
```

Merge patches **approved point IDs only** into `n5.grammar.json` (upsert by `id`). Existing bundle points and checkpoints stay in place; unapproved drafts are not removed. Approve explicitly in Shizen Studio (Queue → Approve); staged points appear under the **Staging** tab before merge.

Split assigns `"status": "draft"` by default. To reset an existing library:

```bash
python3 scripts/grammar_import/reset_status.py --status draft
```
