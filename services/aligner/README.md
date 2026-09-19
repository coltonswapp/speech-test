# shizen-aligner

Forced alignment of a known Japanese script to a TTS take. torchaudio
`MMS_FA` (wav2vec2 CTC, 20 ms frames at 16 kHz) plus pykakasi romanization.
Ported from `docs/karaoke-autotiming/align_mms.py`; numerics are identical so
the eval harness stays comparable. Ticket KA-2.

## API

`POST /align` — `Authorization: Bearer $ALIGNER_TOKEN`

```json
{
  "audioUrl": "https://…signed R2 URL of the full untrimmed WAV…",
  "lines": [
    { "text": "三〇二のカイトです", "tokens": [
      { "text": "三〇二", "reading": "さんまるに" },
      { "text": "の" }, { "text": "カイト" }, { "text": "です" } ] }
  ]
}
```

```json
{
  "alignerVersion": "mms-fa-v1",
  "durationSeconds": 39.4,
  "sampleRate": 24000,
  "lines": [ { "score": 0.81, "tokens": [
    { "startSeconds": 1.24, "endSeconds": 1.62, "score": 0.9, "readingFallback": false } ] } ],
  "timings": { "fetchSeconds": 0.1, "alignSeconds": 2.3 }
}
```

- Times are in full-WAV seconds (same domain as the Studio playhead). Any
  input sample rate is accepted; audio is resampled to 16 kHz internally.
- `reading` is a kana reading of the surface. When present and kana it is
  used verbatim; otherwise the override table then pykakasi on the surface
  are used and `readingFallback` is `true`.
- `score` is the mean CTC posterior per token. It does **not** predict error
  (see the design doc) — use it only for `script-mismatch` style line checks.
- Errors: `401` bad token, `413` audio over 64 MiB, `422` undecodable audio
  or script longer than the audio, `502` audio fetch failed.

`GET /healthz` is unauthenticated.

## Local

```sh
python -m venv .venv && .venv/bin/pip install -r requirements.txt
ALIGNER_TOKEN=local-dev-token .venv/bin/uvicorn aligner.app:app --port 8766
.venv/bin/python tests/test_core.py
.venv/bin/python tests/verify_gold.py <proto_dir>   # see docstring
```

## Deploy (Modal)

```sh
pip install modal && modal token new                      # once per machine
modal secret create shizen-aligner ALIGNER_TOKEN=$(openssl rand -hex 24)
modal deploy modal_app.py                                 # prints the URL
```

Then in Vercel set `ALIGNER_URL` to the printed `…modal.run` URL and
`ALIGNER_TOKEN` to the same secret. Model weights are baked into the image
at build time; the container scales to zero after 5 min idle and a cold
start is roughly 10–20 s. `modal serve modal_app.py` gives a hot-reloading
dev URL.

Not yet handled (later tickets): chunking takes over ~90 s at VAD sentence
bounds, and per-line windowed alignment.
