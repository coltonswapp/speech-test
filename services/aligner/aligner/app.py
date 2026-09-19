"""FastAPI surface for the aligner. POST /align with a bearer token."""
from __future__ import annotations

import io
import os
import time
from typing import Optional

import httpx
import soundfile as sf
from fastapi import Depends, FastAPI, Header, HTTPException
from pydantic import BaseModel, Field

from aligner.core import ALIGNER_VERSION, TokenIn, align_take, load_bundle

MAX_AUDIO_BYTES = 64 * 1024 * 1024
FETCH_TIMEOUT_SECONDS = 30.0


class TokenReq(BaseModel):
    text: str = Field(min_length=1)
    reading: Optional[str] = None


class LineReq(BaseModel):
    text: str
    tokens: list[TokenReq] = Field(min_length=1)


class AlignRequest(BaseModel):
    audioUrl: str = Field(description="Signed URL of the full untrimmed WAV")
    lines: list[LineReq] = Field(min_length=1)


class TokenRes(BaseModel):
    startSeconds: float
    endSeconds: float
    score: float
    readingFallback: bool


class LineRes(BaseModel):
    tokens: list[TokenRes]
    score: float


class AlignResponse(BaseModel):
    alignerVersion: str
    durationSeconds: float
    sampleRate: int
    lines: list[LineRes]
    timings: dict[str, float]


def require_token(authorization: Optional[str] = Header(default=None)) -> None:
    expected = os.environ.get("ALIGNER_TOKEN")
    if not expected:
        raise HTTPException(500, "ALIGNER_TOKEN is not configured")
    if authorization != f"Bearer {expected}":
        raise HTTPException(401, "invalid bearer token")


app = FastAPI(title="shizen-aligner", version=ALIGNER_VERSION)


@app.get("/healthz")
def healthz() -> dict:
    import torch

    return {
        "ok": True,
        "alignerVersion": ALIGNER_VERSION,
        "torchThreads": torch.get_num_threads(),
        "cpuCount": os.cpu_count(),
    }


@app.post("/align", response_model=AlignResponse, dependencies=[Depends(require_token)])
def align(req: AlignRequest) -> AlignResponse:
    t0 = time.perf_counter()
    try:
        with httpx.Client(timeout=FETCH_TIMEOUT_SECONDS, follow_redirects=True) as client:
            r = client.get(req.audioUrl)
            r.raise_for_status()
    except httpx.HTTPError as e:
        raise HTTPException(502, f"audio fetch failed: {e}") from e
    if len(r.content) > MAX_AUDIO_BYTES:
        raise HTTPException(413, "audio larger than 64 MiB")
    t_fetch = time.perf_counter()

    try:
        wave, sr = sf.read(io.BytesIO(r.content), dtype="float32")
    except Exception as e:  # soundfile raises RuntimeError on bad data
        raise HTTPException(422, f"could not decode audio: {e}") from e

    lines = [[TokenIn(text=t.text, reading=t.reading) for t in line.tokens] for line in req.lines]
    try:
        out, duration = align_take(wave, sr, lines)
    except ValueError as e:
        raise HTTPException(422, str(e)) from e
    t_align = time.perf_counter()

    return AlignResponse(
        alignerVersion=ALIGNER_VERSION,
        durationSeconds=round(duration, 3),
        sampleRate=int(sr),
        lines=[
            LineRes(
                tokens=[TokenRes(**vars(t)) for t in line.tokens],
                score=round(line.score, 3),
            )
            for line in out
        ],
        timings={
            "fetchSeconds": round(t_fetch - t0, 3),
            "alignSeconds": round(t_align - t_fetch, 3),
        },
    )


def warm() -> None:
    """Load model weights and pin torch to every available core; call at
    container start so the first request is fast."""
    import torch

    threads = int(os.environ.get("ALIGNER_THREADS") or os.cpu_count() or 1)
    torch.set_num_threads(threads)
    load_bundle()
