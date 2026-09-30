"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { useQuery } from "@tanstack/react-query";
import { toast } from "sonner";
import {
  ChevronLeft,
  ExternalLink,
  Pause,
  Play,
  SkipForward,
  X,
} from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button, buttonVariants } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Skeleton } from "@/components/ui/skeleton";
import {
  dialogueApi,
  scenarioSlug,
  type DialogueCollection,
  type DialogueCollectionScenario,
} from "@/lib/dialogue/client";
import { activeTokenIndexInLine } from "@/lib/dialogue/token-sync";
import {
  isSpokenLine,
  isStageLine,
  type DialogueLine,
  type PublishedToken,
  type PublishedTokenSync,
} from "@/lib/dialogue/types";
import { ttsApi } from "@/lib/tts/client";
import { cn } from "@/lib/utils";

type PlaylistItem = {
  scenarioId: string;
  slug: string;
  title: string;
  index: number; // 1-based among playable
  total: number;
  audioUrl: string;
  lines: DialogueLine[];
  tokenSync: PublishedTokenSync | null;
  /** Scenario thumb, else collection; null when neither has a URL. */
  thumbnailUrl: string | null;
};

function spokenStartSeconds(
  tokenSync: PublishedTokenSync | null,
  spokenLineIndex: number,
): number | null {
  const line = tokenSync?.lines[spokenLineIndex];
  if (!line) return null;
  const stamped = line.tokens
    .map((t) => t.startSeconds)
    .filter((s): s is number => s != null);
  return stamped.length > 0 ? Math.min(...stamped) : null;
}

function activeSpokenIndex(
  tokenSync: PublishedTokenSync | null,
  currentTime: number,
): number | null {
  if (!tokenSync?.lines.length) return null;
  let active: number | null = null;
  for (let i = 0; i < tokenSync.lines.length; i++) {
    const start = spokenStartSeconds(tokenSync, i);
    if (start != null && currentTime >= start - 0.05) active = i;
  }
  return active;
}

/** Map dialogue line index → spoken-line index (tokenSync lines). */
function spokenIndexByDialogueIndex(lines: DialogueLine[]): Map<number, number> {
  const map = new Map<number, number>();
  let spoken = 0;
  lines.forEach((line, index) => {
    if (!isSpokenLine(line)) return;
    if (!line.speaker.trim() || !line.japanese.trim()) return;
    map.set(index, spoken);
    spoken += 1;
  });
  return map;
}

function resolveThumbnailUrl(
  scenario: DialogueCollectionScenario,
  collection: DialogueCollection,
): string | null {
  return (
    scenario.thumbnailSmallUrl ??
    scenario.thumbnailUrl ??
    collection.thumbnailSmallUrl ??
    collection.thumbnailUrl ??
    null
  );
}

function PlaythroughTokenSpan({
  token,
  active,
}: {
  token: PublishedToken;
  active: boolean;
}) {
  return (
    <span
      className={cn(
        "rounded-sm px-0.5 transition-colors",
        active && "bg-primary text-primary-foreground",
      )}
    >
      {token.text}
    </span>
  );
}

