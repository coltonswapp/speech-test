"use client";

import { useEffect, useRef, type PointerEvent } from "react";
import {
  MIN_AMBIENCE_WINDOW_SECONDS,
  clampAmbienceWindow,
  wrapAmbienceOffset,
} from "@/lib/tts/ambience";
import { cn } from "@/lib/utils";

const peaksCache = new Map<string, Promise<Float32Array>>();

async function loadPeaks(url: string): Promise<Float32Array> {
  const cached = peaksCache.get(url);
  if (cached) return cached;
  const pending = (async () => {
    const res = await fetch(url);
    if (!res.ok) throw new Error("Could not load ambience waveform.");
    const buffer = await res.arrayBuffer();
    const ctx = new AudioContext();
    try {
      const decoded = await ctx.decodeAudioData(buffer.slice(0));
      const channel = decoded.getChannelData(0);
      const bars = 1800;
      const peaks = new Float32Array(bars);
      const step = channel.length / bars;
      for (let i = 0; i < bars; i++) {
        let max = 0;
        const start = Math.floor(i * step);
        const end = Math.min(channel.length, Math.floor((i + 1) * step));
        for (let j = start; j < end; j++) {
          const v = Math.abs(channel[j]);
          if (v > max) max = v;
        }
        peaks[i] = max;
      }
      return peaks;
    } finally {
      await ctx.close().catch(() => {});
    }
  })();
  peaksCache.set(url, pending);
  pending.catch(() => {
    peaksCache.delete(url);
  });
  return pending;
}

const HANDLE_PX = 8;

