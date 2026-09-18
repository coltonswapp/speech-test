"""Eval harness: compare predicted tokenSync vs human gold tokenSync.

Usage: python eval_tokensync.py pred.json gold.json [--bias-ms N]
  pred.json / gold.json: {"lines":[{"text":..., "tokens":[{"text":..., "startSeconds":...}]}]}
Both files may be a bare tokenSync object or a dict of {sceneId: tokenSync}.

Alignment policy (document in Studio when tokenization diverges):
  - Lines are aligned by index; text must match after trim, else the line is skipped and counted.
  - Tokens are aligned by character span in the line text (each token maps to a [start,end) char
    range via sequential indexOf, same as tokenRangesInLine in lib/dialogue/token-sync.ts).
  - A gold token is "matched" when a predicted token starts at the same char offset. Gold tokens
    whose start char falls inside a predicted token (pred merged them) are counted as
    `unmatched_merged`; predicted tokens starting mid-gold-token (pred split) are `extra_split`.
  - Δ is computed only on matched tokens: Δ = pred.start - gold.start (positive = late).
"""
import json, sys, statistics as st

PARTICLES = set("はがをにでとのもへやかねよ") | {"よね", "ので", "から", "まで", "んですか", "んですね", "んです", "です", "だ", "な"}


def token_spans(text, tokens):
    spans = []
    cur = 0
    for t in tokens:
        i = text.find(t["text"], cur)
        if i < 0:
            return None
        spans.append((i, i + len(t["text"]), t))
        cur = i + len(t["text"])
    return spans


def evaluate(pred, gold, bias_ms=0.0):
    rows = []  # per matched token
    stats = {"lines": 0, "line_text_mismatch": 0, "gold_tokens": 0, "matched": 0,
             "unmatched_merged": 0, "extra_split": 0, "pred_tokens": 0}
    for li, gl in enumerate(gold["lines"]):
        stats["lines"] += 1
        stats["gold_tokens"] += len(gl["tokens"])
        pl = pred["lines"][li] if li < len(pred["lines"]) else None
        if pl is None or pl["text"].strip() != gl["text"].strip():
            stats["line_text_mismatch"] += 1
            continue
        stats["pred_tokens"] += len(pl["tokens"])
        gs = token_spans(gl["text"], gl["tokens"])
        ps = token_spans(pl["text"], pl["tokens"])
        if gs is None or ps is None:
            stats["line_text_mismatch"] += 1
            continue
        pstart = {s: t for s, e, t in ps}
        gstart = {s for s, e, t in gs}
        for s, e, t in ps:
            if s not in gstart:
                stats["extra_split"] += 1
        prev_gold = None
        for ti, (s, e, gt) in enumerate(gs):
            pt = pstart.get(s)
            if pt is None or pt.get("startSeconds") is None:
                stats["unmatched_merged"] += 1
                prev_gold = gt["startSeconds"]
                continue
            stats["matched"] += 1
            d = (pt["startSeconds"] - gt["startSeconds"]) * 1000 - bias_ms
            gap_prev = (gt["startSeconds"] - prev_gold) * 1000 if prev_gold is not None else None
            rows.append({
                "line": li, "tok": ti, "text": gt["text"], "delta_ms": d,
                "first": ti == 0, "particle": gt["text"] in PARTICLES,
                "single_char": len(gt["text"]) == 1,
                "post_pause": gap_prev is not None and gap_prev > 350,
                "gold": gt["startSeconds"], "pred": pt["startSeconds"],
            })
            prev_gold = gt["startSeconds"]
    return rows, stats


def summarize(rows, label="all"):
    if not rows:
        return f"{label}: n=0"
    a = sorted(abs(r["delta_ms"]) for r in rows)
    sgn = [r["delta_ms"] for r in rows]
    n = len(a)
    p = lambda q: a[min(n - 1, int(q * n))]
    within = lambda ms: 100.0 * sum(1 for x in a if x <= ms) / n
    return (f"{label:>14}: n={n:3d} med|Δ|={st.median(a):5.0f} p95|Δ|={p(0.95):5.0f} "
            f"≤50:{within(50):5.1f}% ≤100:{within(100):5.1f}% ≤150:{within(150):5.1f}% "
            f"bias(signed med)={st.median(sgn):+5.0f} mean={st.mean(sgn):+5.0f}")


def report(rows, stats, title=""):
    print(f"=== {title} ===")
    print("coverage:", stats)
    print(summarize(rows))
    print(summarize([r for r in rows if r["first"]], "first-of-line"))
    print(summarize([r for r in rows if not r["first"]], "non-first"))
    print(summarize([r for r in rows if r["particle"]], "particle"))
    print(summarize([r for r in rows if r["single_char"]], "single-char"))
    print(summarize([r for r in rows if r["post_pause"]], "post-pause"))
    print(summarize([r for r in rows if not r["post_pause"] and not r["first"]], "mid-phrase"))


def load(path):
    d = json.load(open(path))
    return d if "lines" in d else d  # either bare or dict-of-scenes


if __name__ == "__main__":
    pred, gold = load(sys.argv[1]), load(sys.argv[2])
    bias = float(sys.argv[sys.argv.index("--bias-ms") + 1]) if "--bias-ms" in sys.argv else 0.0
    all_rows, all_stats = [], {}
    keys = [None] if "lines" in gold else sorted(gold.keys())
    for k in keys:
        p = pred if k is None else pred[k]
        g = gold if k is None else gold[k]
        rows, stats = evaluate(p, g, bias)
        report(rows, stats, k or "scene")
        all_rows += rows
        for s, v in stats.items():
            all_stats[s] = all_stats.get(s, 0) + v
    if len(keys) > 1:
        report(all_rows, all_stats, "ALL")
