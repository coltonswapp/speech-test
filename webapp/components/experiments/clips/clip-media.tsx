"use client";

import { useEffect, useImperativeHandle, useRef, type Ref } from "react";
import { cn } from "@/lib/utils";
import { usePersistentState } from "@/components/experiments/clips/use-persistent-state";

// One player for a clip: the uploaded clip.wav, or the YouTube video itself
// (to check tokens against what's on screen). Callers drive it through a
// controller that speaks clip-relative seconds (0 = clip start, before the
// onset shift), whichever source is showing.

export type ClipMediaSource = "audio" | "video";

export type ClipMediaController = {
  /** Clip-relative seconds at the playhead. */
  currentTime(): number;
  paused(): boolean;
  /** Plays, from `clipSeconds` when given. */
  play(clipSeconds?: number): void;
  pause(): void;
};

type YTPlayer = {
  playVideo(): void;
  pauseVideo(): void;
  seekTo(seconds: number, allowSeekAhead: boolean): void;
  getCurrentTime(): number;
  getPlayerState(): number;
  destroy(): void;
};

type YTNamespace = {
  Player: new (
    element: HTMLElement,
    options: {
      videoId: string;
      width?: string | number;
      height?: string | number;
      playerVars?: Record<string, string | number>;
      events?: { onReady?: () => void };
    }
  ) => YTPlayer;
};

declare global {
  interface Window {
    YT?: YTNamespace;
    onYouTubeIframeAPIReady?: () => void;
  }
}

const YT_PLAYING = 1;
const YT_BUFFERING = 3;

let apiPromise: Promise<YTNamespace> | null = null;

function loadYouTubeApi(): Promise<YTNamespace> {
  if (window.YT?.Player) return Promise.resolve(window.YT);
  apiPromise ??= new Promise((resolve) => {
    const previous = window.onYouTubeIframeAPIReady;
    window.onYouTubeIframeAPIReady = () => {
      previous?.();
      resolve(window.YT!);
    };
    const script = document.createElement("script");
    script.src = "https://www.youtube.com/iframe_api";
    script.async = true;
    document.head.appendChild(script);
  });
  return apiPromise;
}

export type ClipMediaProps = {
  videoId: string;
  /** Video time of the clip's start/end. */
  startSec: number;
  endSec: number;
  portrait: boolean;
  audioUrl: string;
};

export function ClipMedia({
  videoId,
  startSec,
  endSec,
  portrait,
  audioUrl,
  controllerRef,
  preload = "metadata",
  videoOnly = false,
  className,
}: ClipMediaProps & {
  controllerRef?: Ref<ClipMediaController>;
  preload?: "auto" | "metadata";
  /** Always the YouTube video, no source toggle (the whole-video page). */
  videoOnly?: boolean;
  className?: string;
}) {
  const [storedSource, setSource] = usePersistentState<ClipMediaSource>(
    "experiments.clips.playerSource",
    "video"
  );
  const source: ClipMediaSource = videoOnly ? "video" : storedSource;
  const audioRef = useRef<HTMLAudioElement>(null);
  const hostRef = useRef<HTMLDivElement>(null);
  const ytRef = useRef<YTPlayer | null>(null);
  // A play() before the iframe is ready waits here.
  const pendingRef = useRef<number | null | undefined>(undefined);

  useEffect(() => {
    if (source !== "video" || !hostRef.current) return;
    let cancelled = false;
    let player: YTPlayer | null = null;
    const mount = document.createElement("div");
    hostRef.current.appendChild(mount);
    void loadYouTubeApi().then((YT) => {
      if (cancelled) return;
      player = new YT.Player(mount, {
        videoId,
        width: "100%",
        height: "100%",
        playerVars: {
          start: Math.floor(startSec),
          end: Math.ceil(endSec),
          playsinline: 1,
          rel: 0,
          modestbranding: 1,
        },
        events: {
          onReady: () => {
            if (cancelled || !player) return;
            ytRef.current = player;
            const pending = pendingRef.current;
            pendingRef.current = undefined;
            if (pending !== undefined) {
              if (pending !== null) player.seekTo(startSec + pending, true);
              player.playVideo();
            }
          },
        },
      });
    });
    return () => {
      cancelled = true;
      ytRef.current = null;
      player?.destroy();
      mount.remove();
    };
  }, [source, videoId, startSec, endSec]);

  useImperativeHandle(
    controllerRef,
    () => ({
      currentTime() {
        if (source === "video") {
          const player = ytRef.current;
          return player ? player.getCurrentTime() - startSec : 0;
        }
        return audioRef.current?.currentTime ?? 0;
      },
      paused() {
        if (source === "video") {
          const state = ytRef.current?.getPlayerState();
          return state !== YT_PLAYING && state !== YT_BUFFERING;
        }
        return audioRef.current?.paused ?? true;
      },
      play(clipSeconds) {
        if (source === "video") {
          const player = ytRef.current;
          if (!player) {
            pendingRef.current = clipSeconds ?? null;
            return;
          }
          if (clipSeconds !== undefined) player.seekTo(startSec + Math.max(0, clipSeconds), true);
          player.playVideo();
          return;
        }
        const audio = audioRef.current;
        if (!audio) return;
        if (clipSeconds !== undefined) audio.currentTime = Math.max(0, clipSeconds);
        void audio.play();
      },
      pause() {
        if (source === "video") ytRef.current?.pauseVideo();
        else audioRef.current?.pause();
      },
    }),
    [source, startSec]
  );

  return (
    <div className={cn("flex flex-col gap-2", className)}>
      <div className={cn("flex items-center gap-1 text-xs", videoOnly && "hidden")}>
        {(["audio", "video"] as const).map((option) => (
          <button
            key={option}
            type="button"
            onClick={() => {
              if (option === source) return;
              audioRef.current?.pause();
              ytRef.current?.pauseVideo();
              setSource(option);
            }}
            className={cn(
              "rounded-md px-2 py-0.5 transition-colors",
              option === source
                ? "bg-primary text-primary-foreground"
                : "text-muted-foreground hover:bg-muted hover:text-foreground"
            )}
          >
            {option === "audio" ? "Clip audio" : "YouTube video"}
          </button>
        ))}
      </div>
      {source === "audio" ? (
        <audio ref={audioRef} src={audioUrl} controls preload={preload} className="w-full" />
      ) : (
        <div
          ref={hostRef}
          className={cn(
            "overflow-hidden rounded-lg bg-black",
            // Portrait: sized by height so a Short fits beside the editor without scrolling.
            portrait ? "mx-auto aspect-[9/16] h-[min(65vh,36rem)]" : "aspect-video w-full"
          )}
        />
      )}
    </div>
  );
}