function DialoguePlaybackPanel({
  lines,
  tokenSync,
  currentTime,
  playing,
  highlightedSpoken,
  onSpokenClick,
}: {
  lines: DialogueLine[];
  tokenSync: PublishedTokenSync | null;
  currentTime: number;
  playing: boolean;
  highlightedSpoken: number | null;
  onSpokenClick: (spokenIndex: number) => void;
}) {
  const spokenMap = useMemo(() => spokenIndexByDialogueIndex(lines), [lines]);
  const activeRowRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    if (!playing || highlightedSpoken == null) return;
    activeRowRef.current?.scrollIntoView({
      behavior: "smooth",
      block: "nearest",
    });
  }, [playing, highlightedSpoken]);

  if (lines.length === 0) {
    return (
      <p className="text-sm text-muted-foreground">No dialogue lines on this scene.</p>
    );
  }

  return (
    <div className="flex max-h-[min(50vh,28rem)] flex-col gap-2 overflow-y-auto rounded-lg border border-border/60 bg-muted/20 p-3">
      {lines.map((line, index) => {
        if (isStageLine(line)) {
          return (
            <div
              key={`stage-${index}`}
              className="shrink-0 rounded-md border border-dashed border-border/70 bg-background/60 px-3 py-2 text-center text-xs italic text-muted-foreground"
            >
              {line.text.trim() || "(stage)"}
              {line.visibility ? (
                <span className="ml-1 not-italic opacity-70">· {line.visibility}</span>
              ) : null}
            </div>
          );
        }
        if (!isSpokenLine(line)) {
          return (
            <div
              key={`other-${index}`}
              className="shrink-0 px-2 py-1 text-xs text-muted-foreground"
            >
              {line.type === "inline-question"
                ? `Checkpoint: ${line.prompt}`
                : "—"}
            </div>
          );
        }
        const spokenIdx = spokenMap.get(index);
        const isActive =
          spokenIdx != null && spokenIdx === highlightedSpoken;
        const syncLine =
          spokenIdx != null ? (tokenSync?.lines[spokenIdx] ?? null) : null;
        const hasTokenKaraoke = Boolean(syncLine?.tokens.length);
        const activeToken =
          isActive && playing && syncLine
            ? activeTokenIndexInLine(syncLine.tokens, currentTime)
            : null;

        return (
          <div
            key={`spoken-${index}`}
            ref={isActive ? activeRowRef : undefined}
            role="button"
            tabIndex={0}
            onClick={() => {
              if (spokenIdx != null) onSpokenClick(spokenIdx);
            }}
            onKeyDown={(event) => {
              if (spokenIdx == null) return;
              if (event.key === "Enter" || event.key === " ") {
                event.preventDefault();
                onSpokenClick(spokenIdx);
              }
            }}
            className={cn(
              // shrink-0: rows must keep content height inside the max-h flex
              // column (md:min-h-0 from touch-target patterns collapses them).
              "shrink-0 cursor-pointer rounded-md border px-3 py-2 text-left transition-colors",
              "min-h-11 touch-manipulation",
              isActive
                ? "border-primary/40 bg-primary/5"
                : "border-border/50 bg-background/80 hover:border-border",
            )}
          >
            <div className="text-[11px] font-medium text-muted-foreground">
              {line.speaker || "Speaker"}
            </div>
            <div className="block text-sm leading-snug">
              {hasTokenKaraoke && syncLine ? (
                <span className="inline">
                  {syncLine.tokens.map((token, ti) => (
                    <PlaythroughTokenSpan
                      key={`${ti}-${token.text}`}
                      token={token}
                      active={activeToken === ti}
                    />
                  ))}
                </span>
              ) : (
                line.japanese
              )}
            </div>
            {line.english ? (
              <div className="mt-0.5 text-xs text-muted-foreground">
                {line.english}
              </div>
            ) : null}
          </div>
        );
      })}
    </div>
  );
}

async function resolveAudioUrl(
  scenario: DialogueCollectionScenario,
  collectionId: string,
): Promise<string | null> {
  if (scenario.publishedAudioUrl) return scenario.publishedAudioUrl;
  try {
    const { project } = await dialogueApi.getScenarioAudio(
      collectionId,
      scenarioSlug(scenario),
    );
    if (!project?.selectedVariantId) return null;
    // Prefer selected take; byte count unknown — cache-bust with project id.
    return ttsApi.variantAudioUrl(project.id, project.selectedVariantId);
  } catch {
    return null;
  }
}

/** Published CDN URLs are absolute; Studio take proxies are same-origin paths. */
function isCrossOriginAudioUrl(url: string): boolean {
  return /^https?:\/\//i.test(url);
}

