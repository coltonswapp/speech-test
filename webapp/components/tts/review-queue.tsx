"use client";

import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { Check, ExternalLink, Pause, Play } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
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
                <td className="py-1.5 pr-4 tabular-nums">{fmt(row.linesUntouchedPct, "%")}</td>
                <td className="py-1.5 pr-4 tabular-nums">{fmt(row.correctionsOver200msPct, "%")}</td>
              </tr>
            ))}
          </tbody>
        </table>
        <p className="mt-2 text-xs text-muted-foreground">
          Clock starts the first time a take is opened in Token timing and stops at publish.
          v1 bar: ≥ 80% of lines untouched, ≤ 4 min per scene.
          {timing.since ? ` Measuring since ${new Date(timing.since).toLocaleDateString()}.` : " No published takes measured yet."}
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
        active && !untimed && "border-primary bg-primary/15"
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
  approvePending,
  onPlay,
  onApprove,
}: {
  line: FlaggedLine;
  editorHref: string;
  playing: boolean;
  activeTokenIndex: number | null;
  approvePending: boolean;
  onPlay: () => void;
  onApprove: () => void;
}) {
  const canPlay = line.playFromSeconds != null;
  return (
    <div
      className={cn(
        "flex flex-wrap items-start gap-2 rounded-md border px-2 py-1.5 transition-colors",
        playing
          ? "border-primary/50 bg-primary/5"
          : "border-transparent"
      )}
    >
      <Button
        type="button"
        size="sm"
        variant="outline"
        className="min-h-10 shrink-0 touch-manipulation md:min-h-8"
        disabled={!canPlay}
        onClick={onPlay}
        title={
          canPlay
            ? `Play line ${line.lineIndex + 1} from the stamps`
            : "No timing on this line yet"
        }
      >
        {playing ? <Pause className="size-3.5" /> : <Play className="size-3.5" />}
        <span className="ml-1">L{line.lineIndex + 1}</span>
      </Button>
      <div className="min-w-0 flex-1 flex flex-wrap items-center gap-x-1 gap-y-1 text-sm leading-relaxed">
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
      </div>
      <div className="flex shrink-0 items-center gap-1">
        <Button
          type="button"
          size="sm"
          variant="outline"
          className="min-h-10 touch-manipulation border-emerald-500/50 md:min-h-8"
          disabled={approvePending}
          onClick={onApprove}
          title={`Approve line ${line.lineIndex + 1}: clear its flags`}
          aria-label={`Approve line ${line.lineIndex + 1}`}
        >
          <Check className="size-3.5" />
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
              activeTokenIndex != null && "bg-primary/5"
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

function TakeCard({ take }: { take: Take }) {
  const queryClient = useQueryClient();
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const stopTimerRef = useRef<number | null>(null);
  const rafRef = useRef<number | null>(null);
  const [playingKey, setPlayingKey] = useState<string | null>(null);
  const [currentTime, setCurrentTime] = useState(0);
  const [approvingLine, setApprovingLine] = useState<number | null>(null);

  const audioUrl = ttsApi.variantAudioUrl(
    take.projectId,
    take.variantId,
    take.audioByteCount
  );

  useEffect(() => {
    const audio = new Audio(audioUrl);
    audio.preload = "auto";
    const onEnded = () => {
      setPlayingKey(null);
      if (rafRef.current != null) {
        cancelAnimationFrame(rafRef.current);
        rafRef.current = null;
      }
    };
    audio.addEventListener("ended", onEnded);
    audioRef.current = audio;
    return () => {
      if (stopTimerRef.current != null) window.clearTimeout(stopTimerRef.current);
      if (rafRef.current != null) cancelAnimationFrame(rafRef.current);
      audio.pause();
      audio.removeEventListener("ended", onEnded);
      audioRef.current = null;
    };
  }, [audioUrl]);

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
    },
    onError: (error) => toast.error(error.message),
  });

  const approveLineMutation = useMutation({
    mutationFn: (lineIndex: number) =>
      ttsApi.approveLine(take.projectId, take.variantId, lineIndex),
    onMutate: (lineIndex) => setApprovingLine(lineIndex),
    onSettled: () => setApprovingLine(null),
    onSuccess: (result, lineIndex) => {
      queryClient.invalidateQueries({ queryKey: ["tts-review-queue"] });
      if (result.takeReviewed || result.alreadyReviewed) {
        toast.success(`Line ${lineIndex + 1} approved — take marked reviewed.`);
      } else if (result.cleared) {
        toast.success(`Line ${lineIndex + 1} approved.`);
      } else {
        toast.message(`Line ${lineIndex + 1} had no flags left.`);
      }
    },
    onError: (error) => toast.error(error.message),
  });

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

  async function playSegment(key: string, fromSeconds: number, untilSeconds: number | null) {
    if (playingKey === key) {
      stopPlayback();
      return;
    }
    clearStopTimer();
    const audio = audioRef.current;
    if (!audio) {
      toast.error("Audio is not ready yet.");
      return;
    }
    try {
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
      toast.error(error instanceof Error ? error.message : "Could not play audio.");
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
      line.playUntilSeconds
    );
  }

  async function playTake() {
    await playSegment(`${take.variantId}:all`, 0, null);
  }

  const playingTake = playingKey === `${take.variantId}:all`;
  const href = editorHref(take);
  const opened = take.timing?.openedAt;

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex flex-wrap items-center gap-2 text-base">
          <Link href={href} className="underline-offset-4 hover:underline">
            {take.title}
          </Link>
          {take.collectionId && (
            <span className="text-xs font-normal text-muted-foreground">{take.collectionId}</span>
          )}
          <Badge
            variant="outline"
            className={cn(
              take.flagCount > 0
                ? "border-amber-500/50 text-amber-600 dark:text-amber-400"
                : "border-emerald-500/50 text-emerald-600 dark:text-emerald-400"
            )}
          >
            {take.flagCount === 0 ? "no flags" : `${take.flagCount} flagged`}
          </Badge>
          {take.isPublishedTake && <Badge variant="secondary">published</Badge>}
          {take.isSelectedTake && !take.isPublishedTake && (
            <Badge variant="secondary">selected</Badge>
          )}
          <span className="ml-auto text-xs font-normal text-muted-foreground">
            {take.lineCount} lines · {take.tokenCount} tokens · {take.voice} ·{" "}
            {new Date(take.createdAt).toLocaleString()}
            {opened ? ` · opened ${new Date(opened).toLocaleString()}` : " · not opened yet"}
            {take.timing?.publishedAt && minutes(opened, take.timing.publishedAt)
              ? ` · ${minutes(opened, take.timing.publishedAt)} to publish`
              : ""}
          </span>
        </CardTitle>
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        <div className="flex flex-wrap items-center gap-2">
          <Button
            type="button"
            size="sm"
            variant="outline"
            className="min-h-11 touch-manipulation md:min-h-8"
            onClick={playTake}
          >
            {playingTake ? (
              <Pause className="size-3.5" />
            ) : (
              <Play className="size-3.5" />
            )}
            <span className="ml-1.5">{playingTake ? "Stop" : "Play take"}</span>
          </Button>
          <Button
            type="button"
            size="sm"
            variant="outline"
            className="min-h-11 touch-manipulation border-emerald-500/50 md:min-h-8"
            disabled={approveMutation.isPending}
            onClick={() => approveMutation.mutate()}
            title="Accept auto stamps: source → reviewed, clear amber flags"
          >
            {approveMutation.isPending ? "Approving…" : "Approve"}
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
        {take.flaggedLines.length > 0 && (
          <div className="flex flex-col gap-2">
            <div className="flex flex-wrap gap-1 text-xs text-muted-foreground">
              {Object.entries(take.flagsByCode).map(([code, n]) => (
                <span key={code}>
                  {FLAG_LABEL[code as TokenSyncFlag["code"]]} ×{n}
                </span>
              ))}
            </div>
            {take.flaggedLines.map((line) => {
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
                  approvePending={
                    approveLineMutation.isPending && approvingLine === line.lineIndex
                  }
                  onPlay={() => playLine(line)}
                  onApprove={() => approveLineMutation.mutate(line.lineIndex)}
                />
              );
            })}
          </div>
        )}
      </CardContent>
    </Card>
  );
}

export function ReviewQueue() {
  const { data, isLoading, isError, error } = useQuery({
    queryKey: ["tts-review-queue"],
    queryFn: () => ttsApi.reviewQueue(),
    refetchInterval: 30_000,
  });

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
        {error instanceof Error ? error.message : "Could not load the review queue."}
      </p>
    );
  }

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold">Review queue</h1>
        <p className="text-sm text-muted-foreground">
          Takes stamped by the aligner that nobody has marked reviewed, most flags first.
          Play a flagged line, checkmark to clear that line, or open Token timing on the line to fix stamps.
        </p>
      </div>
      <TimingSummary timing={data.timing} />
      {data.takes.length === 0 && (
        <p className="text-sm text-muted-foreground">Nothing waiting for review.</p>
      )}
      <div className="flex flex-col gap-3">
        {data.takes.map((take) => (
          <TakeCard key={take.variantId} take={take} />
        ))}
      </div>
    </div>
  );
}
