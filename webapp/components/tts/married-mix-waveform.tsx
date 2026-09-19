"use client";

import { useEffect, useRef, useState } from "react";
import WaveSurfer from "wavesurfer.js";
import { STUDIO_RESTART_MARRIED_MIX } from "@/lib/tts/ambience";

function formatTime(seconds: number): string {
  if (!Number.isFinite(seconds)) return "0:00";
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${m}:${s.toString().padStart(2, "0")}`;
}

export function MarriedMixWaveform({
  url,
  playing,
  onPlayingChange,
}: {
  url: string;
  playing: boolean;
  onPlayingChange: (playing: boolean) => void;
}) {
  const containerRef = useRef<HTMLDivElement>(null);
  const wavesurferRef = useRef<WaveSurfer | null>(null);
  const playingRef = useRef(playing);
  playingRef.current = playing;
  const [duration, setDuration] = useState(0);
  const [currentTime, setCurrentTime] = useState(0);

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;
    let cancelled = false;
    const ws = WaveSurfer.create({
      container,
      waveColor: "oklch(0.62 0.1 230)",
      progressColor: "oklch(0.94 0.19 95)",
      cursorColor: "oklch(0.94 0.19 95)",
      cursorWidth: 1,
      height: 88,
      barWidth: 2,
      barGap: 1,
      url,
    });
    wavesurferRef.current = ws;

    ws.on("ready", (d) => {
      if (cancelled) return;
      setDuration(d);
      if (playingRef.current) void ws.play();
    });
    ws.on("audioprocess", (t) => {
      if (!cancelled) setCurrentTime(t);
    });
    ws.on("interaction", () => {
      if (!cancelled) setCurrentTime(ws.getCurrentTime());
    });
    ws.on("play", () => {
      if (!cancelled) onPlayingChange(true);
    });
    ws.on("pause", () => {
      if (!cancelled) onPlayingChange(false);
    });
    ws.on("finish", () => {
      if (!cancelled) onPlayingChange(false);
    });

    return () => {
      cancelled = true;
      wavesurferRef.current = null;
      ws.destroy();
    };
  }, [url, onPlayingChange]);

  useEffect(() => {
    const ws = wavesurferRef.current;
    if (!ws) return;
    if (playing && !ws.isPlaying()) void ws.play();
    if (!playing && ws.isPlaying()) ws.pause();
  }, [playing]);

  useEffect(() => {
    function onRestart() {
      const ws = wavesurferRef.current;
      if (!ws) return;
      if (ws.isPlaying()) ws.pause();
      ws.setTime(0);
      setCurrentTime(0);
      void ws.play();
    }
    window.addEventListener(STUDIO_RESTART_MARRIED_MIX, onRestart);
    return () => window.removeEventListener(STUDIO_RESTART_MARRIED_MIX, onRestart);
  }, []);

  return (
    <div className="flex flex-col gap-1">
      <div className="flex items-center justify-between gap-2">
        <span className="text-[11px] font-medium uppercase tracking-wide text-emerald-700 dark:text-emerald-300">
          Mixed clip
        </span>
        <span className="text-[11px] tabular-nums text-muted-foreground">
          {formatTime(currentTime)} / {formatTime(duration)}
        </span>
      </div>
      <div
        ref={containerRef}
        className="h-[88px] w-full rounded-sm border border-emerald-500/35 bg-muted/30"
      />
    </div>
  );
}
