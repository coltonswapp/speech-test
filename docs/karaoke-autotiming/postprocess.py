"""Post-process raw CTC token starts toward Studio's human stamping conventions, then eval.

Corrections:
  A. onset-snap: if the predicted start sits inside a speech run whose acoustic onset is
     within `max_back` ms earlier, move the start to that onset (CTC emits late; humans
     stamp at the acoustic onset).
  B. lead-in: first-of-line tokens back off `lead_in` ms into the preceding silence
     (mirrors leadInAdjustedBoundaries in webapp/lib/tts/alignment.ts, 80 ms).
  C. global shift: subtract `shift` ms from every remaining token (models human tap
     lookback TOKEN_STAMP_LOOKBACK_SECONDS=120ms + CTC delay).
"""
import json, sys, itertools
import numpy as np, soundfile as sf
sys.path.insert(0, ".")
from eval_tokensync import evaluate, summarize, report

SR = 16000


def rms_track(wave, win_ms=10):
    w = int(SR * win_ms / 1000)
    n = len(wave) // w
    r = np.sqrt((wave[: n * w].reshape(n, w) ** 2).mean(axis=1))
    return r, w


def quiet_threshold(r):
    s = np.sort(r)
    floor = s[int(len(s) * 0.1)]
    mx = s[-1]
    return max(floor * 1.6, floor + (mx - floor) * 0.04, 0.003)


def snap_to_onset(t, r, w, thr, max_back_ms):
    """Walk back from t while frames are loud; return onset time of that speech run, or t."""
    k = int(t * SR / w)
    k = min(max(k, 0), len(r) - 1)
    if r[k] < thr:  # predicted inside silence already: walk forward to speech onset
        j = k
        while j < len(r) - 1 and r[j] < thr and (j - k) * w / SR < 0.25:
            j += 1
        return j * w / SR
    j = k
    lim = int(max_back_ms / 1000 * SR / w)
    while j > 0 and r[j - 1] >= thr and (k - j) < lim:
        j -= 1
    if k - j >= lim:
        return t  # long continuous speech: mid-phrase, don't snap
    return j * w / SR


def apply(pred, wave, shift_ms, lead_in_ms, max_back_ms, snap_all):
    r, w = rms_track(wave)
    thr = quiet_threshold(r)
    out = {"lines": []}
    prev = -1.0
    for li, line in enumerate(pred["lines"]):
        toks = []
        for ti, t in enumerate(line["tokens"]):
            s = t["startSeconds"]
            if ti == 0 or snap_all:
                on = snap_to_onset(s, r, w, thr, max_back_ms)
                if ti == 0:
                    s = max(on - lead_in_ms / 1000, 0)
                elif on < s:  # post-pause token snapped to onset; no further shift
                    s = on - min(shift_ms, 60) / 1000
                else:
                    s = s - shift_ms / 1000
            else:
                s = s - shift_ms / 1000
            s = max(s, prev + 0.02)
            prev = s
            toks.append({"text": t["text"], "startSeconds": round(s, 3)})
        out["lines"].append({"text": line["text"], "tokens": toks})
    return out


if __name__ == "__main__":
    src = sys.argv[1] if len(sys.argv) > 1 else "pred_whole.json"
    pred = json.load(open(src)); gold = json.load(open("gold/gold.json"))
    waves = {sid: sf.read(f"audio/{sid.split('/')[1]}.wav", dtype="float32")[0] for sid in gold}
    grid = list(itertools.product([100, 130, 150, 170], [40, 80, 120], [250, 350], [False, True]))
    results = []
    for shift, lead, back, snap_all in grid:
        rows = []
        for sid in gold:
            p = apply(pred[sid], waves[sid], shift, lead, back, snap_all)
            rr, _ = evaluate(p, gold[sid])
            rows += rr
        a = sorted(abs(x["delta_ms"]) for x in rows)
        w100 = 100 * sum(v <= 100 for v in a) / len(a)
        results.append((w100, shift, lead, back, snap_all, np.median(a), a[int(.95 * len(a))]))
    results.sort(reverse=True)
    print("top configs (≤100%, shift, lead_in, max_back, snap_all, med, p95):")
    for r in results[:6]:
        print("  %.1f%%  shift=%d lead=%d back=%d snapAll=%s med=%.0f p95=%.0f" % r)
    best = results[0]
    _, shift, lead, back, snap_all = best[:5]
    rows, stats = [], {}
    outp = {}
    for sid in gold:
        p = apply(pred[sid], waves[sid], shift, lead, back, snap_all)
        outp[sid] = p
        rr, ss = evaluate(p, gold[sid])
        rows += rr
        for k, v in ss.items(): stats[k] = stats.get(k, 0) + v
    report(rows, stats, f"BEST shift={shift} lead={lead} back={back} snapAll={snap_all} ({src})")
    json.dump(outp, open("pred_post.json", "w"), ensure_ascii=False, indent=1)
    # worst tokens
    print("\nworst 12 tokens:")
    for r in sorted(rows, key=lambda r: -abs(r["delta_ms"]))[:12]:
        print("  L%02d T%02d %-14s Δ=%+5.0f gold=%.3f pred=%.3f first=%s" % (r["line"], r["tok"], r["text"], r["delta_ms"], r["gold"], r["pred"], r["first"]))
