# Data files

Some large data files are not tracked in git. Generate them locally before building.

## JMdict (`shizen/jmdict.sqlite`)

The iOS app bundles `shizen/jmdict.sqlite` for dictionary lookup. It is built from the public [JMdict](https://www.edrdg.org/jmdict/j_jmdict.html) dataset (~85 MB).

```bash
python3 scripts/build_jmdict.py
```

This downloads `JMdict_e.xml` (if missing) and writes `shizen/jmdict.sqlite`. Re-run after updating the source XML.

## Kanjidic (`shizen/kanjidic.sqlite`)

Kanjidic (~1 MB) is tracked in git and ships with the app as-is.

## API keys (iOS app)

Gemini and OpenAI keys are not in git. For local development:

1. Copy `shizen/Secrets.plist.example` to `shizen/Secrets.plist` and fill in your keys, **or**
2. Set `GEMINI_API_KEY` and `OPENAI_API_KEY` in the **shizen** Xcode scheme (Run → Arguments → Environment Variables).

If you previously committed keys, rotate them in the provider consoles before reuse.
