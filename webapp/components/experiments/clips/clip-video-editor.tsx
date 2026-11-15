"use client";

import { memo, useCallback, useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { useMutation, useQueries, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import {
  AudioLinesIcon,
  ChevronLeftIcon,
  ExternalLinkIcon,
  LanguagesIcon,
  Loader2Icon,
  SaveIcon,
  ScissorsIcon,
} from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { Skeleton } from "@/components/ui/skeleton";
import { Switch } from "@/components/ui/switch";
import { cn } from "@/lib/utils";
import { clipsApi } from "@/lib/experiments/clips/client";
import {
  clipHasUntimedLines,
  clipIsAligned,
  clipIsTokenized,
  type ClipDraft,
  type ClipDraftResponse,
  type ClipSummary,
} from "@/lib/experiments/clips/types";
import type { EditableToken } from "@/lib/experiments/clips/token-edits";
import { formatTimecode } from "@/components/experiments/clips/clip-format";
import { ClipMedia, type ClipMediaController } from "@/components/experiments/clips/clip-media";
import { ClipTokenLines, tokenKey } from "@/components/experiments/clips/clip-token-lines";
import { EditorSection } from "@/components/experiments/clips/editor-section";
import { FeedBadge, ProcessAllButton } from "@/components/experiments/clips/clip-list";
import { usePersistentState } from "@/components/experiments/clips/use-persistent-state";
import {
  formatCost,
  formatCount,
  STEP_LABELS,
  sumUsage,
  usageByStep,
  type UsageTotals,
} from "@/lib/experiments/clips/usage-cost";
import type { ClipUsageStep } from "@/lib/experiments/clips/types";

// Every clip cut from one YouTube video, reviewed on one page: the video plays
// on the right and the highlighted token moves from clip to clip as it plays.
// Each clip is still its own draft (and its own clip in the app); edits here
// go to that clip, exactly as in its editor.

type Active = { clipId: string; key: string } | null;

/** What drives highlighting: the YouTube video, or one clip's own audio. */
type Driver = { kind: "video" } | { kind: "audio"; clipId: string; el: HTMLAudioElement };

type TimelineItem = { key: string; start: number; end: number };

type ClipTimeline = {
  clipId: string;
  /** Video time of the clip's start/end. */
  startSec: number;
  endSec: number;
  /** Clip-relative, onset shift applied, time-ordered. */
  items: TimelineItem[];
};

function buildTimeline(draft: ClipDraft): ClipTimeline {
  const items: TimelineItem[] = [];
  draft.sentences.forEach((sentence, i) =>
    (sentence.tokens ?? []).forEach((token, j) => {
      if (token.startSec === undefined || token.endSec === undefined) return;
      items.push({
        key: tokenKey(i, j),
        start: token.startSec + draft.shiftSec,
        end: token.endSec + draft.shiftSec,
      });
    })
  );
  return { clipId: draft.id, startSec: draft.startSec, endSec: draft.endSec, items };
}

/** Last token that has started at `t`, held until the next one starts. */
function tokenAt(items: TimelineItem[], t: number): string | null {
  let lo = 0;
  let hi = items.length - 1;
  let found = -1;
  while (lo <= hi) {
    const mid = (lo + hi) >> 1;
    if (items[mid].start <= t) {
      found = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return found >= 0 && t < items[found].end + 0.3 ? items[found].key : null;
}

export function ClipVideoEditor({ videoId }: { videoId: string }) {
  const listQuery = useQuery({ queryKey: ["experiment-clips"], queryFn: () => clipsApi.list() });
  const summaries = useMemo(
    () =>
      (listQuery.data?.clips ?? [])
        .filter((clip) => clip.videoId === videoId)
        .sort((a, b) => a.startSec - b.startSec),
    [listQuery.data, videoId]
  );
  // Same query keys as the clip editor, so both pages share the cache.
  const draftQueries = useQueries({
    queries: summaries.map((clip) => ({
      queryKey: ["experiment-clip", clip.id],
      queryFn: () => clipsApi.get(clip.id),
    })),
  });
  const drafts = draftQueries.map((q) => q.data?.draft);
  // useQueries returns a new array every render; key the timelines on draft
  // versions so the playback loop only restarts when a draft changes.
  const draftsVersion = drafts.map((d) => (d ? `${d.id}@${d.updatedAt}` : "")).join("|");

  const timelines = useMemo(
    () => drafts.filter((d): d is ClipDraft => Boolean(d)).map(buildTimeline),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [draftsVersion]
  );

  // Processing cost across every clip from this video.
  const videoUsage = useMemo(() => {
    const loaded = drafts.filter((d): d is ClipDraft => Boolean(d));
    const perClip = loaded.map((d) => ({ clipId: d.id, totals: sumUsage(d.usage ?? []) }));
    const runs = loaded.flatMap((d) => d.usage ?? []);
    return {
      totals: sumUsage(runs),
      byStep: usageByStep(runs),
      perClip,
      loadedCount: loaded.length,
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [draftsVersion]);

  const mediaRef = useRef<ClipMediaController>(null);
  const driverRef = useRef<Driver>({ kind: "video" });
  const audioStartedAtRef = useRef(0);
  /** Pause point for line playback, in the driver's own time. */
  const stopAtRef = useRef<number | null>(null);
  const [active, setActive] = useState<Active>(null);
  const [follow, setFollow] = usePersistentState("experiments.clips.video.follow", true);
  const lastScrolledLineRef = useRef<string | null>(null);

  // Polls every frame: YouTube has no timeupdate events.
  useEffect(() => {
    let frame = 0;
    const tick = () => {
      frame = requestAnimationFrame(tick);
      const video = mediaRef.current;
      let driver = driverRef.current;
      // The video was started while a clip's audio drove: the video takes over.
      // (Grace period: pausing YouTube after the audio starts is async.)
      if (
        driver.kind === "audio" &&
        video &&
        !video.paused() &&
        performance.now() - audioStartedAtRef.current > 600
      ) {
        driver.el.pause();
        driver = { kind: "video" };
        driverRef.current = driver;
        stopAtRef.current = null;
      }

      let clip: ClipTimeline | undefined;
      let t: number;
      if (driver.kind === "audio") {
        clip = timelines.find((c) => c.clipId === driver.clipId);
        t = driver.el.currentTime;
        if (stopAtRef.current !== null && t >= stopAtRef.current) {
          stopAtRef.current = null;
          driver.el.pause();
        }
      } else {
        if (!video) return;
        const videoTime = video.currentTime();
        if (stopAtRef.current !== null && videoTime >= stopAtRef.current) {
          stopAtRef.current = null;
          video.pause();
        }
        // Clips are back to back: the last one that has started.
        for (const c of timelines) if (c.startSec <= videoTime) clip = c;
        if (clip && videoTime > clip.endSec + 0.5) clip = undefined;
        t = clip ? videoTime - clip.startSec : 0;
      }
      const key = clip ? tokenAt(clip.items, t) : null;
      const next: Active = clip && key ? { clipId: clip.clipId, key } : null;
      setActive((prev) =>
        prev?.clipId === next?.clipId && prev?.key === next?.key ? prev : next
      );
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [timelines]);

  // Follow: keep the line being played in view (once per line, not per token).
  useEffect(() => {
    if (!follow || !active) return;
    const line = `${active.clipId}:${active.key.split(":")[0]}`;
    if (line === lastScrolledLineRef.current) return;
    lastScrolledLineRef.current = line;
    const el = document.querySelector(
      `[data-clip-id="${active.clipId}"] [data-token-key="${active.key}"]`
    );
    el?.scrollIntoView({ block: "center", behavior: "smooth" });
  }, [active, follow]);

  // Space plays/pauses whatever drives, except while typing.
  useEffect(() => {
    const isTyping = (target: EventTarget | null) =>
      target instanceof HTMLElement &&
      (target.isContentEditable ||
        target.tagName === "TEXTAREA" ||
        target.tagName === "SELECT" ||
        (target.tagName === "INPUT" &&
          !["button", "checkbox", "radio", "range", "submit"].includes(
            (target as HTMLInputElement).type
          )));
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.code !== "Space" || event.repeat || isTyping(event.target)) return;
      event.preventDefault();
      event.stopPropagation();
      const driver = driverRef.current;
      if (driver.kind === "audio") {
        if (driver.el.paused) void driver.el.play();
        else driver.el.pause();
        return;
      }
      const video = mediaRef.current;
      if (!video) return;
      if (video.paused()) video.play();
      else video.pause();
    };
    const onKeyUp = (event: KeyboardEvent) => {
      if (event.code === "Space" && !isTyping(event.target)) event.preventDefault();
    };
    window.addEventListener("keydown", onKeyDown, true);
    window.addEventListener("keyup", onKeyUp, true);
    return () => {
      window.removeEventListener("keydown", onKeyDown, true);
      window.removeEventListener("keyup", onKeyUp, true);
    };
  }, []);

  /**
   * Token / line clicks. Plays that clip's audio if it's what you're
   * listening to; otherwise seeks the video.
   */
  const playClipAt = useCallback(
    (clipId: string, clipStartSec: number, clipSeconds: number, stopAt?: number) => {
      const driver = driverRef.current;
      lastScrolledLineRef.current = null;
      if (driver.kind === "audio" && driver.clipId === clipId) {
        stopAtRef.current = stopAt ?? null;
        driver.el.currentTime = Math.max(0, clipSeconds);
        void driver.el.play();
        return;
      }
      if (driver.kind === "audio") driver.el.pause();
      driverRef.current = { kind: "video" };
      stopAtRef.current = stopAt !== undefined ? clipStartSec + stopAt : null;
      mediaRef.current?.play(clipStartSec + Math.max(0, clipSeconds));
    },
    []
  );

  /** A clip's own audio player started: it drives until something else plays. */
  const onClipAudioPlay = useCallback((clipId: string, el: HTMLAudioElement) => {
    const previous = driverRef.current;
    if (previous.kind === "audio" && previous.el !== el) previous.el.pause();
    driverRef.current = { kind: "audio", clipId, el };
    audioStartedAtRef.current = performance.now();
    stopAtRef.current = null;
    lastScrolledLineRef.current = null;
    mediaRef.current?.pause();
  }, []);

  if (listQuery.isPending) return <Skeleton className="h-64 w-full" />;
  if (listQuery.isError) {
    return <p className="text-sm text-destructive">{listQuery.error.message}</p>;
  }
  if (summaries.length === 0) {
    return <p className="text-sm text-muted-foreground">No clips from this video.</p>;
  }

  const title = summaries.find((c) => c.videoTitle)?.videoTitle ?? videoId;
  const channel = summaries.find((c) => c.channelName)?.channelName;
  const first = summaries[0];
  const last = summaries[summaries.length - 1];

  return (
    <div className="flex flex-col gap-6">
      <div>
        <Link
          href="/experiments/clips"
          className="mb-1 inline-flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground"
        >
          <ChevronLeftIcon className="size-3" /> Clips
        </Link>
        <h1 className="text-xl font-semibold tracking-tight">{title}</h1>
        <p className="flex flex-wrap items-center gap-x-3 gap-y-1 text-sm text-muted-foreground">
          {channel ? <span>{channel}</span> : null}
          <a
            href={`https://www.youtube.com/watch?v=${videoId}`}
            target="_blank"
            rel="noreferrer"
            className="inline-flex items-center gap-1 hover:text-foreground"
          >
            {videoId} <ExternalLinkIcon className="size-3" />
          </a>
          <span>
            {summaries.length} clips · {formatTimecode(first.startSec)}–
            {formatTimecode(last.endSec)}
          </span>
          <span className="inline-flex items-center gap-1.5">
            <Switch id="video-follow" checked={follow} onCheckedChange={setFollow} />
            <Label htmlFor="video-follow" className="text-sm font-normal text-muted-foreground">
              Follow playback
            </Label>
          </span>
          {videoUsage.totals.runs > 0 ? (
            <span title="Estimated Gemini cost of every run on these clips (see Usage below)">
              Est. cost {formatCost(videoUsage.totals)}
            </span>
          ) : null}
          <ProcessAllButton clips={summaries} />
        </p>
      </div>

      <div className="flex flex-col gap-6 lg:grid lg:grid-cols-[minmax(0,1fr)_24rem] lg:items-start">
        <aside className="lg:sticky lg:top-20 lg:col-start-2 lg:row-start-1">
          <div className="flex flex-col gap-2 rounded-xl border border-border/60 p-3">
            <ClipMedia
              videoId={videoId}
              startSec={0}
              endSec={last.endSec}
              portrait={first.orientation === "portrait"}
              audioUrl=""
              controllerRef={mediaRef}
              videoOnly
            />
            <p className="text-xs text-muted-foreground">
              Tokens follow the video, or a clip’s own audio while you play it. Click a token to
              jump there; Space plays and pauses.
            </p>
          </div>
        </aside>
        <div className="flex min-w-0 flex-col gap-4 lg:col-start-1 lg:row-start-1">
          <VideoUsageSection usage={videoUsage} clipCount={summaries.length} />
          {summaries.map((summary, index) => (
            <ClipPanel
              key={summary.id}
              summary={summary}
              data={draftQueries[index]?.data}
              loadError={draftQueries[index]?.error?.message ?? null}
              active={active?.clipId === summary.id ? active.key : null}
              onPlay={playClipAt}
              onAudioPlay={onClipAudioPlay}
            />
          ))}
        </div>
      </div>
    </div>
  );
}

type VideoUsage = {
  totals: UsageTotals;
  byStep: Array<{ step: ClipUsageStep; totals: UsageTotals }>;
  perClip: Array<{ clipId: string; totals: UsageTotals }>;
  loadedCount: number;
};

/** Processing cost for the whole video: by step, then by clip. */
function VideoUsageSection({ usage, clipCount }: { usage: VideoUsage; clipCount: number }) {
  const { totals, byStep, perClip, loadedCount } = usage;
  const cell = "py-1.5 pr-3 text-right";
  return (
    <EditorSection
      id="video-usage"
      title="Usage"
      summary={totals.runs > 0 ? `${totals.runs} runs · ${formatCost(totals)}` : "no runs yet"}
      defaultOpen={false}
    >
      <p className="text-xs text-muted-foreground">
        Every Transcribe, Tokenize, Align, Translate, Level and Feed run on these {clipCount} clips,
        added up. Costs use published text rates (thinking billed as output); ≥ means some runs
        sent audio, which Gemini bills higher. Align runs on our aligner (no Gemini cost).
        Highlights runs aren’t logged, and each clip keeps its last 50 runs.
        {loadedCount < clipCount ? ` Still loading ${clipCount - loadedCount} clips.` : ""}
        {totals.unpriced ? " Some runs used a model without a known rate and are left out of the cost." : ""}
      </p>
      {totals.runs === 0 ? (
        <p className="text-sm text-muted-foreground">No runs logged yet.</p>
      ) : (
        <>
          <div className="overflow-x-auto">
            <table className="w-full text-xs tabular-nums">
              <thead className="text-left text-muted-foreground">
                <tr className="border-b border-border/60">
                  <th className="py-1.5 pr-3 font-medium">Step</th>
                  <th className={cn(cell, "font-medium")}>Runs</th>
                  <th className={cn(cell, "font-medium")}>Calls</th>
                  <th className={cn(cell, "font-medium")}>Input</th>
                  <th className={cn(cell, "font-medium")}>Output</th>
                  <th className={cn(cell, "font-medium")}>Thinking</th>
                  <th className={cn(cell, "font-medium")}>Time</th>
                  <th className="py-1.5 text-right font-medium">Est. cost</th>
                </tr>
              </thead>
              <tbody>
                {byStep.map(({ step, totals: t }) => {
                  const gemini = step !== "align";
                  return (
                    <tr key={step} className="border-b border-border/40">
                      <td className="py-1.5 pr-3 font-medium">{STEP_LABELS[step]}</td>
                      <td className={cell}>{formatCount(t.runs)}</td>
                      <td className={cell}>{gemini ? formatCount(t.calls) : "—"}</td>
                      <td className={cell}>
                        {gemini ? formatCount(t.inputTokens) : "—"}
                        {t.audioInputTokens > 0 ? (
                          <span className="block text-muted-foreground">
                            {formatCount(t.audioInputTokens)} audio
                          </span>
                        ) : null}
                      </td>
                      <td className={cell}>{gemini ? formatCount(t.outputTokens) : "—"}</td>
                      <td className={cell}>
                        {!gemini ? "—" : step === "tokenize" ? "in output" : formatCount(t.thinkingTokens)}
                      </td>
                      <td className={cell}>{(t.durationMs / 1000).toFixed(0)} s</td>
                      <td className="py-1.5 text-right">{gemini ? formatCost(t) : "—"}</td>
                    </tr>
                  );
                })}
              </tbody>
              <tfoot>
                <tr className="border-t border-border/60 font-medium">
                  <td className="py-1.5 pr-3">All steps</td>
                  <td className={cell}>{formatCount(totals.runs)}</td>
                  <td className={cell}>{formatCount(totals.calls)}</td>
                  <td className={cell}>{formatCount(totals.inputTokens)}</td>
                  <td className={cell}>{formatCount(totals.outputTokens)}</td>
                  <td className={cell}>{formatCount(totals.thinkingTokens)}</td>
                  <td className={cell}>{(totals.durationMs / 1000).toFixed(0)} s</td>
                  <td className="py-1.5 text-right">{formatCost(totals)}</td>
                </tr>
              </tfoot>
            </table>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-xs tabular-nums">
              <thead className="text-left text-muted-foreground">
                <tr className="border-b border-border/60">
                  <th className="py-1.5 pr-3 font-medium">Clip</th>
                  <th className={cn(cell, "font-medium")}>Runs</th>
                  <th className={cn(cell, "font-medium")}>Time</th>
                  <th className="py-1.5 text-right font-medium">Est. cost</th>
                </tr>
              </thead>
              <tbody>
                {perClip.map(({ clipId, totals: t }) => (
                  <tr key={clipId} className="border-b border-border/40 last:border-0">
                    <td className="py-1.5 pr-3 font-mono">{clipId}</td>
                    <td className={cell}>{formatCount(t.runs)}</td>
                    <td className={cell}>{(t.durationMs / 1000).toFixed(0)} s</td>
                    <td className="py-1.5 text-right">{t.runs > 0 ? formatCost(t) : "—"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </>
      )}
    </EditorSection>
  );
}

/** One clip from the video: header with status + steps, its audio, its tokens. */
const ClipPanel = memo(function ClipPanel({
  summary,
  data,
  loadError,
  active,
  onPlay,
  onAudioPlay,
}: {
  summary: ClipSummary;
  data: ClipDraftResponse | undefined;
  loadError: string | null;
  active: string | null;
  onPlay: (clipId: string, clipStartSec: number, clipSeconds: number, stopAt?: number) => void;
  onAudioPlay: (clipId: string, el: HTMLAudioElement) => void;
}) {
  const queryClient = useQueryClient();
  const clipId = summary.id;
  const draft = data?.draft;
  const [editing, setEditing] = useState(false);
  const [saving, setSaving] = useState(false);
  /** Unsaved English, or null when not editing it. */
  const [english, setEnglish] = useState<string[] | null>(null);

  const setDraft = (next: ClipDraft) => {
    queryClient.setQueryData<ClipDraftResponse>(["experiment-clip", clipId], (prev) =>
      prev ? { ...prev, draft: next } : prev
    );
    void queryClient.invalidateQueries({ queryKey: ["experiment-clips"] });
  };
  const fail = (error: unknown) =>
    toast.error(`${clipId}: ${error instanceof Error ? error.message : String(error)}`);

  // Transcribe → tokenize → align, skipping what's done; keeps timed lines.
  const [stepLabel, setStepLabel] = useState<string | null>(null);
  const runSteps = useMutation({
    mutationFn: async () => {
      if (!draft) throw new Error("Clip not loaded.");
      let current = draft;
      try {
        if (current.sentences.length === 0) {
          setStepLabel("Transcribing…");
          current = (await clipsApi.step(clipId, "transcribe")).draft;
          setDraft(current);
          if (current.sentences.length === 0) return current;
        }
        if (!clipIsTokenized(current)) {
          setStepLabel("Tokenizing…");
          current = (await clipsApi.step(clipId, "tokenize")).draft;
          setDraft(current);
        }
        if (!clipIsAligned(current)) {
          setStepLabel("Aligning…");
          current = clipHasUntimedLines(current)
            ? (await clipsApi.alignUntimed(clipId)).draft
            : (await clipsApi.step(clipId, "align")).draft;
          setDraft(current);
        }
      } finally {
        setStepLabel(null);
      }
      return current;
    },
    onSuccess: (next) => {
      if (next.sentences.length === 0) toast.message(`${clipId}: no speech found.`);
      const basic = next.sentences.flatMap((s, i) => (s.basicSplit ? [i + 1] : []));
      if (basic.length > 0) {
        toast.warning(`${clipId}: line ${basic.join(", ")} got a basic word split; check its tokens.`);
      }
    },
    onError: fail,
  });

  const translate = useMutation({
    mutationFn: () => clipsApi.step(clipId, "translate"),
    onSuccess: ({ draft: next }) => {
      setDraft(next);
      setEnglish(null);
    },
    onError: fail,
  });

  const saveEnglish = useMutation({
    mutationFn: (lines: string[]) => clipsApi.patch(clipId, { english: lines }),
    onSuccess: ({ draft: next }) => {
      setDraft(next);
      setEnglish(null);
      toast.success(`${clipId}: English saved.`);
    },
    onError: fail,
  });

  const editTokens = async (sentence: number, tokens: EditableToken[]) => {
    setSaving(true);
    try {
      const { draft: next } = await clipsApi.patch(clipId, { tokens: { sentence, tokens } });
      setDraft(next);
      const line = next.sentences[sentence];
      const timed = (line?.tokens ?? []).every((t) => t.startSec !== undefined);
      if (!timed) toast.message(`${clipId} line ${sentence + 1}: align edited lines to time the new tokens.`);
    } catch (error) {
      fail(error);
    } finally {
      setSaving(false);
    }
  };

  const clearFlags = async (sentence: number, cleared: boolean) => {
    try {
      const { draft: next } = await clipsApi.patch(clipId, { clearFlags: { sentence, cleared } });
      setDraft(next);
    } catch (error) {
      fail(error);
    }
  };

  const busy = runSteps.isPending || translate.isPending || saveEnglish.isPending || saving;
  const aligned = draft ? clipIsAligned(draft) : summary.aligned;
  const partly = draft ? clipHasUntimedLines(draft) : false;
  const tokenized = draft ? clipIsTokenized(draft) : summary.tokenized;
  const empty = draft ? draft.sentences.length === 0 : summary.sentenceCount === 0;
  const basicCount = draft?.sentences.filter((s) => s.basicSplit).length ?? 0;
  const clipUsage = draft ? sumUsage(draft.usage ?? []) : null;
  const englishChanged =
    english !== null && draft !== undefined && english.some((line, i) => line !== (draft.sentences[i]?.en ?? ""));

  const nextStepLabel = empty
    ? "Transcribe"
    : !tokenized
      ? "Tokenize and align"
      : partly
        ? "Align edited lines"
        : !aligned
          ? "Align"
          : null;

  return (
    <div data-clip-id={clipId} className={cn(summary.deprecated && "opacity-60")}>
      <EditorSection
        id={`video.${clipId}`}
        title={
          <span className="flex items-center gap-2">
            <span className="font-mono">{clipId}</span>
            <span className="text-xs font-normal text-muted-foreground">
              {formatTimecode(summary.startSec)}–{formatTimecode(summary.endSec)}
            </span>
          </span>
        }
        summary={[
          `${summary.sentenceCount} sentences`,
          aligned ? "aligned" : partly ? "needs aligning" : tokenized ? "tokenized" : empty ? "not transcribed" : "",
        ]
          .filter(Boolean)
          .join(" · ")}
        actions={
          <>
            {summary.deprecated ? <Badge variant="destructive">Deprecated</Badge> : null}
            {basicCount > 0 ? (
              <Badge variant="outline" className="border-amber-500/60 text-amber-700 dark:text-amber-400">
                {basicCount} basic split
              </Badge>
            ) : null}
            <FeedBadge clip={summary} />
            <Badge variant={summary.jlptLevel ? "secondary" : "outline"}>
              {summary.jlptLevel ? `N${summary.jlptLevel}` : "No level"}
            </Badge>
            {nextStepLabel ? (
              <Button size="sm" disabled={busy || !draft} onClick={() => runSteps.mutate()}>
                {runSteps.isPending ? <Loader2Icon className="animate-spin" /> : <AudioLinesIcon />}
                {stepLabel ?? nextStepLabel}
              </Button>
            ) : null}
            {tokenized ? (
              <Button
                size="sm"
                variant={editing ? "default" : "outline"}
                disabled={!draft || (busy && !editing)}
                onClick={() => setEditing((on) => !on)}
              >
                {saving ? <Loader2Icon className="animate-spin" /> : <ScissorsIcon />}
                {editing ? "Done" : "Edit tokens"}
              </Button>
            ) : null}
            {draft && !empty ? (
              english === null ? (
                <>
                  <Button
                    size="sm"
                    variant="outline"
                    disabled={busy}
                    onClick={() => setEnglish(draft.sentences.map((s) => s.en ?? ""))}
                  >
                    <LanguagesIcon />
                    Edit English
                  </Button>
                  {draft.sentences.some((s) => !s.en?.trim()) ? (
                    <Button
                      size="sm"
                      variant="outline"
                      disabled={busy}
                      onClick={() => translate.mutate()}
                    >
                      {translate.isPending ? <Loader2Icon className="animate-spin" /> : <LanguagesIcon />}
                      Translate
                    </Button>
                  ) : null}
                </>
              ) : (
                <>
                  <Button size="sm" variant="ghost" disabled={saveEnglish.isPending} onClick={() => setEnglish(null)}>
                    Cancel
                  </Button>
                  <Button
                    size="sm"
                    disabled={!englishChanged || saveEnglish.isPending}
                    onClick={() => saveEnglish.mutate(english)}
                  >
                    {saveEnglish.isPending ? <Loader2Icon className="animate-spin" /> : <SaveIcon />}
                    Save English
                  </Button>
                </>
              )
            ) : null}
            {clipUsage && clipUsage.runs > 0 ? (
              <span
                className="text-xs tabular-nums text-muted-foreground"
                title={`${clipUsage.runs} runs on this clip (estimated Gemini cost)`}
              >
                {formatCost(clipUsage)}
              </span>
            ) : null}
            <Link
              href={`/experiments/clips/${clipId}`}
              className="text-xs text-muted-foreground hover:text-foreground"
            >
              Open editor
            </Link>
          </>
        }
        stickyContent={
          data?.audioUrl && !empty ? (
            <audio
              src={data.audioUrl}
              controls
              preload="none"
              className="h-8 w-full"
              onPlay={(event) => onAudioPlay(clipId, event.currentTarget)}
            />
          ) : null
        }
      >
        {loadError ? (
          <p className="text-sm text-destructive">{loadError}</p>
        ) : !draft ? (
          <Skeleton className="h-24 w-full" />
        ) : empty ? (
          <p className="text-sm text-muted-foreground">
            No transcript yet{summary.sentenceCount === 0 && draft.asr ? " (no speech found)" : ""}.
          </p>
        ) : !tokenized ? (
          <ol className="flex flex-col gap-1 text-base" lang="ja">
            {draft.sentences.map((s, i) => (
              <li key={i}>{s.text}</li>
            ))}
          </ol>
        ) : (
          <ClipTokenLines
            draft={draft}
            active={active}
            editing={editing}
            disabled={busy}
            saving={saving}
            onPlay={(clipSeconds, stopAt) => onPlay(clipId, draft.startSec, clipSeconds, stopAt)}
            onEditTokens={(sentence, tokens) => void editTokens(sentence, tokens)}
            onClearFlags={(sentence, cleared) => void clearFlags(sentence, cleared)}
            english={
              english
                ? {
                    values: english,
                    onChange: (i, value) =>
                      setEnglish((prev) => prev?.map((line, j) => (j === i ? value : line)) ?? prev),
                  }
                : undefined
            }
          />
        )}
      </EditorSection>
    </div>
  );
});
