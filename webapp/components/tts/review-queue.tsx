"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import {
  Check,
  ChevronDown,
  ChevronRight,
  ExternalLink,
  Pause,
  Play,
  Upload,
} from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { dialogueApi } from "@/lib/dialogue/client";
import { derivePublishPipeline } from "@/lib/dialogue/publish-pipeline";
import { ttsApi, type ReviewQueueResult } from "@/lib/tts/client";
import type { TokenSyncFlag } from "@/lib/dialogue/types";
import { activeTokenIndexInLine } from "@/lib/dialogue/token-sync";
import { cn } from "@/lib/utils";

const FLAG_LABEL: Record<TokenSyncFlag["code"], string> = {
  "stamp-in-silence": "stamp in silence",
  "script-mismatch": "script mismatch",
  "reading-fallback": "reading fallback",
  "no-gap": "no gap",
};

type Take = ReviewQueueResult["takes"][number];
type FlaggedLine = Take["flaggedLines"][number];
type KaraokeLine = Take["lines"][number];
type KaraokeToken = KaraokeLine["tokens"][number];

type LessonGroup = {
  key: string;
  collectionId: string | null;
  title: string;
  isActive: boolean | null;
  takes: Take[];
};

function minutes(from?: string, to?: string): string | null {
  if (!from || !to) return null;
  const m = (new Date(to).getTime() - new Date(from).getTime()) / 60000;
  return m >= 0 ? `${m < 10 ? m.toFixed(1) : Math.round(m)} min` : null;
}

function fmt(n: number | null, unit = ""): string {
  return n == null ? "—" : `${n < 10 ? n.toFixed(1) : Math.round(n)}${unit}`;
}

/** Deep-link into scene Audio → Token timing focused on a spoken line. */
function editorHref(take: Take, lineIndex?: number): string {
  const lineQs =
    lineIndex != null ? `&line=${lineIndex}&timing=tokens` : "";
  if (take.collectionId && take.slug) {
    return `/content/dialogues/${take.collectionId}/${take.slug}?tab=audio&take=${take.variantId}${lineQs}`;
  }
  return `/tts/${take.projectId}?take=${take.variantId}${lineQs}`;
}

function groupTakesByLesson(takes: Take[]): LessonGroup[] {
  const groups: LessonGroup[] = [];
  const indexByKey = new Map<string, number>();
  for (const take of takes) {
    const key = take.collectionId ?? `project:${take.projectId}`;
    const existing = indexByKey.get(key);
    if (existing != null) {
      groups[existing]!.takes.push(take);
      continue;
    }
    indexByKey.set(key, groups.length);
    groups.push({
      key,
      collectionId: take.collectionId,
      title: take.collectionTitle ?? take.collectionId ?? "Unlinked takes",
      isActive: take.collectionIsActive,
      takes: [take],
    });
  }
  return groups;
}

function PipelineSteps({ take }: { take: Take }) {
  const pipeline = derivePublishPipeline({
    hasFlags: take.flagCount > 0,
    isPublishedTake: take.isPublishedTake,
    collectionIsActive: take.collectionIsActive,
  });
  const steps: Array<{
    key: keyof typeof pipeline.reached;
    label: string;
    reached: boolean;
  }> = [
    { key: "staged", label: "Staged", reached: pipeline.reached.staged },
    {
      key: "inDatabase",
      label: "In database",
      reached: pipeline.reached.inDatabase,
    },
    {
      key: "clientVisible",
      label: "Client-visible",
      reached: pipeline.reached.clientVisible,
    },
  ];
  return (
    <div
      className="flex flex-wrap items-center gap-1.5 text-[11px]"
      title="Publish pipeline: Gate A lands in the database; Gate B makes the lesson visible to learners."
    >
      <span className="text-muted-foreground">Pipeline</span>
      {steps.map((step, index) => (
        <span key={step.key} className="inline-flex items-center gap-1.5">
          {index > 0 && (
            <span className="text-muted-foreground/60" aria-hidden>
              →
            </span>
          )}
          <span
            className={cn(
              "inline-flex items-center gap-1 rounded border px-1.5 py-0.5",
              step.reached
                ? step.key === "clientVisible"
                  ? "border-foreground/40 bg-foreground text-background"
                  : "border-emerald-500/50 bg-emerald-500/10 text-emerald-700 dark:text-emerald-300"
                : "border-border/60 text-muted-foreground",
            )}
          >
            <span aria-hidden>{step.reached ? "●" : "○"}</span>
            {step.label}
          </span>
        </span>
      ))}
    </div>
  );
}