export function AmbienceLane({
  audioUrl,
  bedDuration,
  takeDuration,
  offsetSeconds,
  startSeconds = 0,
  endSeconds = null,
  playheadSeconds,
  label = "Ambience",
  accentClassName,
  onOffsetChange,
  onWindowChange,
}: {
  audioUrl: string;
  bedDuration: number;
  takeDuration: number;
  offsetSeconds: number;
  startSeconds?: number;
  endSeconds?: number | null;
  playheadSeconds: number;
  label?: string;
  accentClassName?: string;
  onOffsetChange?: (next: number) => void;
  onWindowChange?: (next: { startSeconds: number; endSeconds: number | null }) => void;
}) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const peaksRef = useRef<Float32Array | null>(null);
  const dragRef = useRef<{
    pointerId: number;
    mode: "move" | "start" | "end" | "phase";
    startX: number;
    startOffset: number;
    windowStart: number;
    windowEnd: number;
  } | null>(null);

  const clip = clampAmbienceWindow(startSeconds, endSeconds, takeDuration);
  const windowEnd = clip.endSeconds ?? takeDuration;

  useEffect(() => {
    let cancelled = false;
    peaksRef.current = null;
    void loadPeaks(audioUrl)
      .then((peaks) => {
        if (cancelled) return;
        peaksRef.current = peaks;
        paint();
      })
      .catch(() => {
        if (!cancelled) peaksRef.current = null;
      });
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [audioUrl]);

  function paint() {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const rect = canvas.getBoundingClientRect();
    const dpr = window.devicePixelRatio || 1;
    const width = Math.max(1, Math.round(rect.width * dpr));
    const height = Math.max(1, Math.round(rect.height * dpr));
    if (canvas.width !== width || canvas.height !== height) {
      canvas.width = width;
      canvas.height = height;
    }
    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    ctx.clearRect(0, 0, width, height);

    const mid = height / 2;
    const peaks = peaksRef.current;
    const loop = Math.max(0.05, bedDuration);
    const take = Math.max(0.05, takeDuration);
    const offset = wrapAmbienceOffset(offsetSeconds, loop);
    const startX = (clip.startSeconds / take) * width;
    const endX = (windowEnd / take) * width;

    ctx.fillStyle = "rgba(15, 23, 42, 0.18)";
    ctx.fillRect(0, 0, width, height);
    ctx.fillStyle = "rgba(56, 189, 248, 0.12)";
    ctx.fillRect(startX, 0, Math.max(1, endX - startX), height);

    if (peaks && peaks.length > 0) {
      ctx.fillStyle = "oklch(0.72 0.12 230)";
      for (let x = Math.floor(startX); x < endX; x++) {
        const takeT = (x / width) * take;
        const intoWindow = Math.max(0, takeT - clip.startSeconds);
        const bedT = wrapAmbienceOffset(offset + intoWindow, loop);
        const index = Math.min(
          peaks.length - 1,
          Math.floor((bedT / loop) * peaks.length)
        );
        const amp = peaks[index] ?? 0;
        const h = Math.max(dpr, amp * (height * 0.86));
        ctx.fillRect(x, mid - h / 2, 1, h);
      }
    }

    ctx.fillStyle = "oklch(0.72 0.12 230 / 55%)";
    ctx.fillRect(startX, 0, Math.max(2, dpr * 2), height);
    ctx.fillRect(endX - Math.max(2, dpr * 2), 0, Math.max(2, dpr * 2), height);

    if (takeDuration > 0) {
      const playX = (Math.min(playheadSeconds, takeDuration) / takeDuration) * width;
      ctx.strokeStyle = "oklch(0.94 0.19 95)";
      ctx.lineWidth = Math.max(1, dpr);
      ctx.beginPath();
      ctx.moveTo(playX, 0);
      ctx.lineTo(playX, height);
      ctx.stroke();
    }
  }

  useEffect(() => {
    paint();
    const canvas = canvasRef.current;
    if (!canvas) return;
    const observer = new ResizeObserver(() => paint());
    observer.observe(canvas);
    return () => observer.disconnect();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [bedDuration, takeDuration, offsetSeconds, startSeconds, endSeconds, playheadSeconds]);

  function timeDeltaForDx(dx: number): number {
    const canvas = canvasRef.current;
    if (!canvas || takeDuration <= 0) return 0;
    return (dx / canvas.getBoundingClientRect().width) * takeDuration;
  }

  function hitMode(clientX: number): "move" | "start" | "end" | "phase" {
    const canvas = canvasRef.current;
    if (!canvas || takeDuration <= 0) return "move";
    const rect = canvas.getBoundingClientRect();
    const x = clientX - rect.left;
    const startX = (clip.startSeconds / takeDuration) * rect.width;
    const endX = (windowEnd / takeDuration) * rect.width;
    if (Math.abs(x - startX) <= HANDLE_PX) return "start";
    if (Math.abs(x - endX) <= HANDLE_PX) return "end";
    if (!onWindowChange && onOffsetChange) return "phase";
    return "move";
  }

  function onPointerDown(event: PointerEvent<HTMLCanvasElement>) {
    if (event.button !== 0) return;
    event.currentTarget.setPointerCapture(event.pointerId);
    dragRef.current = {
      pointerId: event.pointerId,
      mode: hitMode(event.clientX),
      startX: event.clientX,
      startOffset: offsetSeconds,
      windowStart: clip.startSeconds,
      windowEnd,
    };
  }

  function onPointerMove(event: PointerEvent<HTMLCanvasElement>) {
    const drag = dragRef.current;
    if (!drag || drag.pointerId !== event.pointerId) return;
    const delta = timeDeltaForDx(event.clientX - drag.startX);
    if (drag.mode === "phase" && onOffsetChange) {
      onOffsetChange(wrapAmbienceOffset(drag.startOffset - delta, bedDuration));
      return;
    }
    if (!onWindowChange) return;
    if (drag.mode === "move") {
      const span = drag.windowEnd - drag.windowStart;
      const nextStart = Math.max(0, Math.min(takeDuration - span, drag.windowStart + delta));
      onWindowChange(
        clampAmbienceWindow(
          nextStart,
          nextStart + span >= takeDuration - 0.02 ? null : nextStart + span,
          takeDuration
        )
      );
      return;
    }
    if (drag.mode === "start") {
      onWindowChange(
        clampAmbienceWindow(drag.windowStart + delta, drag.windowEnd, takeDuration)
      );
      return;
    }
    onWindowChange(
      clampAmbienceWindow(
        drag.windowStart,
        Math.max(drag.windowStart + MIN_AMBIENCE_WINDOW_SECONDS, drag.windowEnd + delta),
        takeDuration
      )
    );
  }

  function onPointerUp(event: PointerEvent<HTMLCanvasElement>) {
    if (dragRef.current?.pointerId === event.pointerId) {
      dragRef.current = null;
    }
  }

  return (
    <div className="flex flex-col gap-1">
      <div className="flex items-center justify-between gap-2">
        <span
          className={cn(
            "text-[11px] font-medium uppercase tracking-wide text-sky-700 dark:text-sky-300",
            accentClassName
          )}
        >
          {label}
        </span>
        <span className="text-[11px] text-muted-foreground">
          Drag to place · edges to trim the window
        </span>
      </div>
      <canvas
        ref={canvasRef}
        className={cn(
          "h-[72px] w-full cursor-ew-resize touch-none rounded-sm border border-sky-500/30 bg-muted/40"
        )}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerUp}
        onPointerCancel={onPointerUp}
      />
    </div>
  );
}
