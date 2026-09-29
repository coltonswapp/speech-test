"""Unit checks for romanization + ふふ CTC skip. Run: python tests/test_core.py"""
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
import numpy as np
from aligner.core import (
    WordSpan,
    fill_skipped_spans,
    is_kana,
    romanize,
    should_skip_ctc,
)

assert is_kana("さんまるに") and is_kana("カイトー") and not is_kana("三〇二") and not is_kana("302")
# A kana reading wins and is not a fallback.
assert romanize("三〇二", "さんまるに") == ("sanmaruni", False)
assert romanize("302", "さんまるに") == ("sanmaruni", False)
# Non-kana reading is ignored; without an override the surface is guessed
# (and flagged as a fallback) — the tokenizer's reading is what makes numerals work.
assert romanize("三〇二", "302")[1] is True
assert romanize("302") == ("a", True)
# Plain surface → pykakasi.
assert romanize("すみません") == ("sumimasen", True)
assert romanize("日本", "にほん") == ("nihon", False)
# Nothing alignable still yields one target.
assert romanize("ー") == ("a", True)
assert romanize("…") == ("a", True)

# 「ふふ」 is the only CTC skip; other laughter stays on the phonemic path.
assert should_skip_ctc("ふふ") is True
assert should_skip_ctc("笑", "ふふ") is True
assert should_skip_ctc("あはは") is False
assert should_skip_ctc("へへ") is False
assert should_skip_ctc("うふふ") is False
assert should_skip_ctc("ふふふ") is False
# Speculative huhu override is NOT the primary fix — romanize still yields fufu.
assert romanize("ふふ") == ("fufu", True)
assert romanize("ふふ", "ふふ") == ("fufu", False)

# Neighbor interpolation: skip sits in the gap between aligned neighbors.
# Spans from align_words for empty romaji are (0,0) — fill must replace them.
raw = [
    WordSpan(10, 20, 0.9),
    WordSpan(0, 0, 0.0),  # ふふ placeholder
    WordSpan(40, 50, 0.8),
]
filled = fill_skipped_spans(raw, [False, True, False], n_frames=60, n_samples16k=60 * 320)
assert filled[0] == raw[0] and filled[2] == raw[2]
assert filled[1].start_frame == 20 and filled[1].end_frame == 40
assert filled[1].score == 0.0
# Never leave a zero span that would stamp at t=0 and cascade.
assert not (filled[1].start_frame == 0 and filled[1].end_frame == 0)

# Degenerate gap (neighbors abut): still get a tiny non-zero span at the boundary.
tight = fill_skipped_spans(
    [WordSpan(10, 30, 1.0), WordSpan(0, 0, 0.0), WordSpan(30, 40, 1.0)],
    [False, True, False],
    n_frames=50,
    n_samples16k=50 * 320,
)
assert tight[1].end_frame > tight[1].start_frame

# RMS prefers the loud run inside the gap over a uniform mid-gap split.
# 100 frames × 320 samples/frame = 32000 samples @ 16 kHz. Put energy only in
# frames 55–65 (samples covering that CTC region).
n_frames = 100
n_samples = n_frames * 320
wave = np.zeros(n_samples, dtype=np.float32)
# Loud samples corresponding roughly to frames 55–65.
wave[55 * 320 : 65 * 320] = 0.2
rms_filled = fill_skipped_spans(
    [WordSpan(10, 20, 0.9), WordSpan(0, 0, 0.0), WordSpan(80, 90, 0.8)],
    [False, True, False],
    n_frames=n_frames,
    n_samples16k=n_samples,
    wave16k=wave,
)
assert 50 <= rms_filled[1].start_frame <= 60
assert 60 <= rms_filled[1].end_frame <= 70

# Leading / trailing skip uses take bounds.
edge = fill_skipped_spans(
    [WordSpan(0, 0, 0.0), WordSpan(30, 40, 0.9), WordSpan(0, 0, 0.0)],
    [True, False, True],
    n_frames=50,
    n_samples16k=50 * 320,
)
assert edge[0].start_frame == 0 and edge[0].end_frame == 30
assert edge[2].start_frame == 40 and edge[2].end_frame == 50

print("test_core OK")