function TimingSummary({ timing }: { timing: ReviewQueueResult["timing"] }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Open-to-publish timing</CardTitle>
      </CardHeader>
      <CardContent className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead className="text-left text-xs text-muted-foreground">
            <tr>
              <th className="py-1 pr-4 font-medium">Source</th>
              <th className="py-1 pr-4 font-medium">Published takes</th>
              <th className="py-1 pr-4 font-medium">Median open → publish</th>
              <th className="py-1 pr-4 font-medium">Lines untouched</th>
              <th className="py-1 pr-4 font-medium">Takes with a &gt;200 ms fix</th>
            </tr>
          </thead>
          <tbody>
            {timing.bySource.map((row) => (
              <tr key={row.source} className="border-t border-border/60">
                <td className="py-1.5 pr-4 font-medium">
                  {row.source === "auto" ? "auto / reviewed" : "hand-stamped"}
                </td>
                <td className="py-1.5 pr-4 tabular-nums">{row.published}</td>
                <td className="py-1.5 pr-4 tabular-nums">
                  {fmt(row.medianOpenToPublishMinutes, " min")}
                  {row.withOpenTiming < row.published && (
                    <span className="ml-1 text-xs text-muted-foreground">
                      ({row.withOpenTiming} timed)
                    </span>
                  )}
                </td>
                <td className="py-1.5 pr-4 tabular-nums">
                  {fmt(row.linesUntouchedPct, "%")}
                </td>
                <td className="py-1.5 pr-4 tabular-nums">
                  {fmt(row.correctionsOver200msPct, "%")}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        <p className="mt-2 text-xs text-muted-foreground">
          Clock starts the first time a take is opened in Token timing and stops
          at publish. v1 bar: ≥ 80% of lines untouched, ≤ 4 min per scene.
          {timing.since
            ? ` Measuring since ${new Date(timing.since).toLocaleDateString()}.`
            : " No published takes measured yet."}
        </p>
      </CardContent>
    </Card>
  );
}

/**
 * Match Token timing chips: stamped sky base, amber when flagged, primary fill
 * while playing — no extra ring (that made queue karaoke look “off”).
 */
function KaraokeTokenChip({
  token,
  active,
}: {
  token: KaraokeToken;
  active: boolean;
}) {
  const untimed = token.startSeconds == null;
  const flagged = token.codes.length > 0;
  return (
    <span
      title={token.codes.map((c) => FLAG_LABEL[c]).join("; ") || undefined}
      className={cn(
        "mx-px inline-block whitespace-nowrap rounded-md border px-1.5 py-1 align-middle md:px-1 md:py-px",
        untimed && "border-dashed border-rose-400 bg-rose-500/15",
        !untimed && "border-sky-500/30 bg-sky-500/10",
        flagged && "border-amber-500/70 bg-amber-500/15",
        active && !untimed && "border-primary bg-primary/15",
      )}
    >
      {token.text}
    </span>
  );
}

function FlaggedLine({
  line,
  editorHref: lineEditorHref,
  playing,
  activeTokenIndex,
  checked,
  playDisabled,
  onPlay,
  onToggleChecked,
}: {
  line: FlaggedLine;
  editorHref: string;
  playing: boolean;
  activeTokenIndex: number | null;
  /** Optional local QA progress — not required to Approve the take. */
  checked: boolean;
  /** True while audio is loading or take has no bytes. */
  playDisabled: boolean;
  onPlay: () => void;
  onToggleChecked: () => void;
}) {
  const canPlay = line.playFromSeconds != null && !playDisabled;
  return (
    <div
      className={cn(
        "flex flex-wrap items-start gap-2 rounded-md border px-2 py-1.5 transition-colors",
        playing ? "border-primary/50 bg-primary/5" : "border-transparent",
      )}
    >
      <Button
        type="button"
        size="sm"
        variant="outline"
        className="min-h-10 shrink-0 touch-manipulation md:min-h-8"
        disabled={!canPlay && !playing}
        onClick={onPlay}
        title={
          playing
            ? `Stop line ${line.lineIndex + 1}`
            : playDisabled
              ? "Take audio is not ready"
              : line.playFromSeconds != null
                ? `Play line ${line.lineIndex + 1} from the stamps`
                : "No timing on this line yet"
        }
      >
        {playing ? (
          <Pause className="size-3.5" />
        ) : (
          <Play className="size-3.5" />
        )}
        <span className="ml-1">L{line.lineIndex + 1}</span>
      </Button>
      {/* Same wrap as chips so Check+Jump sit immediately after the last token. */}
      <div className="flex min-w-0 flex-wrap items-center gap-x-1 gap-y-1 text-sm leading-relaxed">
        {line.lineCodes.map((code) => (
          <span
            key={code}
            className="rounded border border-amber-500/50 px-1 text-[10px] font-medium text-amber-700 dark:text-amber-300"
          >
            {FLAG_LABEL[code]}
          </span>
        ))}
        {line.tokens.map((token, i) => (
          <KaraokeTokenChip
            key={`${i}-${token.text}`}
            token={token}
            active={playing && activeTokenIndex === i}
          />
        ))}
        <div className="ml-2 inline-flex shrink-0 items-center gap-1">
          <Button
            type="button"
            size="sm"
            variant="outline"
            className={cn(
              "min-h-10 touch-manipulation md:min-h-8",
              checked
                ? "border-emerald-500/60 bg-emerald-500/15 text-emerald-700 dark:text-emerald-300"
                : "border-border/60",
            )}
            onClick={onToggleChecked}
            title={
              checked
                ? `Uncheck line ${line.lineIndex + 1}`
                : `Optional: check line ${line.lineIndex + 1} after listening`
            }
            aria-pressed={checked}
            aria-label={
              checked
                ? `Line ${line.lineIndex + 1} checked`
                : `Check line ${line.lineIndex + 1}`
            }
          >
            <Check
              className={cn(
                "size-3.5",
                checked && "text-emerald-600 dark:text-emerald-400",
              )}
            />
          </Button>
          <Link
            href={lineEditorHref}
            className="inline-flex min-h-10 items-center justify-center rounded-lg border border-border/60 px-2 text-muted-foreground touch-manipulation hover:text-foreground md:min-h-8"
            title={`Open Token timing on line ${line.lineIndex + 1}`}
            aria-label={`Open line ${line.lineIndex + 1} in editor`}
          >
            <ExternalLink className="size-3.5" />
          </Link>
        </div>
      </div>
    </div>
  );
}

function TakeKaraoke({
  lines,
  currentTime,
  playing,
}: {
  lines: KaraokeLine[];
  currentTime: number;
  playing: boolean;
}) {
  return (
    <div className="flex flex-col gap-1.5 rounded-md border border-border/60 bg-muted/20 px-2 py-2">
      {lines.map((line) => {
        // Same rule as TokenSyncEditor: each line’s latest started token.
        const activeTokenIndex = playing
          ? activeTokenIndexInLine(line.tokens, currentTime)
          : null;
        return (
          <div
            key={line.lineIndex}
            className={cn(
              "flex flex-wrap items-baseline gap-x-1 gap-y-1 rounded px-1 py-0.5 text-sm leading-relaxed transition-colors",
              activeTokenIndex != null && "bg-primary/5",
            )}
          >
            <span className="mr-1 font-mono text-[10px] text-muted-foreground">
              L{line.lineIndex + 1}
            </span>
            {line.tokens.map((token, i) => (
              <KaraokeTokenChip
                key={`${i}-${token.text}`}
                token={token}
                active={activeTokenIndex === i}
              />
            ))}
          </div>
        );
      })}
    </div>
  );
}

function TakeCard({
  take,
  onInteract,
}: {
  take: Take;
  onInteract?: () => void;
}) {
  const queryClient = useQueryClient();
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const blobUrlRef = useRef<string | null>(null);
  const loadPromiseRef = useRef<Promise<HTMLAudioElement> | null>(null);
  const stopTimerRef = useRef<number | null>(null);
  const rafRef = useRef<number | null>(null);
  const [playingKey, setPlayingKey] = useState<string | null>(null);
  const [currentTime, setCurrentTime] = useState(0);
  const [audioLoading, setAudioLoading] = useState(false);
  // Optional local line checks for deeper QA — Approve clears flags take-wide.
  const [checkedLines, setCheckedLines] = useState<Set<number>>(
    () => new Set(),
  );

  const audioUrl = ttsApi.variantAudioUrl(
    take.projectId,
    take.variantId,
    take.audioByteCount,
  );
  const hasAudioBytes = take.audioByteCount > 0;
  const canPublishAndComplete = !!(
    take.collectionId &&
    take.slug &&
    hasAudioBytes
  );

  useEffect(() => {
    return () => {
      if (stopTimerRef.current != null) {
        window.clearTimeout(stopTimerRef.current);
      }
      if (rafRef.current != null) cancelAnimationFrame(rafRef.current);
      const audio = audioRef.current;
      if (audio) {
        audio.pause();
        audio.removeAttribute("src");
        audio.load();
      }
      if (blobUrlRef.current) {
        URL.revokeObjectURL(blobUrlRef.current);
        blobUrlRef.current = null;
      }
      audioRef.current = null;
      loadPromiseRef.current = null;
    };
  }, []);

  // Poll media clock while playing — timeupdate is too coarse vs Token timing’s
  // audioprocess/playhead and made stamps look slightly late in the queue.
  useEffect(() => {
    if (playingKey == null) {
      if (rafRef.current != null) {
        cancelAnimationFrame(rafRef.current);
        rafRef.current = null;
      }
      return;
    }
    const tick = () => {
      const audio = audioRef.current;
      if (audio && Number.isFinite(audio.currentTime)) {
        setCurrentTime(audio.currentTime);
      }
      rafRef.current = requestAnimationFrame(tick);
    };
    rafRef.current = requestAnimationFrame(tick);
    return () => {
      if (rafRef.current != null) {
        cancelAnimationFrame(rafRef.current);
        rafRef.current = null;
      }
    };
  }, [playingKey]);

  const approveMutation = useMutation({
    mutationFn: () => ttsApi.markReviewed(take.projectId, take.variantId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["tts-review-queue"] });
      toast.success("Marked reviewed. Flags cleared.");
      onInteract?.();
    },
    onError: (error) => toast.error(error.message),
  });

  /**
   * Gate A only: select take → publish scenario audio to DB/CDN → mark reviewed.
   * Never flips lesson `isActive` (Gate B).
   * Publish runs before mark-reviewed so a failed Gate A keeps the take in queue.
   */
  const publishAndCompleteMutation = useMutation({
    mutationFn: async () => {
      if (!take.collectionId || !take.slug) {
        throw new Error("This take is not linked to a dialogue scene.");
      }
      if (!take.isSelectedTake) {
        await ttsApi.selectVariant(take.projectId, take.variantId);
      }
      const published = await dialogueApi.publishScenario(
        take.collectionId,
        take.slug,
      );
      await ttsApi.markReviewed(take.projectId, take.variantId);
      return published;
    },
    onSuccess: (result) => {
      queryClient.invalidateQueries({ queryKey: ["tts-review-queue"] });
      queryClient.invalidateQueries({ queryKey: ["dialogue-collections"] });
      queryClient.invalidateQueries({ queryKey: ["dialogue-collection"] });
      queryClient.invalidateQueries({ queryKey: ["dialogue-scenario"] });
      queryClient.invalidateQueries({
        queryKey: ["dialogue-collection-audio-status"],
      });
      toast.success(
        result.hasTokenKaraoke
          ? "Published to database with karaoke · marked complete. Lesson visibility unchanged."
          : "Published to database · marked complete. Lesson visibility unchanged.",
      );
      onInteract?.();
    },
    onError: (error) => toast.error(error.message),
  });

  function toggleLineChecked(lineIndex: number) {
    onInteract?.();
    setCheckedLines((prev) => {
      const next = new Set(prev);
      if (next.has(lineIndex)) next.delete(lineIndex);
      else next.add(lineIndex);
      return next;
    });
  }

  function clearStopTimer() {
    if (stopTimerRef.current != null) {
      window.clearTimeout(stopTimerRef.current);
      stopTimerRef.current = null;
    }
  }

  function stopPlayback() {
    clearStopTimer();
    audioRef.current?.pause();
    setPlayingKey(null);
  }

  /**
   * Same path as WaveSurfer: fetch the take WAV, then play a blob: URL.
   * Assigning the API path to HTMLAudioElement.src can fail on Safari/Mac with
   * "This Element has no supported sources" even when the waveform player works.
   */
  function ensureAudio(): Promise<HTMLAudioElement> {
    if (audioRef.current?.src) {
      return Promise.resolve(audioRef.current);
    }
    if (loadPromiseRef.current) return loadPromiseRef.current;

    if (!hasAudioBytes) {
      return Promise.reject(new Error("This take has no audio."));
    }

    setAudioLoading(true);
    const promise = (async () => {
      const res = await fetch(audioUrl, { credentials: "same-origin" });
      if (!res.ok) {
        throw new Error(
          res.status === 404
            ? "Take audio was not found."
            : `Could not load take audio (${res.status}).`,
        );
      }
      const contentType = res.headers.get("content-type") ?? "";
      if (
        contentType.includes("application/json") ||
        contentType.includes("text/html")
      ) {
        throw new Error("Take audio response was not audio data.");
      }
      const buffer = await res.arrayBuffer();
      if (buffer.byteLength === 0) {
        throw new Error("This take has no audio.");
      }
      const mime = contentType.startsWith("audio/")
        ? contentType.split(";")[0]!.trim()
        : "audio/wav";
      const blob = new Blob([buffer], { type: mime });
      const objectUrl = URL.createObjectURL(blob);
      if (blobUrlRef.current) URL.revokeObjectURL(blobUrlRef.current);
      blobUrlRef.current = objectUrl;

      const audio = audioRef.current ?? new Audio();
      audio.preload = "auto";
      audio.onended = () => {
        setPlayingKey(null);
        if (rafRef.current != null) {
          cancelAnimationFrame(rafRef.current);
          rafRef.current = null;
        }
      };
      audio.src = objectUrl;
      audioRef.current = audio;

      if (audio.readyState < HTMLMediaElement.HAVE_METADATA) {
        await new Promise<void>((resolve, reject) => {
          const onReady = () => {
            cleanup();
            resolve();
          };
          const onError = () => {
            cleanup();
            reject(new Error("Could not load take audio."));
          };
          const cleanup = () => {
            audio.removeEventListener("loadedmetadata", onReady);
            audio.removeEventListener("error", onError);
          };
          audio.addEventListener("loadedmetadata", onReady);
          audio.addEventListener("error", onError);
        });
      }
      return audio;
    })();

    loadPromiseRef.current = promise.then(
      (audio) => {
        setAudioLoading(false);
        return audio;
      },
      (error) => {
        setAudioLoading(false);
        loadPromiseRef.current = null;
        throw error;
      },
    );
    return loadPromiseRef.current;
  }

  async function playSegment(
    key: string,
    fromSeconds: number,
    untilSeconds: number | null,
  ) {
    if (playingKey === key) {
      stopPlayback();
      return;
    }
    if (!hasAudioBytes) {
      toast.error("This take has no audio.");
      return;
    }
    clearStopTimer();
    try {
      onInteract?.();
      const audio = await ensureAudio();
      audio.pause();
      audio.currentTime = fromSeconds;
      setCurrentTime(fromSeconds);
      await audio.play();
      setPlayingKey(key);
      if (untilSeconds != null && untilSeconds > fromSeconds) {
        const ms = Math.max(200, (untilSeconds - fromSeconds) * 1000);
        stopTimerRef.current = window.setTimeout(() => {
          audio.pause();
          setPlayingKey(null);
          stopTimerRef.current = null;
        }, ms);
      }
    } catch (error) {
      setPlayingKey(null);
      const message =
        error instanceof Error && error.message
          ? error.message
          : "Could not play audio.";
      if (
        message.includes("no supported sources") ||
        message.includes("NotSupportedError")
      ) {
        toast.error("Could not load take audio.");
      } else {
        toast.error(message);
      }
    }
  }

  async function playLine(line: FlaggedLine) {
    if (line.playFromSeconds == null) {
      toast.error("No timing available for this line.");
      return;
    }
    await playSegment(
      `${take.variantId}:${line.lineIndex}`,
      line.playFromSeconds,
      line.playUntilSeconds,
    );
  }

  async function playTake() {
    await playSegment(`${take.variantId}:all`, 0, null);
  }

  const playingTake = playingKey === `${take.variantId}:all`;
  const href = editorHref(take);
  const opened = take.timing?.openedAt;
  const queueLines = take.flaggedLines;
  const checkedCount = queueLines.filter((line) =>
    checkedLines.has(line.lineIndex),
  ).length;
  const allLinesChecked =
    queueLines.length === 0 || checkedCount === queueLines.length;
  const uncheckedCount = queueLines.length - checkedCount;
  const actionBusy =
    approveMutation.isPending || publishAndCompleteMutation.isPending;

  return (
    <Card>
      <CardHeader className="gap-2">
        <CardTitle className="flex flex-wrap items-center gap-2 text-base">
          <Link href={href} className="underline-offset-4 hover:underline">
            {take.title}
          </Link>
          {take.collectionId && (
            <span className="text-xs font-normal text-muted-foreground">
              {take.collectionId}
            </span>
          )}
          <Badge
            variant="outline"
            className={cn(
              queueLines.length === 0
                ? "border-emerald-500/50 text-emerald-600 dark:text-emerald-400"
                : uncheckedCount > 0
                  ? "border-amber-500/50 text-amber-600 dark:text-amber-400"
                  : "border-emerald-500/50 text-emerald-600 dark:text-emerald-400",
            )}
          >
            {queueLines.length === 0
              ? "no flags"
              : allLinesChecked
                ? "all lines checked"
                : checkedCount === 0
                  ? `${queueLines.length} flagged`
                  : `${checkedCount}/${queueLines.length} checked`}
          </Badge>
          {take.isPublishedTake && <Badge variant="secondary">published</Badge>}
          {take.isSelectedTake && !take.isPublishedTake && (
            <Badge variant="secondary">selected</Badge>
          )}
          <span className="ml-auto text-xs font-normal text-muted-foreground">
            {take.lineCount} lines · {take.tokenCount} tokens · {take.voice} ·{" "}
            {new Date(take.createdAt).toLocaleString()}
            {opened
              ? ` · opened ${new Date(opened).toLocaleString()}`
              : " · not opened yet"}
            {take.timing?.publishedAt &&
            minutes(opened, take.timing.publishedAt)
              ? ` · ${minutes(opened, take.timing.publishedAt)} to publish`
              : ""}
          </span>
        </CardTitle>
        <PipelineSteps take={take} />
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        <div className="flex flex-wrap items-center gap-2">
          <Button
            type="button"
            size="sm"
            variant="outline"
            className="min-h-11 touch-manipulation md:min-h-8"
            onClick={playTake}
            disabled={!hasAudioBytes || (audioLoading && !playingTake)}
            title={
              !hasAudioBytes
                ? "This take has no audio"
                : audioLoading
                  ? "Loading take audio…"
                  : playingTake
                    ? "Stop"
                    : "Play take"
            }
          >
            {playingTake ? (
              <Pause className="size-3.5" />
            ) : (
              <Play className="size-3.5" />
            )}
            <span className="ml-1.5">
              {playingTake ? "Stop" : audioLoading ? "Loading…" : "Play take"}
            </span>
          </Button>
          <Button
            type="button"
            size="sm"
            variant="outline"
            className="min-h-11 touch-manipulation border-emerald-500/60 bg-emerald-500/15 text-emerald-700 dark:text-emerald-300 md:min-h-8"
            disabled={actionBusy}
            onClick={() => approveMutation.mutate()}
            title="Mark take reviewed, clear flags, and leave the queue. Per-line checks are optional."
          >
            {approveMutation.isPending ? "Approving…" : "Approve take"}
          </Button>
          <Button
            type="button"
            size="sm"
            variant="outline"
            className="min-h-11 touch-manipulation md:min-h-8"
            disabled={actionBusy || !canPublishAndComplete}
            onClick={() => publishAndCompleteMutation.mutate()}
            title={
              canPublishAndComplete
                ? "Select this take, publish audio to the database (Gate A), then mark reviewed. Does not make the lesson visible to learners."
                : "Needs a linked dialogue scene and take audio"
            }
          >
            <Upload className="size-3.5" />
            <span className="ml-1.5">
              {publishAndCompleteMutation.isPending
                ? "Publishing…"
                : "Publish & mark complete"}
            </span>
          </Button>
          <Link
            href={href}
            className="inline-flex min-h-11 items-center rounded-lg px-2.5 text-[0.8rem] font-medium text-muted-foreground underline-offset-4 hover:underline touch-manipulation md:min-h-8"
          >
            Open in editor
          </Link>
        </div>
        {playingTake && take.lines.length > 0 && (
          <TakeKaraoke
            lines={take.lines}
            currentTime={currentTime}
            playing={playingTake}
          />
        )}
        {queueLines.length > 0 && (
          <div className="flex flex-col gap-2">
            {take.flagCount > 0 && (
              <div className="flex flex-wrap gap-1 text-xs text-muted-foreground">
                {Object.entries(take.flagsByCode).map(([code, n]) => (
                  <span key={code}>
                    {FLAG_LABEL[code as TokenSyncFlag["code"]]} ×{n}
                  </span>
                ))}
              </div>
            )}
            {queueLines.map((line) => {
              const linePlaying =
                playingKey === `${take.variantId}:${line.lineIndex}`;
              const lineActiveToken = linePlaying
                ? activeTokenIndexInLine(line.tokens, currentTime)
                : null;
              return (
                <FlaggedLine
                  key={line.lineIndex}
                  line={line}
                  editorHref={editorHref(take, line.lineIndex)}
                  playing={linePlaying}
                  activeTokenIndex={lineActiveToken}
                  checked={checkedLines.has(line.lineIndex)}
                  playDisabled={
                    !hasAudioBytes || (audioLoading && !linePlaying)
                  }
                  onPlay={() => playLine(line)}
                  onToggleChecked={() => toggleLineChecked(line.lineIndex)}
                />
              );
            })}
          </div>
        )}
      </CardContent>
    </Card>
  );
}

