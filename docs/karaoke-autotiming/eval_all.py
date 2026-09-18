import json, numpy as np, soundfile as sf, statistics as st, itertools
from eval_tokensync import evaluate, summarize
from postprocess import apply, rms_track, quiet_threshold

gold = json.load(open('gold/gold_all.json')); pred = json.load(open('pred_all_whole.json'))
waves = {sid: sf.read(f"audio_all/{sid.replace('/','__')}.wav", dtype='float32')[0] for sid in pred}
CFG = dict(shift_ms=150, lead_in_ms=120, max_back_ms=350, snap_all=False)  # tuned on first-hello only

rows_by_scene = {}; stats_tot = {}
for sid in pred:
    p = apply(pred[sid], waves[sid], **CFG)
    rr, ss = evaluate(p, gold[sid])
    for r in rr: r['scene'] = sid; r['coll'] = sid.split('/')[0]
    rows_by_scene[sid] = rr
    for k, v in ss.items(): stats_tot[k] = stats_tot.get(k, 0) + v

allrows = [r for rr in rows_by_scene.values() for r in rr]
held = [r for r in allrows if r['coll'] != 'first-hello']
print("coverage:", stats_tot)
print("\n=== HELD-OUT (35 scenes, config fixed from first-hello) ===")
nf = [r for r in held if not r['first']]
print(summarize(nf, 'in-line'))
print(summarize([r for r in nf if r['particle']], 'particle'))
print(summarize([r for r in nf if r['single_char']], 'single-char'))
print(summarize([r for r in nf if r['post_pause']], 'post-pause'))
print(summarize([r for r in nf if not r['post_pause']], 'mid-phrase'))
print(summarize([r for r in held if r['first']], 'first-of-line'))
print("\n=== ALL 38 ===")
print(summarize([r for r in allrows if not r['first']], 'in-line'))

print("\n=== per collection (in-line) ===")
for coll in sorted({r['coll'] for r in allrows}):
    print(summarize([r for r in allrows if r['coll'] == coll and not r['first']], coll))

print("\n=== per scene: share within 100ms, worst first (in-line) ===")
per = []
for sid, rr in rows_by_scene.items():
    x = [abs(r['delta_ms']) for r in rr if not r['first']]
    if x: per.append((100 * sum(v <= 100 for v in x) / len(x), 100 * sum(v <= 150 for v in x) / len(x), st.median(x), len(x), sid))
per.sort()
for w100, w150, med, n, sid in per[:8]:
    print("  %-38s ≤100: %5.1f%%  ≤150: %5.1f%%  med %4.0f  n=%3d" % (sid, w100, w150, med, n))
print("  ...")
print("  scenes with ≥85%% ≤100ms: %d/%d ; ≥80%%: %d/%d" % (sum(p[0] >= 85 for p in per), len(per), sum(p[0] >= 80 for p in per), len(per)))

# line-level acceptance: share of lines with no in-line token > 150 ms
lines = {}
for r in allrows:
    if r['first']: continue
    k = (r['scene'], r['line']); lines[k] = lines.get(k, False) or abs(r['delta_ms']) > 150
print("\nlines with no in-line token >150ms off: %.1f%% of %d lines" % (100 * sum(not v for v in lines.values()) / len(lines), len(lines)))

# boundaries: derived mark (onset-80ms) inside silence gap
in_gap = 0; nb = 0; dmark = []
for sid in pred:
    marks = json.load(open(f"audio_all/{sid.replace('/','__')}.marks.json"))
    if not marks: continue
    w = waves[sid]; r, ws = rms_track(w); thr = quiet_threshold(r)
    L = pred[sid]['lines']
    for i, m in enumerate(marks):
        if i + 1 >= len(L): break
        s = L[i + 1]['tokens'][0]['startSeconds']; k = int(s * 16000 / ws); j = k
        while j > 0 and r[j - 1] >= thr: j -= 1
        onset = j * ws / 16000; q = j
        while q > 0 and r[q - 1] < thr: q -= 1
        prev_end = q * ws / 16000
        pm = max(onset - 0.08, prev_end + 0.01); nb += 1; in_gap += (prev_end <= pm <= onset); dmark.append((pm - m) * 1000)
print("derived line marks inside silence gap: %d/%d ; Δ vs human mark med %+.0f ms" % (in_gap, nb, st.median(dmark)))

# stamp-in-silence flag heuristic on held-out
flag = 0; caught = 0; bad = 0; n = 0
for sid in pred:
    if sid.startswith('first-hello'): continue
    w = waves[sid]; r, ws = rms_track(w); thr = quiet_threshold(r)
    for x in rows_by_scene[sid]:
        if x['first']: continue
        k = int(x['pred'] * 16000 / ws); e = np.mean(r[k:k + 6]) / thr if k + 6 <= len(r) else 9
        f = e < 1.0; b = abs(x['delta_ms']) > 150
        n += 1; flag += f; bad += b; caught += (f and b)
print("stamp-in-silence flag (held-out in-line): flag rate %.1f%%, catches %d/%d tokens >150ms" % (100 * flag / n, caught, bad))

# reference: sweep on full set
print("\n=== config sweep on all 38 (reference only) ===")
res = []
for shift, lead in itertools.product([120, 150, 180], [80, 120]):
    rows = []
    for sid in pred:
        p = apply(pred[sid], waves[sid], shift, lead, 350, False)
        rr, _ = evaluate(p, gold[sid]); rows += [r for r in rr if r['tok'] > 0]
    a = [abs(r['delta_ms']) for r in rows]
    res.append((100 * sum(v <= 100 for v in a) / len(a), shift, lead, st.median(a)))
for w, s, l, m in sorted(res, reverse=True)[:3]:
    print("  shift=%d lead=%d ≤100: %.1f%% med %.0f" % (s, l, w, m))
