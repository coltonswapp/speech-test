"""Prototype: forced-align a known Japanese script to take audio with torchaudio MMS_FA
(wav2vec2 CTC, 20 ms frames) and emit a tokenSync-shaped prediction.

Modes:
  whole     : one CTC pass over the full take; line boundaries fall out of alignment.
  windowed  : per-line pass inside human line marks (simulates constructed per-line audio).

Output: pred JSON {sceneId: {"lines":[{"text","tokens":[{"text","startSeconds","score"}]}],
                              "lineStarts":[...], "lineScores":[...]}}
"""
import json, re, sys, glob, os
import numpy as np, soundfile as sf, torch, torchaudio
import pykakasi

kks = pykakasi.kakasi()
ROMAJI_OVERRIDES = {"三〇二": "sanmaruni", "302": "sanmaruni", "はいー": "haii", "ー": ""}


def romanize(surface: str) -> str:
    if surface in ROMAJI_OVERRIDES:
        return ROMAJI_OVERRIDES[surface]
    out = "".join(item["hepburn"] for item in kks.convert(surface))
    out = out.lower().replace("-", "").replace("’", "'")
    out = re.sub(r"[^a-z']", "", out)
    return out or "a"


bundle = torchaudio.pipelines.MMS_FA
model = bundle.get_model(with_star=False).eval()
dictionary = bundle.get_dict(star=None)
SR = bundle.sample_rate  # 16000


def emission_for(wave: np.ndarray):
    with torch.inference_mode():
        em, _ = model(torch.from_numpy(wave).float().unsqueeze(0))
    return em[0]  # (frames, vocab)


def align_words(em, words):
    """words: list of romaji strings. Returns per-word (start_frame, end_frame, mean_score)."""
    ids, owner = [], []
    for wi, w in enumerate(words):
        for c in w:
            if c in dictionary:
                ids.append(dictionary[c]); owner.append(wi)
    targets = torch.tensor([ids], dtype=torch.int32)
    ali, scores = torchaudio.functional.forced_align(em.unsqueeze(0), targets, blank=0)
    spans = torchaudio.functional.merge_tokens(ali[0], scores[0].exp())
    # spans are in emitted-token order == ids order
    out = [None] * len(words)
    for k, sp in enumerate(spans):
        wi = owner[k]
        if out[wi] is None:
            out[wi] = [sp.start, sp.end, [sp.score]]
        else:
            out[wi][1] = sp.end; out[wi][2].append(sp.score)
    return [(s, e, float(np.mean(sc))) if v else (0, 0, 0.0) for v in out for (s, e, sc) in [v or (0, 0, [0.0])]]


def frames_to_seconds(frame, n_frames, n_samples):
    return frame * (n_samples / n_frames) / SR


def run_scene(wave, lines, mode, marks=None):
    n = len(wave)
    pred_lines, line_starts, line_scores = [], [], []
    if mode == "whole":
        em = emission_for(wave)
        words = [romanize(t["text"]) for l in lines for t in l["tokens"]]
        spans = align_words(em, words)
        k = 0
        for l in lines:
            toks = []
            for t in l["tokens"]:
                s, e, sc = spans[k]; k += 1
                toks.append({"text": t["text"], "startSeconds": round(frames_to_seconds(s, em.shape[0], n), 3),
                             "endSeconds": round(frames_to_seconds(e, em.shape[0], n), 3), "score": round(sc, 3)})
            pred_lines.append({"text": l["text"], "tokens": toks})
            line_starts.append(toks[0]["startSeconds"]); line_scores.append(float(np.mean([t["score"] for t in toks])))
    else:  # windowed on given marks
        bounds = [0.0] + list(marks) + [n / SR]
        for li, l in enumerate(lines):
            lo, hi = int(bounds[li] * SR), int(bounds[li + 1] * SR)
            seg = wave[lo:hi]
            em = emission_for(seg)
            words = [romanize(t["text"]) for t in l["tokens"]]
            spans = align_words(em, words)
            toks = []
            for t, (s, e, sc) in zip(l["tokens"], spans):
                toks.append({"text": t["text"], "startSeconds": round(bounds[li] + frames_to_seconds(s, em.shape[0], len(seg)), 3),
                             "endSeconds": round(bounds[li] + frames_to_seconds(e, em.shape[0], len(seg)), 3), "score": round(sc, 3)})
            pred_lines.append({"text": l["text"], "tokens": toks})
            line_starts.append(toks[0]["startSeconds"]); line_scores.append(float(np.mean([t["score"] for t in toks])))
    return {"lines": pred_lines, "lineStarts": line_starts, "lineScores": line_scores}


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "whole"
    gold = json.load(open("gold/gold.json"))
    pred = {}
    for scene_id, ts in gold.items():
        slug = scene_id.split("/")[1]
        wave, sr = sf.read(f"audio/{slug}.wav", dtype="float32")
        assert sr == SR, sr
        if wave.ndim > 1:
            wave = wave.mean(axis=1)
        marks = json.load(open(f"audio/{slug}.marks.json")) if mode == "windowed" else None
        pred[scene_id] = run_scene(wave, ts["lines"], mode, marks)
        print(scene_id, "done", flush=True)
    json.dump(pred, open(f"pred_{mode}.json", "w"), ensure_ascii=False, indent=1)