async function buildPlaylist(
  collection: DialogueCollection,
): Promise<{ items: PlaylistItem[]; skipped: number }> {
  const ordered = [...collection.scenarios].sort(
    (a, b) => a.orderIndex - b.orderIndex,
  );
  const resolved: Array<Omit<PlaylistItem, "index" | "total"> | null> =
    await Promise.all(
      ordered.map(async (scenario) => {
        const audioUrl = await resolveAudioUrl(scenario, collection.id);
        if (!audioUrl) return null;
        return {
          scenarioId: scenario.id,
          slug: scenarioSlug(scenario),
          title: scenario.menuTitle,
          audioUrl,
          lines: scenario.lines,
          tokenSync: scenario.tokenSync,
          thumbnailUrl: resolveThumbnailUrl(scenario, collection),
        };
      }),
    );
  const playable = resolved.filter(
    (item): item is Omit<PlaylistItem, "index" | "total"> => item != null,
  );
  const skipped = ordered.length - playable.length;
  const items = playable.map((item, i) => ({
    ...item,
    index: i + 1,
    total: playable.length,
  }));
  return { items, skipped };
}

function LessonPlaythroughSession({
  collectionId,
  lessonTitle,
  onClose,
}: {
  collectionId: string;
  lessonTitle?: string | null;
  onClose: () => void;
}) {
  const { data, isLoading, isError, error } = useQuery({
    queryKey: ["dialogue-collection", collectionId],
    queryFn: () => dialogueApi.getCollection(collectionId),
  });

  const [sceneIndex, setSceneIndex] = useState(0);
  const [playing, setPlaying] = useState(false);
  const [currentTime, setCurrentTime] = useState(0);
  const [loadingAudio, setLoadingAudio] = useState(false);
  const [selectedSpoken, setSelectedSpoken] = useState<number | null>(null);
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const rafRef = useRef<number | null>(null);
  const blobUrlRef = useRef<string | null>(null);
  const loadedScenarioIdRef = useRef<string | null>(null);
  const playlistRef = useRef<PlaylistItem[] | null>(null);
  const sceneIndexRef = useRef(0);

  const collection = data?.collection;
  const playlistQuery = useQuery({
    queryKey: [
      "lesson-playthrough-playlist",
      collectionId,
      collection?.updatedAt,
    ],
    enabled: !!collection,
    queryFn: async () => {
      if (!collection) throw new Error("Missing collection");
      return buildPlaylist(collection);
    },
    staleTime: 30_000,
  });

  const playlist = playlistQuery.data?.items ?? null;
  const skipped = playlistQuery.data?.skipped ?? 0;
  const building = playlistQuery.isLoading || playlistQuery.isFetching;

  useEffect(() => {
    playlistRef.current = playlist;
  }, [playlist]);

  useEffect(() => {
    sceneIndexRef.current = sceneIndex;
  }, [sceneIndex]);

  const current = playlist?.[sceneIndex] ?? null;

  const stopRaf = useCallback(() => {
    if (rafRef.current != null) {
      cancelAnimationFrame(rafRef.current);
      rafRef.current = null;
    }
  }, []);

  const cleanupAudio = useCallback(() => {
    stopRaf();
    const audio = audioRef.current;
    if (audio) {
      audio.pause();
      audio.onended = null;
      audio.removeAttribute("src");
      audio.load();
    }
    audioRef.current = null;
    loadedScenarioIdRef.current = null;
    if (blobUrlRef.current) {
      URL.revokeObjectURL(blobUrlRef.current);
      blobUrlRef.current = null;
    }
    setPlaying(false);
    setCurrentTime(0);
  }, [stopRaf]);

  useEffect(() => () => cleanupAudio(), [cleanupAudio]);

  const startRaf = useCallback(() => {
    stopRaf();
    const tick = () => {
      const audio = audioRef.current;
      if (audio && Number.isFinite(audio.currentTime)) {
        setCurrentTime(audio.currentTime);
      }
      rafRef.current = requestAnimationFrame(tick);
    };
    rafRef.current = requestAnimationFrame(tick);
  }, [stopRaf]);

  const ensureAudio = useCallback(
    async (item: PlaylistItem): Promise<HTMLAudioElement> => {
      if (
        audioRef.current &&
        loadedScenarioIdRef.current === item.scenarioId
      ) {
        return audioRef.current;
      }

      cleanupAudio();
      setLoadingAudio(true);
      try {
        let src = item.audioUrl;
        // Published CDN audio is cross-origin without CORS for fetch(); media
        // elements can play it directly. Same-origin Studio take URLs still go
        // through blob fetch for Safari (HTMLAudioElement.src on /api can fail).
        if (!isCrossOriginAudioUrl(item.audioUrl)) {
          const res = await fetch(item.audioUrl, { credentials: "same-origin" });
          if (!res.ok) {
            throw new Error(
              res.status === 404
                ? "Scene audio was not found."
                : `Could not load audio (${res.status}).`,
            );
          }
          const contentType = res.headers.get("content-type") ?? "";
          const buffer = await res.arrayBuffer();
          if (buffer.byteLength === 0) throw new Error("Scene has no audio.");
          const mime = contentType.startsWith("audio/")
            ? contentType.split(";")[0]!.trim()
            : item.audioUrl.includes(".m4a")
              ? "audio/mp4"
              : "audio/wav";
          const blob = new Blob([buffer], { type: mime });
          const objectUrl = URL.createObjectURL(blob);
          blobUrlRef.current = objectUrl;
          src = objectUrl;
        }
        const audio = new Audio();
        audio.preload = "auto";
        audio.src = src;
        audio.onended = () => {
          setPlaying(false);
          stopRaf();
          const list = playlistRef.current;
          const prev = sceneIndexRef.current;
          const next = prev + 1;
          if (list && next < list.length) {
            // Advance without autoplay — tear down clip; wait for Play.
            audio.onended = null;
            audio.removeAttribute("src");
            audio.load();
            audioRef.current = null;
            loadedScenarioIdRef.current = null;
            if (blobUrlRef.current) {
              URL.revokeObjectURL(blobUrlRef.current);
              blobUrlRef.current = null;
            }
            setCurrentTime(0);
            setSelectedSpoken(null);
            setSceneIndex(next);
            return;
          }
          // Last scene: rewind so Play restarts from the beginning.
          audio.currentTime = 0;
          setCurrentTime(0);
        };
        audioRef.current = audio;
        loadedScenarioIdRef.current = item.scenarioId;
        if (audio.readyState < HTMLMediaElement.HAVE_METADATA) {
          await new Promise<void>((resolve, reject) => {
            const onReady = () => {
              cleanup();
              resolve();
            };
            const onError = () => {
              cleanup();
              reject(new Error("Could not load scene audio."));
            };
            const cleanup = () => {
              audio.removeEventListener("loadedmetadata", onReady);
              audio.removeEventListener("error", onError);
            };
            audio.addEventListener("loadedmetadata", onReady);
            audio.addEventListener("error", onError);
          });
        }
        // Scene may have changed while we were loading.
        if (
          playlistRef.current?.[sceneIndexRef.current]?.scenarioId !==
          item.scenarioId
        ) {
          cleanupAudio();
          throw new Error("Scene changed before audio was ready.");
        }
        return audio;
      } catch (err) {
        cleanupAudio();
        throw err;
      } finally {
        setLoadingAudio(false);
      }
    },
    [cleanupAudio, stopRaf],
  );

  const playFrom = useCallback(
    async (item: PlaylistItem, startSeconds?: number | null) => {
      try {
        const audio = await ensureAudio(item);
        // Only seek when explicitly requested (line click). Fresh loads start
        // at 0 naturally; a pause→Play resume must not pass through here with
        // a forced seek, and must not reset currentTime when reusing the clip.
        if (startSeconds != null && Number.isFinite(startSeconds)) {
          audio.currentTime = Math.max(0, startSeconds);
          setCurrentTime(audio.currentTime);
        } else {
          setCurrentTime(audio.currentTime);
        }
        await audio.play();
        setPlaying(true);
        startRaf();
      } catch (err) {
        const message =
          err instanceof Error ? err.message : "Could not play scene audio.";
        // Scene-change abort is expected; don't toast.
        if (message.includes("Scene changed")) return;
        toast.error(message);
        setPlaying(false);
      }
    },
    [ensureAudio, startRaf],
  );

  function togglePlay() {
    if (!current) return;
    const audio = audioRef.current;
    const loadedHere =
      audio != null && loadedScenarioIdRef.current === current.scenarioId;

    // Same scene already loaded: pause or resume in place — never reload.
    if (loadedHere) {
      if (!audio.paused) {
        audio.pause();
        setPlaying(false);
        stopRaf();
        setCurrentTime(audio.currentTime);
        return;
      }
      // Resume from audio.currentTime (RAF ticker only; no seek / no reload).
      setCurrentTime(audio.currentTime);
      void audio
        .play()
        .then(() => {
          setPlaying(true);
          startRaf();
        })
        .catch((err: unknown) => {
          const message =
            err instanceof Error ? err.message : "Could not play scene audio.";
          toast.error(message);
          setPlaying(false);
        });
      return;
    }

    // Unloaded / different scene: load and start (clip begins at 0).
    void playFrom(current);
  }

  function goTo(index: number) {
    if (!playlist || index < 0 || index >= playlist.length) return;
    if (index === sceneIndex) return;
    cleanupAudio();
    setSelectedSpoken(null);
    setSceneIndex(index);
  }

  function handleSpokenClick(spokenIndex: number) {
    setSelectedSpoken(spokenIndex);
    if (!current) return;
    const start = spokenStartSeconds(current.tokenSync, spokenIndex);
    if (start == null) return;
    void playFrom(current, start);
  }

  const timingActive =
    playing && current
      ? activeSpokenIndex(current.tokenSync, currentTime)
      : null;
  const highlightedSpoken =
    timingActive != null ? timingActive : selectedSpoken;

  if (isLoading || building) {
    return (
      <div className="flex flex-col gap-3 p-1">
        <Skeleton className="h-6 w-48" />
        <Skeleton className="h-40 w-full" />
      </div>
    );
  }

  if (isError || !data?.collection) {
    return (
      <p className="text-sm text-destructive">
        {error instanceof Error ? error.message : "Could not load lesson."}
      </p>
    );
  }

  if (!playlist || playlist.length === 0) {
    return (
      <div className="flex flex-col gap-3">
        <p className="text-sm text-muted-foreground">
          No scenes with published or selected take audio in{" "}
          <span className="font-medium text-foreground">
            {lessonTitle ?? data.collection.title}
          </span>
          . Publish a scene (Gate A) or select a take, then try again.
        </p>
        <Button type="button" variant="outline" size="sm" onClick={onClose}>
          Close
        </Button>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-wrap items-center gap-2">
        <Badge variant="secondary" className="tabular-nums">
          Scene {current?.index ?? 0} of {current?.total ?? 0}
        </Badge>
        {skipped > 0 && (
          <span className="text-xs text-muted-foreground">
            {skipped} scene{skipped === 1 ? "" : "s"} skipped (no audio)
          </span>
        )}
      </div>
      <div className="flex items-start gap-3">
        {current?.thumbnailUrl ? (
          // eslint-disable-next-line @next/next/no-img-element -- CDN lesson thumbs; arbitrary host
          <img
            src={current.thumbnailUrl}
            alt=""
            className="size-14 shrink-0 rounded-md border border-border/60 object-cover md:size-16"
          />
        ) : null}
        <div className="min-w-0">
          <div className="truncate text-base font-medium">
            {current?.title ?? "—"}
          </div>
          <div className="text-xs text-muted-foreground">
            {lessonTitle ?? data.collection.title}
          </div>
        </div>
      </div>
      <div className="flex flex-wrap items-center gap-2">
        <Button
          type="button"
          size="sm"
          variant="outline"
          className="min-h-11 touch-manipulation md:min-h-8"
          disabled={sceneIndex <= 0}
          onClick={() => goTo(sceneIndex - 1)}
        >
          <ChevronLeft className="size-3.5" />
          <span className="ml-1">Prev</span>
        </Button>
        <Button
          type="button"
          size="sm"
          className="min-h-11 touch-manipulation md:min-h-8"
          disabled={loadingAudio || !current}
          onClick={togglePlay}
        >
          {playing ? (
            <Pause className="size-3.5" />
          ) : (
            <Play className="size-3.5" />
          )}
          <span className="ml-1.5">
            {loadingAudio ? "Loading…" : playing ? "Pause" : "Play"}
          </span>
        </Button>
        <Button
          type="button"
          size="sm"
          variant="outline"
          className="min-h-11 touch-manipulation md:min-h-8"
          disabled={!playlist || sceneIndex >= playlist.length - 1}
          onClick={() => goTo(sceneIndex + 1)}
        >
          <SkipForward className="size-3.5" />
          <span className="ml-1">Next</span>
        </Button>
        <Button
          type="button"
          size="sm"
          variant="ghost"
          className="ml-auto min-h-11 touch-manipulation md:min-h-8"
          onClick={() => {
            cleanupAudio();
            onClose();
          }}
        >
          <X className="size-3.5" />
          <span className="ml-1">Close</span>
        </Button>
      </div>
      {current && (
        <DialoguePlaybackPanel
          lines={current.lines}
          tokenSync={current.tokenSync}
          currentTime={currentTime}
          playing={playing}
          highlightedSpoken={highlightedSpoken}
          onSpokenClick={handleSpokenClick}
        />
      )}
      {current && (
        <div className="flex flex-wrap items-center gap-2">
          <Link
            href={`/content/dialogues/${collectionId}/${current.slug}?tab=audio`}
            className={cn(
              buttonVariants({ variant: "outline", size: "sm" }),
              "min-h-11 touch-manipulation md:min-h-8",
            )}
            title="Open this scene's audio panel to review timing and approve"
            onClick={() => {
              cleanupAudio();
              onClose();
            }}
          >
            <ExternalLink className="size-3.5" />
            <span className="ml-1">Open scene audio</span>
          </Link>
        </div>
      )}
      <p className="text-[11px] text-muted-foreground">
        Press Play to start each scene. Click a spoken line to seek when
        stamps exist. Stage lines are shown between spoken lines — karaoke
        follows published token stamps when present.
      </p>
    </div>
  );
}

/**
 * Studio v1: play a lesson's scenes back-to-back with a minimal learner-like
 * dialogue panel (stage lines + spoken karaoke when stamps exist).
 */
export function LessonPlaythroughButton({
  collectionId,
  lessonTitle,
  className,
  size = "sm",
  variant = "outline",
  label = "Play all scenes",
}: {
  collectionId: string;
  lessonTitle?: string | null;
  className?: string;
  size?: "sm" | "default";
  variant?: "outline" | "ghost" | "secondary";
  label?: string;
}) {
  const [open, setOpen] = useState(false);

  return (
    <>
      <Button
        type="button"
        size={size}
        variant={variant}
        className={cn("min-h-11 touch-manipulation md:min-h-8", className)}
        onClick={() => setOpen(true)}
        title="Listen to this lesson's scenes in order (Studio preview)"
      >
        <Play className="size-3.5" />
        <span className="ml-1.5">{label}</span>
      </Button>
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="flex max-h-[90vh] flex-col overflow-y-auto sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>Lesson playthrough</DialogTitle>
          </DialogHeader>
          {open && (
            <LessonPlaythroughSession
              collectionId={collectionId}
              lessonTitle={lessonTitle}
              onClose={() => setOpen(false)}
            />
          )}
        </DialogContent>
      </Dialog>
    </>
  );
}