function LessonGroupSection({
  group,
  expanded,
  onToggle,
  onInteract,
}: {
  group: LessonGroup;
  expanded: boolean;
  onToggle: () => void;
  onInteract: () => void;
}) {
  const waiting = group.takes.length;
  return (
    <section className="flex flex-col gap-2 rounded-lg border border-border/60 bg-card/30 p-2 sm:p-3">
      <button
        type="button"
        className="flex min-h-11 w-full items-center gap-2 rounded-md px-1 text-left touch-manipulation hover:bg-muted/40 md:min-h-9"
        onClick={onToggle}
        aria-expanded={expanded}
      >
        {expanded ? (
          <ChevronDown className="size-4 shrink-0 text-muted-foreground" />
        ) : (
          <ChevronRight className="size-4 shrink-0 text-muted-foreground" />
        )}
        <div className="min-w-0 flex-1">
          <div className="truncate text-sm font-medium">{group.title}</div>
          <div className="text-[11px] text-muted-foreground">
            {waiting} waiting
            {group.collectionId ? ` · ${group.collectionId}` : ""}
            {group.isActive === true
              ? " · visible to learners"
              : group.isActive === false
                ? " · hidden from learners"
                : ""}
          </div>
        </div>
        {!expanded && (
          <Badge variant="secondary" className="shrink-0 tabular-nums">
            {waiting}
          </Badge>
        )}
      </button>
      {expanded && (
        <div className="flex flex-col gap-3">
          {group.takes.map((take) => (
            <TakeCard
              key={take.variantId}
              take={take}
              onInteract={onInteract}
            />
          ))}
        </div>
      )}
    </section>
  );
}

