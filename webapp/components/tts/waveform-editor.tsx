"use client";

import { Fragment, useEffect, useLayoutEffect, useRef, useState } from "react";
import WaveSurfer from "wavesurfer.js";
import RegionsPlugin, { type Region } from "wavesurfer.js/dist/plugins/regions.js";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Play, Pause, Scissors, Download } from "lucide-react";
import { ttsApi, type Variant } from "@/lib/tts/client";
import { cn } from "@/lib/utils";
import type { EditableDialogueLine } from "@/components/tts/dialogue-line-editor";
import { TokenSyncEditor } from "@/components/dialogue/token-sync-editor";
import type { VariantTokenSync } from "@/lib/dialogue/types";
import { enqueueTokenSyncSave } from "@/lib/dialogue/token-sync-persist";

function formatTime(seconds: number): string {
  if (!Number.isFinite(seconds)) return "0:00";
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${m}:${s.toString().padStart(2, "0")}`;
}

/** Splits dialogue lines into the spoken-line list the sentence map is built from. */
function spokenLinesFor(dialogueLines: EditableDialogueLine[]): EditableDialogueLine[] {
  return dialogueLines.flatMap((line) => {
    if (line.kind === "stage") return [];
    return line.text
      .split(/\r?\n/)
      .map((t) => t.trim())
      .filter((t) => t.length > 0)
      .map((text) => ({ id: line.id, speaker: line.speaker, text, kind: "spoken" as const }));
  });
}

type MapListItem =
  | { type: "stage"; key: string; text: string }
  | { type: "spoken"; key: string; row: SentenceMapRow };

function buildMapList(
  dialogueLines: EditableDialogueLine[],
  sentenceRows: SentenceMapRow[],
): MapListItem[] {
  const items: MapListItem[] = [];
  let spokenI = 0;
  dialogueLines.forEach((line, lineIndex) => {
    if (line.kind === "stage") {
      const text = line.text.trim();
      if (!text) return;
      items.push({ type: "stage", key: `stage-${lineIndex}`, text });
      return;
    }
    const parts = line.text
      .split(/\r?\n/)
      .map((t) => t.trim())
      .filter((t) => t.length > 0);
    for (const _ of parts) {
      const row = sentenceRows[spokenI];
      if (row) items.push({ type: "spoken", key: `spoken-${row.index}`, row });
      spokenI += 1;
    }
  });
  return items;
}

/** One-click beat between dialogue lines (physical action, handing something). */
const PLAYHEAD_BREAK_SECONDS = 0.15;
const PLAYHEAD_BREAK_HALF_SECONDS = 0.5;
const PLAYBACK_RATES = [0.5, 0.75, 1] as const;

type SentenceMapRow = {
  index: number;
  speaker: "speaker1" | "speaker2" | null;
  text: string;
  sampleLower: number;
  sampleUpper: number;
};

/** Derives sentence map rows from confirmed line-switch marks — marks are the source of truth, matching the Mac app. */
function buildSentenceMap(
  lines: EditableDialogueLine[],
  marks: number[],
  totalSamples: number
): { rows: SentenceMapRow[]; usesMarks: boolean; validMarkCount: number } {
  if (lines.length === 0 || totalSamples <= 0)
    return { rows: [], usesMarks: false, validMarkCount: 0 };

  const sortedMarks = [...marks].filter((m) => m > 0 && m < totalSamples).sort((a, b) => a - b);
  const usesMarks = sortedMarks.length > 0 && sortedMarks.length + 1 === lines.length;

  const boundaries = usesMarks ? sortedMarks : [];
  const starts = [0, ...boundaries];
  const ends = [...boundaries, totalSamples];

  const rows = lines.map((line, i) => ({
    index: i,
    speaker: line.speaker,
    text: line.text,
    sampleLower: usesMarks ? starts[i] : 0,
    sampleUpper: usesMarks ? ends[i] : 0,
  }));

  return { rows, usesMarks, validMarkCount: sortedMarks.length };
}

/**
 * Which line is currently playing, counted from the marks placed so far.
 * Deliberately not gated on every line having a mark yet — while a line is
 * being marked one at a time, the boundary already placed for line N still
 * tells us the playhead has moved on to line N+1, so the highlight (and
 * auto-scroll) keeps tracking mid-session, not just once fully marked.
 */
function activeSentenceIndexForTime(
  marks: number[],
  currentTime: number,
  sampleRate: number,
  totalLines: number
): number | null {
  if (totalLines === 0 || !Number.isFinite(currentTime)) return null;
  const sample = Math.round(currentTime * sampleRate);
  const sortedMarks = [...marks].filter((m) => m > 0).sort((a, b) => a - b);
  let index = 0;
  for (const mark of sortedMarks) {
    if (sample >= mark) index++;
    else break;
  }
  return Math.min(index, totalLines - 1);
}

export function WaveformEditor({
  projectId,
  variant,
  dialogueLines,
  currentContentHash,
  hasUnsavedChanges,
}: {
  projectId: string;
  variant: Variant;
  dialogueLines?: EditableDialogueLine[];
  currentContentHash?: string;
  hasUnsavedChanges?: boolean;
}) {
  const queryClient = useQueryClient();
  const containerRef = useRef<HTMLDivElement>(null);
  const stripRef = useRef<HTMLDivElement>(null);
  const wavesurferRef = useRef<WaveSurfer | null>(null);
  const regionsRef = useRef<RegionsPlugin | null>(null);
  const trimRegionRef = useRef<Region | null>(null);
  const cutRegionRef = useRef<Region | null>(null);
  const rowRefs = useRef<Record<number, HTMLDivElement | null>>({});
  const playerBarRef = useRef<HTMLDivElement>(null);
  const playerSpacerRef = useRef<HTMLDivElement>(null);
  const sectionRef = useRef<HTMLDivElement>(null);
  const sectionHeaderRef = useRef<HTMLDivElement>(null);
  const variantRef = useRef(variant);
  variantRef.current = variant;

  const [isPlaying, setIsPlaying] = useState(false);
  const [isTrimMode, setIsTrimMode] = useState(false);
  const [isCutMode, setIsCutMode] = useState(false);
  const [hasCutRegion, setHasCutRegion] = useState(false);
  const [duration, setDuration] = useState(0);
  const [currentTime, setCurrentTime] = useState(0);
  const [level, setLevel] = useState(0);
  const [loopingRowIndex, setLoopingRowIndex] = useState<number | null>(null);
  const [suggested, setSuggested] = useState<{ samples: number[]; summary: string }>({
    samples: [],
    summary: "",
  });
  const [dragging, setDragging] = useState<
    { kind: "mark" | "suggested"; index: number } | null
  >(null);
  const [playerBarHeight, setPlayerBarHeight] = useState(0);
  const [sectionHeaderHeight, setSectionHeaderHeight] = useState(0);
  const [timingMode, setTimingMode] = useState<"lines" | "tokens">("lines");
  const [playbackRate, setPlaybackRate] =
    useState<(typeof PLAYBACK_RATES)[number]>(1);
  const playbackRateRef = useRef(playbackRate);
  playbackRateRef.current = playbackRate;

  // Bust the media URL whenever the take's bytes change (cut / commit-trim /
  // insert-line-break). WaveSurfer only remounts when this string changes, and
  // browsers otherwise keep serving the pre-edit WAV from cache.
  const audioUrl = `/api/tts/projects/${projectId}/variants/${variant.id}/audio?v=${variant.audioByteCount}`;
  const marks = variant.dialogueLineSwitchSamples ?? [];
  const sourceLines = dialogueLines ?? [];
  const spokenLines = spokenLinesFor(sourceLines);
  const totalSamples = Math.round(duration * variant.sampleRate);
  const { rows: sentenceRows, usesMarks, validMarkCount } = buildSentenceMap(
    spokenLines,
    marks,
    totalSamples
  );
  const mapList = buildMapList(sourceLines, sentenceRows);
  const activeRowIndex = activeSentenceIndexForTime(
    marks,
    currentTime,
    variant.sampleRate,
    spokenLines.length
  );

  // Keep the currently-playing line in view as the page scrolls — the pinned
  // waveform dock at the bottom would otherwise cover rows near the edge.
  useEffect(() => {
    if (timingMode !== "lines") return;
    if (activeRowIndex == null) return;
    rowRefs.current[activeRowIndex]?.scrollIntoView({
      behavior: "smooth",
      block: "nearest",
    });
  }, [activeRowIndex, timingMode]);

  // Track chrome heights for scroll-margin on active sentence rows.
  useEffect(() => {
    const playerEl = playerBarRef.current;
    const headerEl = sectionHeaderRef.current;
    if (!playerEl && !headerEl) return;
    const observer = new ResizeObserver((entries) => {
      for (const entry of entries) {
        if (entry.target === playerEl) {
          setPlayerBarHeight(entry.contentRect.height);
        } else if (entry.target === headerEl) {
          setSectionHeaderHeight(entry.contentRect.height);
        }
      }
    });
    if (playerEl) observer.observe(playerEl);
    if (headerEl) observer.observe(headerEl);
    return () => observer.disconnect();
  }, []);

  function patchVariantInCache(next: Variant, options?: { refetch?: boolean }) {
    queryClient.setQueryData<{ variants: Variant[] }>(
      ["tts-variants", projectId],
      (old) => {
        if (!old) return old;
        return {
          variants: old.variants.map((v) =>
            v.id === next.id ? { ...v, ...next } : v
          ),
        };
      }
    );
    if (options?.refetch === false) return;
    void queryClient.invalidateQueries({ queryKey: ["tts-variants", projectId] });
  }

  const updateVariantMutation = useMutation({
    mutationFn: (body: Record<string, unknown>) =>
      ttsApi.updateVariant(projectId, variant.id, body),
    onSuccess: (_data, body) => {
      if (Object.keys(body).length === 1 && "tokenSync" in body) return;
      queryClient.invalidateQueries({ queryKey: ["tts-variants", projectId] });
    },
    onError: (error) => toast.error(error.message),
  });

  function persistTokenSync(tokenSync: VariantTokenSync | null) {
    const variantId = variantRef.current.id;
    patchVariantInCache({ ...variantRef.current, tokenSync }, { refetch: false });
    void enqueueTokenSyncSave(() =>
      ttsApi
        .updateVariant(projectId, variantId, { tokenSync })
        .then(() => undefined)
        .catch((error: unknown) => {
          toast.error(
            error instanceof Error ? error.message : "Could not save token timing."
          );
        })
    );
  }

  function setMarks(next: number[]) {
    updateVariantMutation.mutate({
      dialogueLineSwitchSamples: next.length > 0 ? next : null,
    });
  }

  useEffect(() => {
    const containerEl = containerRef.current;
    if (!containerEl) return;
    const container: HTMLElement = containerEl;
    // Guards against React StrictMode's dev-only double-invoke of this effect: the
    // first mount's cleanup destroys this instance before its "ready" (or any other
    // async) callback runs, so those callbacks must no-op instead of touching state
    // or DOM that the second mount's instance now owns.
    let cancelled = false;

    const regions = RegionsPlugin.create();
    const ws = WaveSurfer.create({
      container,
      waveColor: "oklch(0.5 0 0)",
      progressColor: "oklch(0.94 0.19 95)",
      cursorColor: "oklch(0.94 0.19 95)",
      cursorWidth: 1,
      height: 72,
      barWidth: 2,
      barGap: 1,
      url: audioUrl,
      plugins: [regions],
    });

    wavesurferRef.current = ws;
    regionsRef.current = regions;
    // Prior cut selection belonged to the destroyed instance.
    setHasCutRegion(false);

    // Sticky layout can briefly report clientWidth 0 while the browser
    // recomputes stick/unstick. WaveSurfer's own ResizeObserver then reRenders
    // with width 0, clears its canvases, and never paints again if width snaps
    // back to the same non-zero value. Detect an empty canvas host and redraw.
    let lastDrawnWidth = 0;
    let scrollRedrawTimer = 0;
    function waveformCanvasesMissing() {
      const host = container.firstElementChild as HTMLElement | null;
      const canvases = host?.shadowRoot?.querySelectorAll("canvas");
      return !canvases || canvases.length === 0;
    }
    function ensureWaveformPainted() {
      if (cancelled || !container.isConnected) return;
      const width = container.clientWidth;
      if (width <= 0) {
        lastDrawnWidth = 0;
        return;
      }
      if (!ws.getDecodedData()) return;
      if (!waveformCanvasesMissing() && width === lastDrawnWidth) return;
      lastDrawnWidth = width;
      ws.setOptions({});
    }

    const resizeObserver = new ResizeObserver(() => ensureWaveformPainted());
    resizeObserver.observe(container);
    const intersectionObserver = new IntersectionObserver(
      (entries) => {
        if (entries.some((entry) => entry.isIntersecting)) {
          ensureWaveformPainted();
        }
      },
      { threshold: 0 }
    );
    intersectionObserver.observe(container);
    function onScroll() {
      window.clearTimeout(scrollRedrawTimer);
      scrollRedrawTimer = window.setTimeout(ensureWaveformPainted, 50);
    }
    window.addEventListener("scroll", onScroll, true);

    ws.on("ready", (d) => {
      if (cancelled) return;
      setDuration(d);
      const sampleRate = variant.sampleRate;
      const lo = variant.trimSampleLower ?? 0;
      const hi = variant.trimSampleUpper ?? Math.round(d * sampleRate);
      const region = regions.addRegion({
        start: lo / sampleRate,
        end: hi / sampleRate,
        // Color + interactivity are owned by the isTrimMode/isCutMode effect.
        color: "oklch(0.94 0.19 95 / 0%)",
        drag: false,
        resize: false,
      });
      trimRegionRef.current = region;
      if (region.element) region.element.style.pointerEvents = "none";
      lastDrawnWidth = 0;
      ws.setPlaybackRate(playbackRateRef.current, true);
      requestAnimationFrame(() => {
        requestAnimationFrame(ensureWaveformPainted);
      });
    });

    ws.on("audioprocess", (t) => !cancelled && setCurrentTime(t));
    ws.on("interaction", () => !cancelled && setCurrentTime(ws.getCurrentTime()));
    ws.on("play", () => !cancelled && setIsPlaying(true));
    ws.on("pause", () => !cancelled && setIsPlaying(false));
    ws.on("finish", () => !cancelled && setIsPlaying(false));
    ws.on("error", (err) => {
      if (cancelled) return;
      console.error("wavesurfer load error", err);
      toast.error("Failed to load audio waveform.");
    });

    // Thicken the playhead while the user is actively scrubbing so it's easier
    // to grab/track, then shrink it back once the drag ends. Styling the
    // cursor element directly (rather than calling ws.setOptions, which
    // triggers a full waveform reRender on every call) keeps this purely
    // cosmetic with no risk to playback or interactivity.
    function setCursorWidth(px: number) {
      const cursor = ws.getWrapper()?.querySelector<HTMLElement>('[part="cursor"]');
      if (cursor) cursor.style.width = `${px}px`;
    }
    ws.on("dragstart", () => !cancelled && setCursorWidth(3));
    ws.on("dragend", () => !cancelled && setCursorWidth(1));

    // Level meter via an AnalyserNode tapped off wavesurfer's media element.
    let rafId: number;
    let audioCtx: AudioContext | null = null;
    let analyser: AnalyserNode | null = null;
    let dataArray: Uint8Array<ArrayBuffer> | null = null;

    ws.on("ready", () => {
      if (cancelled) return;
      const media = ws.getMediaElement();
      if (!media) return;
      audioCtx = new AudioContext();
      const source = audioCtx.createMediaElementSource(media);
      analyser = audioCtx.createAnalyser();
      analyser.fftSize = 256;
      source.connect(analyser);
      analyser.connect(audioCtx.destination);
      dataArray = new Uint8Array(new ArrayBuffer(analyser.frequencyBinCount));

      function tick() {
        if (analyser && dataArray) {
          analyser.getByteTimeDomainData(dataArray);
          let sum = 0;
          for (let i = 0; i < dataArray.length; i++) {
            const v = (dataArray[i] - 128) / 128;
            sum += v * v;
          }
          setLevel(Math.sqrt(sum / dataArray.length));
        }
        rafId = requestAnimationFrame(tick);
      }
      tick();
    });

    return () => {
      cancelled = true;
      resizeObserver.disconnect();
      intersectionObserver.disconnect();
      window.removeEventListener("scroll", onScroll, true);
      window.clearTimeout(scrollRedrawTimer);
      cancelAnimationFrame(rafId);
      audioCtx?.close().catch(() => {});
      // Drop region refs — the plugin/DOM are about to go away. Cut-mode
      // listeners are torn down by the isCutMode effect when duration resets.
      cutRegionRef.current = null;
      trimRegionRef.current = null;
      ws.destroy();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [audioUrl]);

  useEffect(() => {
    const trim = trimRegionRef.current;
    if (!trim?.element) return;
    trim.setOptions({
      color: isTrimMode ? "oklch(0.94 0.19 95 / 15%)" : "oklch(0.94 0.19 95 / 0%)",
      // Hide edge handles while cutting — the full-width trim region otherwise
      // sits above the waveform with pointer-events and steals the drag that
      // create the cut selection (regions' drag helper preventDefaults moves).
      resize: isTrimMode && !isCutMode,
    });
    trim.element.style.pointerEvents = isTrimMode && !isCutMode ? "all" : "none";
  }, [isTrimMode, isCutMode, duration]);

  // Wire cut-mode drag selection to the live Regions plugin. Kept in an effect
  // (not only in the button handler) so a WaveSurfer remount — e.g. new audio
  // URL — re-enables dragging while the mode toggle stays on.
  useEffect(() => {
    const regions = regionsRef.current;
    if (!isCutMode || !regions || duration <= 0) return;

    const disableDrag = regions.enableDragSelection({
      color: "oklch(0.63 0.24 25 / 20%)",
      drag: false,
      resize: true,
    });

    const unsubscribe = regions.on("region-created", (region) => {
      if (region === trimRegionRef.current) return;
      // Only one cut region at a time — a new drag replaces the last selection.
      if (cutRegionRef.current && cutRegionRef.current !== region) {
        cutRegionRef.current.remove();
      }
      cutRegionRef.current = region;
      // Body is pass-through so the next drag can start a replacement selection
      // on the wrapper; edge handles stay interactive for fine-tuning.
      if (region.element) {
        region.element.style.pointerEvents = "none";
        region.element
          .querySelectorAll<HTMLElement>('[part*="region-handle"]')
          .forEach((el) => {
            el.style.pointerEvents = "all";
          });
      }
      setHasCutRegion(true);
    });

    return () => {
      disableDrag();
      unsubscribe();
    };
  }, [isCutMode, duration]);

  function currentEditSample(): number {
    if (!duration) return 0;
    return Math.min(
      Math.max(Math.round(currentTime * variant.sampleRate), 0),
      totalSamples - 1
    );
  }

  function markLineSwitchAtPlayhead() {
    const sample = currentEditSample();
    if (sample <= 0 || sample >= totalSamples) {
      toast.error("Scrub the playhead to where the next line begins.");
      return;
    }
    if (marks.includes(sample)) return;
    setMarks([...marks, sample].sort((a, b) => a - b));
  }

  function removeLineSwitchMarkNearestPlayhead() {
    if (marks.length === 0) return;
    const sample = currentEditSample();
    let nearestIndex = 0;
    let nearestDist = Infinity;
    marks.forEach((m, i) => {
      const dist = Math.abs(m - sample);
      if (dist < nearestDist) {
        nearestDist = dist;
        nearestIndex = i;
      }
    });
    setMarks(marks.filter((_, i) => i !== nearestIndex));
  }

  function clearLineSwitchMarks() {
    if (marks.length === 0) return;
    setMarks([]);
  }

  const suggestBreaksMutation = useMutation({
    mutationFn: () => ttsApi.suggestBreaks(projectId, variant.id),
    onSuccess: (result) => {
      setSuggested({ samples: result.suggestedSamples, summary: result.summary });
    },
    onError: (error) => toast.error(error.message),
  });

  function applySuggestedMarks() {
    if (suggested.samples.length === 0) return;
    setMarks(suggested.samples);
    setSuggested({ samples: [], summary: "" });
  }

  const insertSilenceMutation = useMutation({
    mutationFn: ({
      sample,
      durationSeconds,
    }: {
      sample: number;
      durationSeconds: number;
    }) => ttsApi.insertLineBreak(projectId, variant.id, sample, durationSeconds),
    onSuccess: ({ variant: next }, { durationSeconds }) => {
      patchVariantInCache(next);
      const label =
        durationSeconds >= 1
          ? durationSeconds.toFixed(1)
          : durationSeconds.toFixed(2);
      toast.success(`Inserted ${label}s silence.`);
    },
    onError: (error) => toast.error(error.message),
  });

  function insertSilenceAt(
    sample: number,
    durationSeconds: number,
    invalidMessage: string
  ) {
    if (sample <= 0 || sample >= totalSamples) {
      toast.error(invalidMessage);
      return;
    }
    insertSilenceMutation.mutate({ sample, durationSeconds });
  }

  function insertLineBreak(durationSeconds: number = PLAYHEAD_BREAK_SECONDS) {
    insertSilenceAt(
      currentEditSample(),
      durationSeconds,
      "Move the playhead to a spot between lines, not at the very start or end."
    );
  }

  function insertPauseAfterStage(itemIndex: number) {
    const nextSpoken = mapList
      .slice(itemIndex + 1)
      .find((item) => item.type === "spoken");
    const sample =
      nextSpoken && usesMarks && nextSpoken.row.sampleLower > 0
        ? nextSpoken.row.sampleLower
        : 1;
    insertSilenceAt(
      sample,
      PLAYHEAD_BREAK_HALF_SECONDS,
      "Can't insert silence here.",
    );
  }

  const timingModeRef = useRef(timingMode);
  timingModeRef.current = timingMode;

  useEffect(() => {
    function onKeyDown(e: KeyboardEvent) {
      const target = e.target as HTMLElement | null;
      if (target && ["INPUT", "TEXTAREA"].includes(target.tagName)) return;
      if (e.code === "Space") {
        e.preventDefault();
        toggleMainPlayback();
      } else if (
        timingModeRef.current === "lines" &&
        (e.key === "m" || e.key === "M")
      ) {
        e.preventDefault();
        markLineSwitchAtPlayhead();
      }
    }
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [currentTime, duration, marks]);

  function playRow(row: SentenceMapRow) {
    const ws = wavesurferRef.current;
    if (!ws || !usesMarks) return;
    // Explicitly pausing before seeking (rather than seeking straight into a
    // still-playing element, e.g. jumping from row 4 to row 3) ensures the new
    // position reliably takes. Unlike wavesurfer's own play(start, end) — an
    // async-generator wrapper that can land its play() call outside the
    // click's synchronous gesture window — pause/seek/play here all run
    // directly on the native <audio> element in the same tick, which browsers
    // handle fine and keeps play() inside the user gesture.
    if (ws.isPlaying()) ws.pause();
    ws.setTime(row.sampleLower / variant.sampleRate);
    setLoopingRowIndex(row.index);
    void ws.play();
  }

  /** Main transport: clears per-row loop so full-track QC can run through the map. */
  function toggleMainPlayback() {
    setLoopingRowIndex(null);
    wavesurferRef.current?.playPause();
  }

  useEffect(() => {
    wavesurferRef.current?.setPlaybackRate(playbackRate, true);
  }, [playbackRate]);

  useEffect(() => {
    const ws = wavesurferRef.current;
    if (!ws || loopingRowIndex == null) return;
    const row = sentenceRows[loopingRowIndex];
    if (!row) return;
    const startTime = row.sampleLower / variant.sampleRate;
    const endTime = row.sampleUpper / variant.sampleRate;
    // A leftover audioprocess tick from whatever was playing before this row
    // was selected (e.g. the previous row's end-of-clip position, which can
    // be >= this row's own endTime) can still be in flight when this listener
    // subscribes. Requiring one tick to land strictly inside [startTime,
    // endTime) before arming the stop check means only genuine progress from
    // *this* row's own playback — not a stale leftover from elsewhere in the
    // clip — can trigger it.
    let armed = false;
    const unsub = ws.on("audioprocess", (t) => {
      if (!armed) {
        if (t >= startTime && t < endTime) armed = true;
        return;
      }
      if (t >= endTime) {
        ws.pause();
        setLoopingRowIndex(null);
      }
    });
    return unsub;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [loopingRowIndex]);

  // Drag handling for green (confirmed) and orange (suggested) marker triangles.
  useEffect(() => {
    if (!dragging) return;
    const strip = stripRef.current;
    if (!strip || duration === 0) return;

    function onMove(e: PointerEvent) {
      if (!strip || !dragging) return;
      const rect = strip.getBoundingClientRect();
      const ratio = Math.min(1, Math.max(0, (e.clientX - rect.left) / rect.width));
      const sample = Math.round(ratio * totalSamples);
      const left = `${(sample / totalSamples) * 100}%`;
      const el = strip.querySelector<HTMLElement>(
        `[data-${dragging.kind}="${dragging.index}"]`
      );
      if (el) el.style.left = left;
      const guideRoot = containerRef.current?.parentElement;
      const guide = guideRoot?.querySelector<HTMLElement>(
        `[data-${dragging.kind}-guide="${dragging.index}"]`
      );
      if (guide) guide.style.left = left;
      strip.dataset.pendingSample = String(sample);
    }

    function onUp() {
      const pending = strip?.dataset.pendingSample;
      if (pending != null && dragging) {
        const sample = Number(pending);
        if (dragging.kind === "mark") {
          const next = [...marks];
          next[dragging.index] = sample;
          setMarks(next.sort((a, b) => a - b));
        } else {
          setSuggested((prev) => {
            const next = [...prev.samples];
            next[dragging.index] = sample;
            return { ...prev, samples: next.sort((a, b) => a - b) };
          });
        }
      }
      if (strip) delete strip.dataset.pendingSample;
      setDragging(null);
    }

    window.addEventListener("pointermove", onMove);
    window.addEventListener("pointerup", onUp, { once: true });
    return () => {
      window.removeEventListener("pointermove", onMove);
      window.removeEventListener("pointerup", onUp);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [dragging, duration]);

  const saveTrimMutation = useMutation({
    mutationFn: () => {
      const region = trimRegionRef.current;
      if (!region) throw new Error("No trim region");
      const sampleRate = variant.sampleRate;
      return ttsApi.updateVariant(projectId, variant.id, {
        trimSampleLower: Math.round(region.start * sampleRate),
        trimSampleUpper: Math.round(region.end * sampleRate),
      });
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["tts-variants", projectId] });
      toast.success("Trim saved.");
    },
    onError: (error) => toast.error(error.message),
  });

  const commitTrimMutation = useMutation({
    mutationFn: async () => {
      const res = await fetch(
        `/api/tts/projects/${projectId}/variants/${variant.id}/commit-trim`,
        { method: "POST" }
      );
      if (!res.ok) {
        const body = await res.json().catch(() => ({}));
        throw new Error(
          typeof body?.error === "string" ? body.error : "Failed to commit trim"
        );
      }
      return res.json() as Promise<{ variant: Variant }>;
    },
    onSuccess: ({ variant: next }) => {
      patchVariantInCache(next);
      toast.success("Trim applied — take shortened.");
    },
    onError: (error) => toast.error(error.message),
  });

  const removeGapMutation = useMutation({
    mutationFn: async (range: { startSample: number; endSample: number }) => {
      const res = await fetch(
        `/api/tts/projects/${projectId}/variants/${variant.id}/remove-gap`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(range),
        }
      );
      if (!res.ok) {
        const body = await res.json().catch(() => ({}));
        throw new Error(
          typeof body?.error === "string" ? body.error : "Failed to remove gap"
        );
      }
      return res.json() as Promise<{ variant: Variant }>;
    },
    onSuccess: ({ variant: next }) => {
      patchVariantInCache(next);
      toast.success("Section removed — audio spliced back together.");
      exitCutMode();
    },
    onError: (error) => toast.error(error.message),
  });

  const exportMutation = useMutation({
    mutationFn: async (format: "wav" | "mp3" | "m4a") => {
      const res = await fetch(
        `/api/tts/projects/${projectId}/variants/${variant.id}/export`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ format }),
        }
      );
      if (!res.ok) {
        const body = await res.json().catch(() => ({}));
        throw new Error(body?.error ?? "Export failed");
      }
      return res.json() as Promise<{ export: { id: string } }>;
    },
    onSuccess: ({ export: record }, format) => {
      queryClient.invalidateQueries({
        queryKey: ["tts-exports", variant.id],
      });
      toast.success(`Exported as ${format.toUpperCase()}.`);
      window.location.href = `/api/tts/projects/${projectId}/variants/${variant.id}/exports/${record.id}`;
    },
    onError: (error) => toast.error(error.message),
  });

  function exitCutMode() {
    cutRegionRef.current?.remove();
    cutRegionRef.current = null;
    setHasCutRegion(false);
    setIsCutMode(false);
  }

  function toggleCutMode() {
    if (isCutMode) {
      exitCutMode();
      return;
    }
    if (!regionsRef.current) return;
    // Leave trim editing so its region can't sit on top of the waveform and
    // swallow the cut drag (see the isTrimMode/isCutMode effect above).
    if (isTrimMode) setIsTrimMode(false);
    setIsCutMode(true);
    toast.info("Drag across the waveform to select the section to remove.");
  }

  function removeCutRegion() {
    const region = cutRegionRef.current;
    if (!region) {
      toast.error("Drag across the waveform to select a section first.");
      return;
    }
    const sampleRate = variant.sampleRate;
    const startSample = Math.round(region.start * sampleRate);
    const endSample = Math.round(region.end * sampleRate);
    if (endSample <= startSample) {
      toast.error("Selected section is empty.");
      return;
    }
    removeGapMutation.mutate({ startSample, endSample });
  }

  const isConversation = (dialogueLines?.length ?? 0) > 0;

  // Pin the waveform to the viewport bottom only while this section still
  // extends past the viewport. Releases as soon as the section end enters
  // view so the following page content is never covered.
  useLayoutEffect(() => {
    if (!isConversation) return;
    const sectionEl = sectionRef.current;
    const playerEl = playerBarRef.current;
    const spacerEl = playerSpacerRef.current;
    if (!sectionEl || !playerEl || !spacerEl) return;
    const section: HTMLElement = sectionEl;
    const player: HTMLElement = playerEl;
    const spacer: HTMLElement = spacerEl;

    function updatePin() {
      const sectionRect = section.getBoundingClientRect();
      const playerHeight = player.offsetHeight;
      const viewH = window.innerHeight;
      const shouldPin =
        sectionRect.bottom > viewH && sectionRect.top < viewH - playerHeight;

      if (shouldPin) {
        player.style.position = "fixed";
        player.style.bottom = "0px";
        player.style.left = `${sectionRect.left}px`;
        player.style.width = `${sectionRect.width}px`;
        player.style.zIndex = "30";
        spacer.style.height = `${playerHeight}px`;
      } else {
        player.style.position = "";
        player.style.bottom = "";
        player.style.left = "";
        player.style.width = "";
        player.style.zIndex = "";
        spacer.style.height = "0px";
      }
    }

    updatePin();
    window.addEventListener("scroll", updatePin, true);
    window.addEventListener("resize", updatePin);
    const observer = new ResizeObserver(updatePin);
    observer.observe(section);
    observer.observe(player);
    return () => {
      window.removeEventListener("scroll", updatePin, true);
      window.removeEventListener("resize", updatePin);
      observer.disconnect();
      player.style.position = "";
      player.style.bottom = "";
      player.style.left = "";
      player.style.width = "";
      player.style.zIndex = "";
      spacer.style.height = "";
    };
  }, [isConversation, sentenceRows.length, playerBarHeight, timingMode]);

  const playerTools = (
    <>
      <div className="relative w-full">
        <div ref={containerRef} className="h-[72px] w-full" />
        {isConversation && timingMode === "lines" && duration > 0 && (
          <div className="pointer-events-none absolute inset-0 z-[1]">
            {suggested.samples.map((sample, i) => (
              <div
                key={`suggested-guide-${i}`}
                data-suggested-guide={i}
                className={`absolute top-0 bottom-0 -translate-x-1/2 ${
                  dragging?.kind === "suggested" && dragging.index === i
                    ? "w-0.5 bg-orange-500/50"
                    : "w-px bg-orange-500/30"
                }`}
                style={{ left: `${(sample / totalSamples) * 100}%` }}
              />
            ))}
            {marks.map((sample, i) => (
              <div
                key={`mark-guide-${i}`}
                data-mark-guide={i}
                className={`absolute top-0 bottom-0 -translate-x-1/2 ${
                  dragging?.kind === "mark" && dragging.index === i
                    ? "w-0.5 bg-emerald-500/55"
                    : "w-px bg-emerald-500/35"
                }`}
                style={{ left: `${(sample / totalSamples) * 100}%` }}
              />
            ))}
          </div>
        )}
      </div>

      {isConversation && timingMode === "lines" && duration > 0 && (
        <div
          ref={stripRef}
          className="relative h-4 w-full overflow-visible rounded-sm bg-muted/50"
        >
          {suggested.samples.map((sample, i) => (
            <div
              key={`suggested-${i}`}
              data-suggested={i}
              onPointerDown={(e) => {
                e.preventDefault();
                setDragging({ kind: "suggested", index: i });
              }}
              className="absolute top-0 z-10 h-full w-5 -translate-x-1/2 touch-manipulation cursor-ew-resize sm:w-3"
              style={{ left: `${(sample / totalSamples) * 100}%` }}
              title={`Suggested break at ${(sample / variant.sampleRate).toFixed(2)}s`}
            >
              <div className="mx-auto h-0 w-0 border-x-4 border-t-4 border-x-transparent border-t-orange-500" />
            </div>
          ))}
          {marks.map((sample, i) => (
            <div
              key={`mark-${i}`}
              data-mark={i}
              onPointerDown={(e) => {
                e.preventDefault();
                setDragging({ kind: "mark", index: i });
              }}
              className="absolute top-0 z-10 h-full w-5 -translate-x-1/2 touch-manipulation cursor-ew-resize sm:w-3"
              style={{ left: `${(sample / totalSamples) * 100}%` }}
              title={`Line switch at ${(sample / variant.sampleRate).toFixed(2)}s`}
            >
              <div className="mx-auto h-0 w-0 border-x-4 border-t-4 border-x-transparent border-t-emerald-500" />
            </div>
          ))}
        </div>
      )}

      <div className="flex flex-wrap items-center gap-2 sm:gap-3">
        <Button
          size="icon"
          variant="outline"
          className="size-11 touch-manipulation md:size-8"
          aria-label={isPlaying ? "Pause" : "Play"}
          onClick={() => toggleMainPlayback()}
        >
          {isPlaying ? (
            <Pause className="size-5 md:size-3.5" />
          ) : (
            <Play className="size-5 md:size-3.5" />
          )}
        </Button>
        {isConversation && timingMode === "lines" && (
          <>
            <Button
              size="sm"
              className="min-h-11 touch-manipulation px-3 md:min-h-8"
              onClick={markLineSwitchAtPlayhead}
            >
              Mark
            </Button>
            <Button
              size="sm"
              variant="outline"
              className="min-h-11 touch-manipulation px-3 md:min-h-8"
              onClick={removeLineSwitchMarkNearestPlayhead}
              disabled={marks.length === 0}
            >
              Undo mark
            </Button>
          </>
        )}
        <span className="text-xs tabular-nums text-muted-foreground">
          {formatTime(currentTime)} / {formatTime(duration)}
        </span>
        <div
          className="flex items-center rounded-md border border-border/60 p-0.5"
          title="Playback speed"
        >
          {PLAYBACK_RATES.map((rate) => (
            <Button
              key={rate}
              size="xs"
              variant={playbackRate === rate ? "secondary" : "ghost"}
              className="h-8 min-w-9 touch-manipulation px-1.5 tabular-nums md:h-6 md:min-w-8"
              onClick={() => setPlaybackRate(rate)}
            >
              {rate}×
            </Button>
          ))}
        </div>
        <div className="h-2 min-w-[4rem] flex-1 overflow-hidden rounded-full bg-muted">
          <div
            className="h-full bg-primary transition-[width] duration-75"
            style={{ width: `${Math.min(100, level * 300)}%` }}
          />
        </div>
      </div>

      {isConversation && timingMode === "lines" && (
        <p className="text-xs text-muted-foreground">
          Scrub the waveform, then tap <span className="font-medium text-foreground">Mark</span>{" "}
          (or the active line) when the next line starts —{" "}
          <span className="font-medium text-foreground">Undo mark</span> removes the nearest.
          On desktop: Space play/pause, M mark. Drag green triangles to fine-tune. Orange = auto breaks.
        </p>
      )}
      {isConversation && timingMode === "tokens" && (
        <p className="text-xs text-muted-foreground">
          Play/pause below. Stamp tokens in the list above — tap{" "}
          <span className="font-medium text-foreground">Stamp</span> or the next (amber) word.
          <span className="font-medium text-foreground"> Undo</span> clears the last stamp.
          On desktop: Space play/pause, T stamps, Backspace undoes.
        </p>
      )}

      {isConversation && timingMode === "lines" && duration > 0 && (
        <div className="flex flex-col gap-2 rounded-md border border-orange-500/20 bg-orange-500/5 p-2.5">
          <p className="text-xs font-semibold">Line break alignment</p>
          <p className="text-xs text-muted-foreground">
            {suggestBreaksMutation.isPending
              ? "Detecting…"
              : suggested.summary || "Detect where the app would split your dialogue lines."}
          </p>
          <div className="flex flex-wrap items-center gap-2">
            <Button
              size="sm"
              variant="outline"
              onClick={() => suggestBreaksMutation.mutate()}
              disabled={suggestBreaksMutation.isPending}
            >
              Detect breaks
            </Button>
            <Button
              size="sm"
              variant="outline"
              onClick={applySuggestedMarks}
              disabled={suggested.samples.length === 0}
            >
              Apply suggested
            </Button>
            {marks.length > 0 && (
              <span className="text-xs text-emerald-600 dark:text-emerald-400">
                {marks.length} green mark{marks.length === 1 ? "" : "s"}
              </span>
            )}
          </div>
        </div>
      )}

      {(timingMode === "lines" || !isConversation) && (
        <>
          <div className="flex flex-wrap items-center gap-2">
            <Button
              size="sm"
              variant="outline"
              onClick={() => setIsTrimMode((v) => !v)}
            >
              {isTrimMode ? "Done trimming" : "Trim…"}
            </Button>
            {isTrimMode && (
              <>
                <Button
                  size="sm"
                  variant="outline"
                  onClick={() => saveTrimMutation.mutate()}
                  disabled={saveTrimMutation.isPending}
                >
                  Save trim
                </Button>
                <Button
                  size="sm"
                  variant="outline"
                  onClick={() => commitTrimMutation.mutate()}
                  disabled={commitTrimMutation.isPending}
                >
                  <Scissors className="size-3.5" />
                  Apply trim to take
                </Button>
              </>
            )}
            {isConversation && (
              <>
                <Button
                  size="sm"
                  variant="outline"
                  className="min-h-10 touch-manipulation md:min-h-7"
                  onClick={markLineSwitchAtPlayhead}
                >
                  Mark line switch
                </Button>
                <Button
                  size="sm"
                  variant="outline"
                  className="min-h-10 touch-manipulation md:min-h-7"
                  onClick={removeLineSwitchMarkNearestPlayhead}
                  disabled={marks.length === 0}
                >
                  Undo nearest mark
                </Button>
                {marks.length > 0 && (
                  <Button
                    size="sm"
                    variant="outline"
                    className="min-h-10 touch-manipulation md:min-h-7"
                    onClick={clearLineSwitchMarks}
                  >
                    Clear line marks
                  </Button>
                )}
                <Button
                  size="sm"
                  variant="outline"
                  className="min-h-10 touch-manipulation md:min-h-7"
                  onClick={() => insertLineBreak(PLAYHEAD_BREAK_SECONDS)}
                  disabled={insertSilenceMutation.isPending}
                >
                  Insert line break (0.15s)
                </Button>
                <Button
                  size="sm"
                  variant="outline"
                  className="min-h-10 touch-manipulation md:min-h-7"
                  onClick={() => insertLineBreak(PLAYHEAD_BREAK_HALF_SECONDS)}
                  disabled={insertSilenceMutation.isPending}
                >
                  Insert line break (0.5s)
                </Button>
              </>
            )}
            <Button size="sm" variant="outline" onClick={toggleCutMode}>
              {isCutMode ? "Cancel cut" : "Cut section…"}
            </Button>
            {isCutMode && (
              <Button
                size="sm"
                variant="outline"
                onClick={removeCutRegion}
                disabled={!hasCutRegion || removeGapMutation.isPending}
              >
                <Scissors className="size-3.5" />
                Remove selected section
              </Button>
            )}
          </div>
          {isCutMode && (
            <p className="text-xs text-muted-foreground">
              Drag across the waveform to select the section to cut, then drag its edges to
              fine-tune. The selected audio is deleted and the remaining audio spliced together.
            </p>
          )}
        </>
      )}
    </>
  );

  return (
    <div className="flex min-w-0 flex-col gap-3">
      {isConversation ? (
        <div ref={sectionRef} className="relative flex flex-col">
          <div
            ref={sectionHeaderRef}
            className="sticky top-14 z-20 flex flex-col gap-2 bg-background pb-2"
          >
            <Tabs
              value={timingMode}
              onValueChange={(value) => {
                if (value === "lines" || value === "tokens") {
                  setLoopingRowIndex(null);
                  setIsTrimMode(false);
                  setIsCutMode(false);
                  setDragging(null);
                  setTimingMode(value);
                }
              }}
            >
              <TabsList className="h-auto min-h-10 touch-manipulation">
                <TabsTrigger value="lines" className="min-h-9 px-3">
                  Line timing
                </TabsTrigger>
                <TabsTrigger value="tokens" className="min-h-9 px-3">
                  Token timing
                </TabsTrigger>
              </TabsList>
            </Tabs>
            {timingMode === "lines" && (
              <>
                <p className="text-sm font-medium">Sentence map</p>
                {usesMarks ? (
                  <p className="text-xs text-emerald-600 dark:text-emerald-400">
                    One row per audio segment ({sentenceRows.length} lines, {marks.length}{" "}
                    breaks). Ranges follow your marks. Playhead highlights the active
                    sentence for QC.
                  </p>
                ) : spokenLines.length > 1 ? (
                  (() => {
                    const needed = spokenLines.length - 1;
                    const delta = needed - validMarkCount;
                    if (delta > 0) {
                      return (
                        <p className="text-xs text-muted-foreground">
                          One row per spoken line. Place {delta} more line break
                          {delta === 1 ? "" : "s"} ({validMarkCount} of {needed} placed) to
                          align audio with marks.
                        </p>
                      );
                    }
                    return (
                      <p className="text-xs text-amber-600 dark:text-amber-400">
                        {-delta} extra mark{-delta === 1 ? "" : "s"} for {spokenLines.length}{" "}
                        lines ({validMarkCount} placed, {needed} needed). Remove the extra
                        mark{-delta === 1 ? "" : "s"}, or check whether the script changed
                        since these were placed.
                      </p>
                    );
                  })()
                ) : null}
              </>
            )}
            {timingMode === "tokens" && (
              <p className="text-sm font-medium">Token karaoke</p>
            )}
          </div>
          {timingMode === "lines" && (
          <div className="flex flex-col gap-1.5">
            {mapList.map((item, itemIndex) => {
              if (item.type === "stage") {
                return (
                  <Fragment key={item.key}>
                    <div className="flex items-start gap-2 rounded-md border border-dashed border-border/80 bg-muted/20 px-2 py-1.5 text-xs">
                      <div className="mt-0.5 size-3.5 shrink-0" />
                      <div className="flex flex-1 flex-col gap-1">
                        <div className="flex items-center gap-1.5">
                          <span className="rounded-full bg-muted-foreground/15 px-1.5 py-0.5 text-[10px] font-medium italic text-muted-foreground">
                            stage
                          </span>
                          <span className="text-[10px] text-muted-foreground">
                            cold
                          </span>
                        </div>
                        <span className="italic text-muted-foreground">{item.text}</span>
                      </div>
                    </div>
                    <div className="flex items-center gap-2 px-8 py-0.5">
                      <div className="h-px flex-1 bg-border/50" />
                      <Button
                        type="button"
                        size="xs"
                        variant="outline"
                        title="Insert 0.5s of silence after this stage line"
                        disabled={insertSilenceMutation.isPending || totalSamples <= 1}
                        onClick={() => insertPauseAfterStage(itemIndex)}
                      >
                        +0.5s
                      </Button>
                      <div className="h-px flex-1 bg-border/50" />
                    </div>
                  </Fragment>
                );
              }
              const row = item.row;
              const isLooping = loopingRowIndex === row.index;
              const isActive = activeRowIndex === row.index;
              const isHighlighted = isLooping || isActive;
              return (
                <Fragment key={item.key}>
                <div
                  ref={(el) => {
                    rowRefs.current[row.index] = el;
                  }}
                  onClick={() => {
                    if (isActive) {
                      markLineSwitchAtPlayhead();
                      return;
                    }
                    if (usesMarks) playRow(row);
                  }}
                  className={cn(
                    "flex touch-manipulation items-start gap-2 rounded-md border px-2 py-2.5 text-xs transition-colors md:py-1.5",
                    isHighlighted
                      ? "border-primary bg-primary/10"
                      : "border-border/40",
                    "cursor-pointer"
                  )}
                  style={{
                    scrollMarginTop: 56 + sectionHeaderHeight + 16,
                    scrollMarginBottom: playerBarHeight + 24,
                  }}
                  title={
                    isActive
                      ? "Tap to mark a line switch at the playhead"
                      : usesMarks
                        ? "Tap to play this line"
                        : undefined
                  }
                >
                  <button
                    type="button"
                    onClick={(e) => {
                      e.stopPropagation();
                      playRow(row);
                    }}
                    disabled={!usesMarks}
                    className="mt-0.5 flex size-9 shrink-0 items-center justify-center touch-manipulation text-muted-foreground hover:text-foreground disabled:opacity-30 md:size-auto"
                  >
                    {isLooping ? (
                      <Pause className="size-4 md:size-3.5" />
                    ) : (
                      <Play className="size-4 md:size-3.5" />
                    )}
                  </button>
                  <div className="flex min-w-0 flex-1 flex-col gap-1">
                    <div className="flex items-center gap-1.5">
                      <span
                        className={cn(
                          "size-1.5 shrink-0 rounded-full transition-opacity",
                          isHighlighted
                            ? "bg-primary opacity-100"
                            : "bg-transparent opacity-0"
                        )}
                        aria-hidden
                      />
                      <span className="font-mono text-[10px] text-muted-foreground">
                        #{row.index + 1}
                      </span>
                      <span
                        className={cn(
                          "rounded-full px-1.5 py-0.5 text-[10px] font-medium",
                          usesMarks
                            ? "bg-emerald-500/15 text-emerald-600 dark:text-emerald-400"
                            : "bg-muted-foreground/15 text-muted-foreground"
                        )}
                      >
                        {usesMarks ? "ready" : "pending"}
                      </span>
                      {usesMarks && (
                        <span className="rounded-full bg-emerald-500/15 px-1.5 py-0.5 text-[10px] font-medium text-emerald-600 dark:text-emerald-400">
                          marked
                        </span>
                      )}
                      {isActive && (
                        <span className="rounded-full bg-primary/15 px-1.5 py-0.5 text-[10px] font-medium text-primary">
                          {isPlaying ? "playing" : "playhead"}
                        </span>
                      )}
                    </div>
                    <span className={cn(isHighlighted && "font-medium")}>{row.text}</span>
                    {usesMarks && (
                      <span className="font-mono text-[10px] text-muted-foreground">
                        {(row.sampleLower / variant.sampleRate).toFixed(2)}s –{" "}
                        {(row.sampleUpper / variant.sampleRate).toFixed(2)}s ·{" "}
                        {(
                          (row.sampleUpper - row.sampleLower) /
                          variant.sampleRate
                        ).toFixed(2)}
                        s
                      </span>
                    )}
                  </div>
                </div>
                </Fragment>
              );
            })}
          </div>
          )}
          {timingMode === "tokens" && spokenLines.length > 0 && (
            <TokenSyncEditor
              variant={variant}
              spokenLines={spokenLines.map((line) => ({
                speaker: line.speaker,
                text: line.text,
              }))}
              currentTime={currentTime}
              duration={duration}
              usesMarks={usesMarks}
              currentContentHash={currentContentHash}
              hasUnsavedChanges={hasUnsavedChanges}
              enableHotkeys
              onGetPlayhead={() =>
                wavesurferRef.current?.getCurrentTime() ?? currentTime
              }
              onPlayLine={(lineIndex) => {
                const ws = wavesurferRef.current;
                if (!ws) return;
                if (loopingRowIndex === lineIndex && ws.isPlaying()) {
                  ws.pause();
                  setLoopingRowIndex(null);
                  return;
                }
                const row = sentenceRows[lineIndex];
                if (row && usesMarks) {
                  playRow(row);
                  return;
                }
                if (lineIndex === 0) {
                  if (ws.isPlaying()) ws.pause();
                  ws.setTime(0);
                  setLoopingRowIndex(null);
                  void ws.play();
                }
              }}
              playingLineIndex={loopingRowIndex}
              onPersist={persistTokenSync}
            />
          )}
          {/* Holds layout space while the player is fixed to the viewport bottom. */}
          <div ref={playerSpacerRef} aria-hidden />
          <div
            ref={playerBarRef}
            className="flex flex-col gap-3 border-t border-border/60 bg-background pt-3 pb-[max(0.75rem,env(safe-area-inset-bottom))] shadow-[0_-8px_24px_-12px_rgba(0,0,0,0.35)]"
          >
            {playerTools}
          </div>
        </div>
      ) : (
        <div className="flex flex-col gap-3">{playerTools}</div>
      )}

      <div className="flex flex-wrap items-center gap-2 border-t border-border/60 pt-3">
        {(["wav", "mp3", "m4a"] as const).map((format) => (
          <Button
            key={format}
            size="sm"
            variant="ghost"
            onClick={() => exportMutation.mutate(format)}
            disabled={exportMutation.isPending}
          >
            <Download className="size-3.5" />
            {format.toUpperCase()}
          </Button>
        ))}
      </div>
    </div>
  );
}
