"""Acceptance check for KA-2 against the prototype.

Usage: python tests/verify_gold.py <proto_dir> [--http URL --token T]

<proto_dir> holds gold/gold.json, audio/<slug>.wav and pred_whole.json from
docs/karaoke-autotiming. Passes when every token start is within one CTC
frame (20 ms) of the prototype and each scene aligns in under 5 s warm.
"""
import json, sys, time, pathlib, argparse

import numpy as np, soundfile as sf

ap = argparse.ArgumentParser()
ap.add_argument("proto_dir")
ap.add_argument("--http", help="align via a running service instead of in-process")
ap.add_argument("--audio-base", help="URL prefix serving <slug>.wav for --http")
ap.add_argument("--token", default="local-dev-token")
args = ap.parse_args()

proto = pathlib.Path(args.proto_dir)
gold = json.load(open(proto / "gold/gold.json"))
ref = json.load(open(proto / "pred_whole.json"))

if not args.http:
    sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
    from aligner.core import TokenIn, align_take, load_bundle
    t = time.perf_counter(); load_bundle(); print(f"model load {time.perf_counter()-t:.1f}s")
else:
    import httpx

FRAME = 0.020
ok = True
for scene_id, ts in gold.items():
    slug = scene_id.split("/")[1]
    lines_req = [{"text": l["text"], "tokens": [{"text": t["text"]} for t in l["tokens"]]} for l in ts["lines"]]
    t0 = time.perf_counter()
    if args.http:
        r = httpx.post(f"{args.http}/align", json={"audioUrl": f"{args.audio_base}/{slug}.wav", "lines": lines_req},
                       headers={"Authorization": f"Bearer {args.token}"}, timeout=120)
        r.raise_for_status()
        body = r.json()
        pred_lines = body["lines"]; extra = body["timings"]
    else:
        wave, sr = sf.read(proto / f"audio/{slug}.wav", dtype="float32")
        out, _ = align_take(wave, sr, [[TokenIn(t["text"]) for t in l["tokens"]] for l in ts["lines"]])
        pred_lines = [{"tokens": [vars(t) for t in l.tokens]} for l in out]; extra = {}
    dt = time.perf_counter() - t0

    diffs = []
    for pl, rl in zip(pred_lines, ref[scene_id]["lines"]):
        for pt, rt in zip(pl["tokens"], rl["tokens"]):
            diffs.append(abs(pt["startSeconds"] - rt["startSeconds"]))
    diffs = np.array(diffs)
    n_tok = sum(len(l["tokens"]) for l in pred_lines)
    within = bool((diffs <= FRAME + 1e-6).all())
    fast = dt < 5.0
    ok &= within and fast
    print(f"{scene_id:40s} tokens={n_tok:3d} max|Δ|={diffs.max()*1000:5.1f}ms "
          f"time={dt:4.2f}s {extra} {'OK' if within and fast else 'FAIL'}")
print("PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