export function ReviewQueue() {
  const { data, isLoading, isError, error } = useQuery({
    queryKey: ["tts-review-queue"],
    queryFn: () => ttsApi.reviewQueue(),
    refetchInterval: 30_000,
  });
  // Freeze first-seen take order for this page session so local line checks
  // never reshuffle cards under the reviewer (API also sorts by createdAt).
  const orderRef = useRef<string[]>([]);
  const takes = useMemo(() => {
    const incoming = data?.takes ?? [];
    if (incoming.length === 0) {
      orderRef.current = [];
      return [];
    }
    const byId = new Map(incoming.map((take) => [take.variantId, take]));
    const nextOrder: string[] = [];
    for (const id of orderRef.current) {
      if (byId.has(id)) nextOrder.push(id);
    }
    for (const take of incoming) {
      if (!nextOrder.includes(take.variantId)) nextOrder.push(take.variantId);
    }
    orderRef.current = nextOrder;
    return nextOrder.map((id) => byId.get(id)!);
  }, [data?.takes]);

  const lessonGroups = useMemo(() => groupTakesByLesson(takes), [takes]);

  // Default expand: lessons with any opened take, else the first lesson only.
  // Once expanded via interaction, stay open for the session.
  const [expandedKeys, setExpandedKeys] = useState<Set<string> | null>(null);
  const defaultExpanded = useMemo(() => {
    const keys = new Set<string>();
    for (const group of lessonGroups) {
      if (group.takes.some((take) => take.timing?.openedAt)) {
        keys.add(group.key);
      }
    }
    if (keys.size === 0 && lessonGroups[0]) {
      keys.add(lessonGroups[0].key);
    }
    return keys;
  }, [lessonGroups]);
  const effectiveExpanded = expandedKeys ?? defaultExpanded;

  function toggleGroup(key: string) {
    setExpandedKeys((prev) => {
      const base = new Set(prev ?? defaultExpanded);
      if (base.has(key)) base.delete(key);
      else base.add(key);
      return base;
    });
  }

  function keepGroupExpanded(key: string) {
    setExpandedKeys((prev) => {
      const base = new Set(prev ?? defaultExpanded);
      base.add(key);
      return base;
    });
  }

  if (isLoading) {
    return (
      <div className="flex flex-col gap-4">
        <Skeleton className="h-8 w-64" />
        <Skeleton className="h-32 w-full" />
      </div>
    );
  }
  if (isError || !data) {
    return (
      <p className="text-sm text-destructive">
        {error instanceof Error
          ? error.message
          : "Could not load the review queue."}
      </p>
    );
  }

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold">Review queue</h1>
        <p className="text-sm text-muted-foreground">
          Auto-stamped takes that still have flags. Pipeline shows Staged → In
          database (Gate A) → Client-visible (Gate B / lesson live).{" "}
          <span className="font-medium text-foreground">
            Publish &amp; mark complete
          </span>{" "}
          lands audio in the database and clears flags — it never flips lesson
          visibility. Per-line checks are optional.
        </p>
      </div>
      <TimingSummary timing={data.timing} />
      {takes.length === 0 && (
        <p className="text-sm text-muted-foreground">
          Nothing waiting for review.
        </p>
      )}
      <div className="flex flex-col gap-3">
        {lessonGroups.map((group) => (
          <LessonGroupSection
            key={group.key}
            group={group}
            expanded={effectiveExpanded.has(group.key)}
            onToggle={() => toggleGroup(group.key)}
            onInteract={() => keepGroupExpanded(group.key)}
          />
        ))}
      </div>
    </div>
  );
}
