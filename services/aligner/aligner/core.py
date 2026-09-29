"""Forced alignment of a known Japanese script to take audio.

torchaudio MMS_FA (wav2vec2 CTC, 20 ms frames at 16 kHz) over the whole take;
line boundaries fall out of the alignment. Ported from
docs/karaoke-autotiming/align_mms.py — keep numerics identical so the eval
harness stays comparable.

Non-phonemic laughter 「ふふ」 is excluded from CTC targets and timed by
neighbor/RMS interpolation so it cannot warp the global Viterbi path. Other
laughter markers (あはは, へへ, …) are left alone.
"""
from __future__ import annotations

import re
from dataclasses import dataclass
from functools import lru_cache
from typing import Sequence

import numpy as np
import pykakasi

ALIGNER_VERSION = "mms-fa-v1.1"
MODEL_SAMPLE_RATE = 16000
# Default duration for a skipped token when the neighbor gap is short / empty.
_SKIP_MIN_FRAMES = 2
# RMS window for loud-region search inside a skip gap (matches karaoke postprocess).
_RMS_WIN_MS = 10

# Last-resort surface fixes when no kana reading was supplied (KA-5 sends
# readings from the tokenizer, so numerals such as 三〇二 / 302 no longer
# need entries here). Keep this to pure orthographic quirks.
ROMAJI_OVERRIDES = {
    "はいー": "haii",
    "ー": "",
}

# Exact surface or reading. Giggle audio ≠ phonemic "fufu"; forcing those four
# CTC chars warps whole-take alignment. Keep the Studio token; fill timing later.
CTC_SKIP_EXACT = frozenset({"ふふ"})

_KANA_RE = re.compile(r"^[぀-ゟ゠-ヿー〜]+$")

_kks = pykakasi.kakasi()


def is_kana(text: str) -> bool:
    return bool(_KANA_RE.match(text))


def should_skip_ctc(surface: str, reading: str | None = None) -> bool:
    """True when this token must not contribute any MMS CTC targets."""
    if surface in CTC_SKIP_EXACT:
        return True
    if reading is not None and reading in CTC_SKIP_EXACT:
        return True
    return False


def _hepburn(text: str) -> str:
    out = "".join(item["hepburn"] for item in _kks.convert(text))
    out = out.lower().replace("-", "").replace("’", "'")
    return re.sub(r"[^a-z']", "", out)


def romanize(surface: str, reading: str | None = None) -> tuple[str, bool]:
    """Return (romaji, used_fallback).

    A kana `reading` is authoritative. Otherwise fall back to the override
    table, then pykakasi on the surface. Empty output becomes "a" so the
    token still owns at least one CTC target (matches the prototype).

    Callers that omit CTC for 「ふふ」 should use `should_skip_ctc` and pass
    an empty string into `align_words` rather than relying on this return.
    """
    if reading and is_kana(reading):
        out = _hepburn(reading)
        if out:
            return out, False
    if surface in ROMAJI_OVERRIDES:
        return ROMAJI_OVERRIDES[surface] or "a", True
    return _hepburn(surface) or "a", True


@dataclass
class _Bundle:
    model: object
    dictionary: dict[str, int]


def device():
    import torch

    return torch.device("cuda" if torch.cuda.is_available() else "cpu")


@lru_cache(maxsize=1)
def load_bundle() -> _Bundle:
    import torchaudio

    bundle = torchaudio.pipelines.MMS_FA
    model = bundle.get_model(with_star=False).eval().to(device())
    assert bundle.sample_rate == MODEL_SAMPLE_RATE
    return _Bundle(model=model, dictionary=bundle.get_dict(star=None))


def to_model_wave(wave: np.ndarray, sample_rate: int) -> np.ndarray:
    """Mono float32 at 16 kHz."""
    import torch
    import torchaudio

    if wave.ndim > 1:
        wave = wave.mean(axis=1)
    wave = wave.astype(np.float32, copy=False)
    if sample_rate != MODEL_SAMPLE_RATE:
        t = torch.from_numpy(wave)
        wave = torchaudio.functional.resample(t, sample_rate, MODEL_SAMPLE_RATE).numpy()
    return wave


def emission_for(wave16k: np.ndarray):
    import torch

    b = load_bundle()
    with torch.inference_mode():
        em, _ = b.model(torch.from_numpy(wave16k).float().unsqueeze(0).to(device()))
    return em[0].cpu()  # (frames, vocab)


