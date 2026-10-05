# Dump / apply (Studio operators)

Hana’s mapping rules live in [`README.md`](./README.md). This file only covers generating dumps and applying approved mappings.

## Current dump in-repo

`patterns.json` and `collections/*.json` were generated from Studio’s API by Hana (not via `DATABASE_URL` / the local dump script). Counts at last refresh: **173** patterns, **32** collections, **149** scenes. N4/N3 labels will mostly orphan until more catalog entries exist.

## Regenerating (optional)

From `webapp/` with Studio DB credentials:

```bash
# DATABASE_URL must be set (usually via .env.local)
cd webapp
pnpm db:grammar-backfill-dump
# or:
pnpm dotenv -e .env.local -- tsx scripts/grammar-backfill-dump.ts
```

Writes:

- `../grammar-backfill/patterns.json` — full Pattern library (`id`, `label`, `shortMeaning?`, `formNote?`)
- `../grammar-backfill/collections/<collectionId>.json` — one file per **active** collection (all scenes)

## Collection dump shape

Spoken lines only (0-based `i`; stage / inline-question rows excluded):

```json
{
  "collectionId": "dinner-out",
  "scenes": [
    {
      "sceneId": "getting-to-know-emi",
      "title": "Getting to know Emi",
      "spokenLines": [{ "i": 0, "text": "…", "speaker": "A" }],
      "grammar": [{ "label": "〜ましょう" }]
    }
  ]
}
```

## Apply an approved mapping

```bash
cd webapp
pnpm dotenv -e .env.local -- tsx scripts/grammar-backfill-apply.ts --mapping ../grammar-backfill/mappings/<slug>.json
# dry-run:
pnpm dotenv -e .env.local -- tsx scripts/grammar-backfill-apply.ts --mapping ../grammar-backfill/mappings/<slug>.json --dry-run
```

Apply writes `patternId` + `sourceSpokenStart` / `sourceSpokenEnd` onto matching scene grammar highlights (matched by existing `label`, same order). It does **not** create Pattern catalog rows. Orphan / ambiguous mapping rows are skipped (see script output).
