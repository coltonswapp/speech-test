"""Forced alignment of a known Japanese script to take audio.

torchaudio MMS_FA (wav2vec2 CTC, 20 ms frames at 16 kHz) over the whole take;
line boundaries fall out of the alignment. Ported from
docs/karaoke-autotiming/align_mms.py — keep numerics identical so the eval
harness stays comparable.
"""
from __future__ import annotations

import re
from dataclasses import dataclass
from functools import lru_cache
from typing import Sequence

import numpy as np
import pykakasi
import torch
import torchaudio

ALIGNER_VERSION = "mms-fa-v1"
MODEL_SAMPLE_RATE = 16000

# Surfaces pykakasi gets wrong. KA-5 supplies readings from the tokenizer so
# this table shrinks over time; it stays as the last-resort fallback.
ROMAJI_OVERRIDES = {
    "三〇二": "sanmaruni",
    "302": "sanmaruni",
    "はいー": "haii",
    "ー": "",
}

_KANA_RE = re.compile(r"^[぀-ゟ゠-ヿー〜]+$")

_kks = pykakasi.kakasi()


def is_kana(text: str) -> bool:
    return bool(_KANA_RE.match(text))


def _hepburn(text: str) -> str:
    out = "".join(item["hepburn"] for item in _kks.convert(text))
    out = out.lower().replace("-", "").replace("’", "'")
    return re.sub(r"[^a-z']", "", out)


def romanize(surface: str, reading: str | None = None) -> tuple[str, bool]:
    """Return (romaji, used_fallback).

    A kana `reading` is authoritative. Otherwise fall back to the override
    table, then pykakasi on the surface. Empty output becomes "a" so the
    token still owns at least one CTC target (matches the prototype).
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
    model: torch.nn.Module
    dictionary: dict[str, int]


def device() -> torch.device:
    return torch.device("cuda" if torch.cuda.is_available() else "cpu")


@lru_cache(maxsize=1)
def load_bundle() -> _Bundle:
    bundle = torchaudio.pipelines.MMS_FA
    model = bundle.get_model(with_star=False).eval().to(device())
    assert bundle.sample_rate == MODEL_SAMPLE_RATE
    return _Bundle(model=model, dictionary=bundle.get_dict(star=None))


def to_model_wave(wave: np.ndarray, sample_rate: int) -> np.ndarray:
    """Mono float32 at 16 kHz."""
    if wave.ndim > 1:
        wave = wave.mean(axis=1)
    wave = wave.astype(np.float32, copy=False)
    if sample_rate != MODEL_SAMPLE_RATE:
        t = torch.from_numpy(wave)
        wave = torchaudio.functional.resample(t, sample_rate, MODEL_SAMPLE_RATE).numpy()
    return wave


def emission_for(wave16k: np.ndarray) -> torch.Tensor:
    b = load_bundle()
    with torch.inference_mode():
        em, _ = b.model(torch.from_numpy(wave16k).float().unsqueeze(0).to(device()))
    return em[0].cpu()  # (frames, vocab)


@dataclass
class WordSpan:
    start_frame: int
    end_frame: int
    score: float


def align_words(em: torch.Tensor, words: Sequence[str]) -> list[WordSpan]:
    """words: romaji per token. Frame spans per word plus mean char score."""
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
    """Whole-take alignment. Returns (lines, durationSeconds) in full-WAV seconds."""
    w16 = to_model_wave(wave, sample_rate)
    n = len(w16)
    em = emission_for(w16)
    flat = [t for line in lines for t in line]
    roman = [romanize(t.text, t.reading) for t in flat]
    spans = align_words(em, [r for r, _ in roman])

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
                    startSeconds=round(frames_to_seconds(sp.start_frame, em.shape[0], n), 3),
                    endSeconds=round(frames_to_seconds(sp.end_frame, em.shape[0], n), 3),
                    score=round(sp.score, 3),
                    readingFallback=fallback,
                )
            )
        out.append(LineOut(tokens=toks, score=float(np.mean([t.score for t in toks])) if toks else 0.0))
    return out, n / MODEL_SAMPLE_RATE