@dataclass
class WordSpan:
    start_frame: int
    end_frame: int
    score: float


def align_words(em, words: Sequence[str]) -> list[WordSpan]:
    """words: romaji per token. Frame spans per word plus mean char score.

    Empty strings contribute no CTC targets (acc stays None → WordSpan(0,0,0)).
    Callers that intentionally skip tokens (e.g. 「ふふ」) must run
    `fill_skipped_spans` afterward — do not leave zero spans in place.
    """
    import torch
    import torchaudio

    b = load_bundle()
    ids: list[int] = []
    owner: list[int] = []
    for wi, w in enumerate(words):
        for c in w:
            if c in b.dictionary:
                ids.append(b.dictionary[c])
                owner.append(wi)
    if not ids:
        raise ValueError("no alignable characters in script")
    if len(ids) > em.shape[0]:
        raise ValueError(
            f"script has {len(ids)} targets but audio has only {em.shape[0]} frames"
        )
    targets = torch.tensor([ids], dtype=torch.int32)
    ali, scores = torchaudio.functional.forced_align(em.unsqueeze(0), targets, blank=0)
    spans = torchaudio.functional.merge_tokens(ali[0], scores[0].exp())

    acc: list[list | None] = [None] * len(words)
    for k, sp in enumerate(spans):
        wi = owner[k]
        if acc[wi] is None:
            acc[wi] = [sp.start, sp.end, [sp.score]]
        else:
            acc[wi][1] = sp.end
            acc[wi][2].append(sp.score)
    out: list[WordSpan] = []
    for v in acc:
        if v is None:
            out.append(WordSpan(0, 0, 0.0))
        else:
            out.append(WordSpan(int(v[0]), int(v[1]), float(np.mean(v[2]))))
    return out


def frames_to_seconds(frame: int, n_frames: int, n_samples16k: int) -> float:
    return frame * (n_samples16k / n_frames) / MODEL_SAMPLE_RATE


def _rms_track(wave16k: np.ndarray) -> tuple[np.ndarray, int]:
    win = max(1, int(MODEL_SAMPLE_RATE * _RMS_WIN_MS / 1000))
    n = len(wave16k) // win
    if n == 0:
        return np.zeros(0, dtype=np.float32), win
    r = np.sqrt((wave16k[: n * win].reshape(n, win) ** 2).mean(axis=1))
    return r, win


def _quiet_threshold(rms: np.ndarray) -> float:
    if len(rms) == 0:
        return 0.003
    s = np.sort(rms)
    floor = float(s[int(len(s) * 0.1)])
    mx = float(s[-1])
    return max(floor * 1.6, floor + (mx - floor) * 0.04, 0.003)


