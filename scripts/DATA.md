# Data files

Some large data files are not tracked in git. Generate them locally before building.

## JMdict (`shizen/jmdict.sqlite`)

The iOS app bundles `shizen/jmdict.sqlite` for dictionary lookup. It is built from the public [JMdict](https://www.edrdg.org/jmdict/j_jmdict.html) dataset (~85 MB).

```bash
python3 scripts/build_jmdict.py
```

This downloads `JMdict_e.xml` (if missing) and writes `shizen/jmdict.sqlite`. Re-run after updating the source XML.

### Adding words JMdict lacks

`scripts/jmdict_supplement.tsv` (tracked) holds Shizen's own rows; the build merges them after JMdict. To find what's missing:

1. In a debug build, open **Settings → Dictionary coverage**. It runs every lesson line through the same tokens and lookup a token tap uses and lists words with no callout (no entry, or a kana hit the app rejects) and weak matches (tail-trim / prefix guesses).
2. **Share review CSV** for the full list, or **Copy supplement rows** to get paste-ready TSV rows with the reading filled in.
3. Paste into `jmdict_supplement.tsv`, fill in `glossary` (and `tags`), and re-run `python3 scripts/build_jmdict.py`. Rows left without a glossary are skipped.

## Kanjidic (`shizen/kanjidic.sqlite`)

Kanjidic (~1 MB) is tracked in git and ships with the app as-is.

## API keys (iOS app)

Gemini, OpenAI, and the Studio content-QA client token are not in git. For local development:

1. Copy `shizen/Secrets.plist.example` to `shizen/Secrets.plist` and fill in your keys, **or**
2. Set `GEMINI_API_KEY`, `OPENAI_API_KEY`, and `CONTENT_QA_CLIENT_TOKEN` in the **shizen** Xcode scheme (Run → Arguments → Environment Variables).

`CONTENT_QA_CLIENT_TOKEN` is sent as `Authorization: Bearer` on scene check-off calls. Public lesson fetches stay unauthenticated.

If you previously committed keys, rotate them in the provider consoles before reuse.