def _loud_span_in_gap(
    lo: int, hi: int, n_frames: int, n_samples16k: int, wave16k: np.ndarray | None
) -> tuple[int, int] | None:
    """If wave is available, return the loudest contiguous run of frames in [lo, hi)."""
    if wave16k is None or hi <= lo or n_frames <= 0:
        return None
    rms, win = _rms_track(wave16k)
    if len(rms) == 0:
        return None
    thr = _quiet_threshold(rms)
    # Map CTC frames → RMS bins via sample index.
    def frame_to_bin(f: int) -> int:
        sample = int(f * (n_samples16k / n_frames))
        return min(max(sample // win, 0), len(rms) - 1)

    a, b = frame_to_bin(lo), frame_to_bin(max(lo, hi - 1))
    if b < a:
        a, b = b, a
    # Find longest loud run inside [a, b].
    best: tuple[int, int] | None = None
    best_len = 0
    i = a
    while i <= b:
        if rms[i] < thr:
            i += 1
            continue
        j = i
        while j <= b and rms[j] >= thr:
            j += 1
        if j - i > best_len:
            best_len = j - i
            best = (i, j)
        i = j
    if best is None or best_len <= 0:
        return None

    def bin_to_frame(k: int) -> int:
        sample = k * win
        return int(round(sample * n_frames / n_samples16k))

    s = max(lo, min(hi, bin_to_frame(best[0])))
    e = max(s + 1, min(hi, bin_to_frame(best[1])))
    if e <= s:
        return None
    return s, e


def fill_skipped_spans(
    spans: Sequence[WordSpan],
    skipped: Sequence[bool],
    n_frames: int,
    n_samples16k: int,
    wave16k: np.ndarray | None = None,
) -> list[WordSpan]:
    """Interpolate frame spans for tokens that were omitted from CTC.

    For each contiguous run of skipped tokens, the gap between the previous
    and next aligned neighbor (or take bounds) is split evenly. When 16 kHz
    audio is provided, a loud RMS run inside that gap is preferred so the
    giggle lands on energy rather than silence.
    """
    if len(spans) != len(skipped):
        raise ValueError("spans and skipped must be the same length")
    out = list(spans)
    n = len(out)
    i = 0
    while i < n:
        if not skipped[i]:
            i += 1
            continue
        j = i
        while j < n and skipped[j]:
            j += 1
        # Neighbor bounds in frames.
        if i > 0:
            lo = out[i - 1].end_frame
        else:
            lo = 0
        if j < n:
            hi = out[j].start_frame
        else:
            hi = n_frames
        if hi < lo:
            hi = lo
        gap = hi - lo
        count = j - i
        loud = _loud_span_in_gap(lo, hi, n_frames, n_samples16k, wave16k)
        if loud is not None:
            lo, hi = loud
            gap = hi - lo
        # Even split of the (possibly RMS-shrunk) gap across the skip run.
        for k in range(count):
            if gap <= 0:
                # Degenerate: park a tiny span at the boundary so Studio still
                # has a stamp (never leave WordSpan(0,0) which cascades).
                s = max(0, min(n_frames, lo))
                e = max(s + 1, min(n_frames, s + _SKIP_MIN_FRAMES))
            else:
                s = lo + (gap * k) // count
                e = lo + (gap * (k + 1)) // count
                if e <= s:
                    e = s + 1
            out[i + k] = WordSpan(int(s), int(e), 0.0)
        i = j
    return out


@dataclass
class TokenIn:
    text: str
    reading: str | None = None


@dataclass
class TokenOut:
    startSeconds: float
    endSeconds: float
    score: float
    readingFallback: bool


@dataclass
class LineOut:
    tokens: list[TokenOut]
    score: float


def align_take(
    wave: np.ndarray, sample_rate: int, lines: Sequence[Sequence[TokenIn]]
) -> tuple[list[LineOut], float]:
    """Whole-take alignment. Returns (lines, durationSeconds) in full-WAV seconds.

    Tokens matching `should_skip_ctc` (「ふふ」 only) are kept in the Studio
    output but omitted from CTC targets; their spans are filled from neighbors
    / RMS so unmatched "fufu" phonemes cannot warp the global path.
    """
    w16 = to_model_wave(wave, sample_rate)
    n = len(w16)
    em = emission_for(w16)
    flat = [t for line in lines for t in line]
    skipped = [should_skip_ctc(t.text, t.reading) for t in flat]
    roman: list[tuple[str, bool]] = []
    for t, sk in zip(flat, skipped):
        if sk:
            # Empty romaji → no CTC IDs in align_words; not a reading fallback.
            roman.append(("", False))
        else:
            roman.append(romanize(t.text, t.reading))
    n_frames = int(em.shape[0])
    if flat and all(skipped):
        # Take is only 「ふふ」: no CTC targets. Seed placeholders, then fill
        # from RMS / take bounds so Studio still gets a stamp.
        spans = [WordSpan(0, 0, 0.0) for _ in flat]
    else:
        spans = align_words(em, [r for r, _ in roman])
    spans = fill_skipped_spans(spans, skipped, n_frames, n, w16)

    out: list[LineOut] = []
    k = 0
    for line in lines:
        toks: list[TokenOut] = []
        for _ in line:
            sp = spans[k]
            _, fallback = roman[k]
            k += 1
            toks.append(
                TokenOut(
                    startSeconds=round(frames_to_seconds(sp.start_frame, n_frames, n), 3),
                    endSeconds=round(frames_to_seconds(sp.end_frame, n_frames, n), 3),
                    score=round(sp.score, 3),
                    readingFallback=fallback,
                )
            )
        out.append(LineOut(tokens=toks, score=float(np.mean([t.score for t in toks])) if toks else 0.0))
    return out, n / MODEL_SAMPLE_RATE
