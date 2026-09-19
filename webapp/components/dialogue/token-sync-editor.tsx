"use client";

import {
  useEffect,
  useImperativeHandle,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
  type MouseEvent,
  type PointerEvent as ReactPointerEvent,
  type Ref,
  type RefObject,
} from "react";
import { useMutation } from "@tanstack/react-query";
import { toast } from "sonner";
import { Play, Pause } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { dialogueApi } from "@/lib/dialogue/client";
import { ttsApi } from "@/lib/tts/client";
import type { AutoStampResult, Variant } from "@/lib/tts/client";
import type { TokenSyncFlag, VariantTokenSync } from "@/lib/dialogue/types";
import { cn } from "@/lib/utils";
import {
  AutoStampControls,
  type AutoStampControlsState,
} from "@/components/tts/auto-stamp-controls";
import {
  activeTokenIndexForTime,
  applyTokenSelection,
  applyLineStartToFirstTokens,
  clearAllStamps,
  clearFlagsForReviewed,
  clearFlagsForToken,
  clearLineStamps,
  clearStampsFrom,
  lineDisplayPieces,
  lineStartSecondsForTokenSync,
  mergeTokenWithNext,
  midpointSplitOffset,
  parseVariantTokenSync,
  splitTokenAt,
  restampToken,
  seekSecondsBeforeToken,
  spokenLineWindows,
  tokenSyncFromSurfaces,
  tokenSyncStatus,
  unstampLastToken,
  type TokenSyncStatus,
} from "@/lib/dialogue/token-sync";

const LONG_PRESS_MS = 550;
const STUDIO_BUILD = process.env.NEXT_PUBLIC_BUILD_SHA ?? "dev";
/** Takes whose first open was already reported this page load (KA-8). */
const reportedOpens = new Set<string>();

function reportReviewEvent(
  variant: Pick<Variant, "id" | "projectId">,
  event: "opened" | "reviewed"
) {
  if (event === "opened") {
    if (reportedOpens.has(variant.id)) return;
    reportedOpens.add(variant.id);
  }
  void ttsApi.reviewEvent(variant.projectId, variant.id, event).catch(() => undefined);
}

const STATUS_LABEL: Record<TokenSyncStatus, string> = {
  missing: "not started",
  stale: "stale",
  "tokens-only": "stamping",
  complete: "complete",
};

function formatStamp(seconds: number): string {
  return `${seconds.toFixed(2)}s`;
}

const FLAG_LABEL: Record<TokenSyncFlag["code"], string> = {
  "stamp-in-silence": "stamp in silence",
  "script-mismatch": "script mismatch",
  "reading-fallback": "reading fallback",
  "no-gap": "no gap before line",
};

function flagKey(lineIndex: number, tokenIndex: number): string {
  return `${lineIndex}:${tokenIndex}`;
}

/**
 * Stamp/undo handed up to the host so the shared transport dock (and its
 * M / Backspace hotkeys) can drive token timing without duplicating the logic.
 */
export type TokenSyncActions = {
  stamp: () => void;
  undo: () => void;
};

export type TokenSyncAvailability = {
  canStamp: boolean;
  canUndo: boolean;
};

export function TokenSyncEditor({
  variant,
  spokenLines,
  currentTime,
  duration,
  usesMarks,
  currentContentHash,
  hasUnsavedChanges,
  playbackRate = 1,
  actionsRef,
  onAvailabilityChange,
  onPersist,
  onGetPlayhead,
  onPlayLine,
  onPlayFromSeconds,
  playingLineIndex,
  autoStampControls,
  autoStampDisabled: autoStampDisabledProp,
  onAutoStampSuccessRef,
  focusLineIndex = null,
}: {
  variant: Variant;
  spokenLines: Array<{ speaker: string; text: string }>;
  currentTime: number;
  duration: number;
  usesMarks: boolean;
  currentContentHash?: string;
  hasUnsavedChanges?: boolean;
  /** Transport playback rate; tap-lookback is scaled into media time from this. */
  playbackRate?: number;
  actionsRef?: Ref<TokenSyncActions | null>;
  onAvailabilityChange?: (state: TokenSyncAvailability) => void;
  onPersist: (tokenSync: VariantTokenSync | null) => void;
  onGetPlayhead?: () => number;
  onPlayLine?: (lineIndex: number) => void;
  /** Seek + play from an absolute playhead time (mid-line stamp recovery). */
  onPlayFromSeconds?: (seconds: number) => void;
  playingLineIndex?: number | null;
  /** Shared with the Audio mode picker chrome so labels/state stay in sync. */
  autoStampControls?: AutoStampControlsState;
  autoStampDisabled?: boolean;
  /** Host ref; editor installs a handler to jump to the first flag after stamp. */
  onAutoStampSuccessRef?: RefObject<((result: AutoStampResult) => void) | null>;
  /** Review-queue deep link: scroll this line into view and select a token. */
  focusLineIndex?: number | null;
}) {
  const spokenTexts = useMemo(
    () => spokenLines.map((line) => line.text.trim()).filter(Boolean),
    [spokenLines]
  );
  const sync = useMemo(
    () => parseVariantTokenSync(variant.tokenSync),
    [variant.tokenSync]
  );
  const contentHash = currentContentHash ?? variant.contentHash ?? "";
  const status = tokenSyncStatus(sync, contentHash, spokenTexts);
  const totalSamples = Math.round(duration * variant.sampleRate);
  const windows = spokenLineWindows({
    markSamples: variant.dialogueLineSwitchSamples ?? [],
    spokenCount: spokenTexts.length,
    sampleRate: variant.sampleRate,
    totalSamples,
  });

  const [selectedToken, setSelectedToken] = useState<{
    lineIndex: number;
    tokenIndex: number;
  } | null>(null);
  const [tokenMenu, setTokenMenu] = useState<{
    lineIndex: number;
    tokenIndex: number;
    x: number;
    y: number;
  } | null>(null);
  const lineRefs = useRef<Record<number, HTMLDivElement | null>>({});
  const focusAppliedRef = useRef<number | null>(null);

  const tokenizeMutation = useMutation({
    mutationFn: () => dialogueApi.tokenizeLines(spokenTexts),
    onSuccess: ({ lines }) => {
      const next = tokenSyncFromSurfaces({
        lines,
        contentHash,
        lineStartSeconds: lineStartSecondsForTokenSync(windows, lines.length),
      });
      commitSync(next, firstUnstamped(next));
      toast.success(
        "Tokenized. First word of each line is already timed from the line mark — Stamp the rest."
      );
    },
    onError: (error) => toast.error(error.message),
  });

  // Install selection jump for shared Auto-stamp (chrome or this toolbar).
  useLayoutEffect(() => {
    if (!onAutoStampSuccessRef) return;
    onAutoStampSuccessRef.current = (result) => {
      const nextSync = parseVariantTokenSync(result.variant.tokenSync);
      const firstFlag = result.flags.find((flag) => flag.tokenIndex != null);
      setSelectedToken(
        firstFlag
          ? { lineIndex: firstFlag.lineIndex, tokenIndex: firstFlag.tokenIndex! }
          : nextSync
            ? firstUnstamped(nextSync)
            : null
      );
    };
    return () => {
      onAutoStampSuccessRef.current = null;
    };
  }, [onAutoStampSuccessRef]);

  const { tokenFlags, lineFlags, flaggedTokens } = useMemo(() => {
    const tokenFlags = new Map<string, TokenSyncFlag[]>();
    const lineFlags = new Map<number, TokenSyncFlag[]>();
    const flaggedTokens: Array<{ lineIndex: number; tokenIndex: number }> = [];
    for (const flag of sync?.flags ?? []) {
      if (flag.tokenIndex == null) {
        lineFlags.set(flag.lineIndex, [...(lineFlags.get(flag.lineIndex) ?? []), flag]);
        continue;
      }
      const key = flagKey(flag.lineIndex, flag.tokenIndex);
      if (!tokenFlags.has(key)) {
        flaggedTokens.push({ lineIndex: flag.lineIndex, tokenIndex: flag.tokenIndex });
      }
      tokenFlags.set(key, [...(tokenFlags.get(key) ?? []), flag]);
    }
    return { tokenFlags, lineFlags, flaggedTokens };
  }, [sync]);

  // Review queue → Token timing: land on the requested spoken line once.
  useLayoutEffect(() => {
    if (focusLineIndex == null || !sync) return;
    if (focusLineIndex < 0 || focusLineIndex >= sync.lines.length) return;
    if (focusAppliedRef.current === focusLineIndex) return;
    focusAppliedRef.current = focusLineIndex;

    const flaggedOnLine = flaggedTokens.find((f) => f.lineIndex === focusLineIndex);
    const tokenIndex = flaggedOnLine?.tokenIndex ?? 0;
    setSelectedToken({ lineIndex: focusLineIndex, tokenIndex });

    // Wait a frame so accordion/layout settle before scrolling.
    requestAnimationFrame(() => {
      lineRefs.current[focusLineIndex]?.scrollIntoView({
        behavior: "smooth",
        block: "center",
      });
    });
  }, [focusLineIndex, sync, flaggedTokens]);

  const unstampedCount = useMemo(() => {
    if (!sync) return 0;
    return sync.lines.reduce(
      (count, line) =>
        count + line.tokens.filter((token) => token.startSeconds == null).length,
      0
    );
  }, [sync]);
  const nextUntimed = useMemo(
    () => (sync ? firstUnstamped(sync) : null),
    [sync]
  );

  const stampTarget = useMemo(() => {
    if (!sync) return null;
    return stampTargetFrom(sync, selectedToken) ?? nextUntimed;
  }, [sync, selectedToken, nextUntimed]);

  const syncRef = useRef(sync);
  const selectedRef = useRef(selectedToken);
  const currentTimeRef = useRef(currentTime);
  const getPlayheadRef = useRef(onGetPlayhead);
  const playbackRateRef = useRef(playbackRate);
  const windowsRef = useRef(windows);
  const statusRef = useRef(status);
  const hasUnsavedRef = useRef(hasUnsavedChanges);
  currentTimeRef.current = currentTime;
  getPlayheadRef.current = onGetPlayhead;
  playbackRateRef.current = playbackRate;
  windowsRef.current = windows;
  statusRef.current = status;
  hasUnsavedRef.current = hasUnsavedChanges;

  function lineStarts() {
    const count = syncRef.current?.lines.length ?? spokenTexts.length;
    return lineStartSecondsForTokenSync(windowsRef.current, count);
  }

  useLayoutEffect(() => {
    syncRef.current = sync;
  }, [sync]);

  // KA-8: first open of the token editor on a take starts its review clock.
  useEffect(() => {
    reportReviewEvent(variant, "opened");
  }, [variant]);
  useLayoutEffect(() => {
    selectedRef.current = selectedToken;
  }, [selectedToken]);

  const stampedCount = useMemo(() => {
    if (!sync) return 0;
    return sync.lines.reduce(
      (count, line) =>
        count + line.tokens.filter((token) => token.startSeconds != null).length,
      0
    );
  }, [sync]);

  const totalCount = useMemo(() => {
    if (!sync) return 0;
    return sync.lines.reduce((count, line) => count + line.tokens.length, 0);
  }, [sync]);

  function commitSync(
    next: VariantTokenSync | null,
    selected: { lineIndex: number; tokenIndex: number } | null
  ) {
    syncRef.current = next;
    selectedRef.current = selected;
    setSelectedToken(selected);
    onPersist(next);
  }

  useEffect(() => {
    if (!sync || hasUnsavedChanges || status === "stale") return;
    const next = applyLineStartToFirstTokens(
      sync,
      lineStartSecondsForTokenSync(windows, sync.lines.length)
    );
    if (next === sync) return;
    commitSync(next, selectedToken ?? firstUnstamped(next));
  }, [sync, windows, hasUnsavedChanges, status, selectedToken]);

  function stamp() {
    const current = syncRef.current;
    if (!current || statusRef.current === "stale" || hasUnsavedRef.current) {
      return;
    }
    const target =
      stampTargetFrom(current, selectedRef.current) ?? firstUnstamped(current);
    if (!target) {
      toast.success("Every token already has a time.");
      return;
    }
    const clipSeconds =
      getPlayheadRef.current?.() ?? currentTimeRef.current;
    const stamped = restampToken(
      current,
      target.lineIndex,
      target.tokenIndex,
      clipSeconds,
      windowsRef.current,
      playbackRateRef.current
    );
    if (stamped === current) return;
    // First hand stamp on a take with no provenance makes it a human take.
    // KA-9: record the build and playback rates behind the hand stamps.
    const rates = new Set(stamped.stampedWith?.playbackRates ?? []);
    rates.add(playbackRateRef.current);
    const next: VariantTokenSync = {
      ...stamped,
      ...(stamped.source == null ? { source: "human" as const } : {}),
      stampedWith: {
        build: STUDIO_BUILD,
        playbackRates: [...rates].sort((a, b) => a - b),
        lastStampedAt: new Date().toISOString(),
      },
    };
    commitSync(next, nextUnstamped(next, target.lineIndex, target.tokenIndex));
  }

  function acceptAsReviewed(current: VariantTokenSync, message: string) {
    commitSync(clearFlagsForReviewed(current), selectedRef.current);
    reportReviewEvent(variant, "reviewed");
    toast.success(message);
  }

  function markReviewed() {
    const current = syncRef.current;
    if (!current || current.source !== "auto" || hasUnsavedRef.current) return;
    acceptAsReviewed(
      current,
      "Marked reviewed. This take left the review queue."
    );
  }

  function jumpToFlagged() {
    if (!sync || flaggedTokens.length === 0) return;
    const at = selectedToken
      ? flaggedTokens.findIndex(
          (f) =>
            f.lineIndex === selectedToken.lineIndex &&
            f.tokenIndex === selectedToken.tokenIndex
        )
      : -1;
    const next = flaggedTokens[(at + 1) % flaggedTokens.length];
    setSelectedToken(next);
    const seconds = sync.lines[next.lineIndex]?.tokens[next.tokenIndex]?.startSeconds;
    if (seconds != null) {
      onPlayFromSeconds?.(Math.max(0, seconds - 1));
    }
  }

  function clearAllTokenFlags() {
    const current = syncRef.current;
    if (!current || hasUnsavedRef.current) return;
    if (!current.flags?.length) return;
    acceptAsReviewed(
      current,
      "Accepted stamps. This take left the review queue."
    );
  }

  function undo() {
    const current = syncRef.current;
    if (!current) return;
    const next = unstampLastToken(current);
    if (next === current) {
      toast.error("Nothing to undo — stamp a token first.");
      return;
    }
    commitSync(next, firstUnstamped(next));
  }

  function clearLine(lineIndex: number) {
    const current = syncRef.current;
    if (!current || hasUnsavedRef.current) return;
    const next = clearLineStamps(
      current,
      lineIndex,
      lineStarts()[lineIndex]
    );
    if (next === current) return;
    commitSync(next, nextUnstamped(next, lineIndex, 0) ?? { lineIndex, tokenIndex: 0 });
  }

  function unflagToken(lineIndex: number, tokenIndex: number) {
    const current = syncRef.current;
    if (!current || hasUnsavedRef.current) return;
    const next = clearFlagsForToken(current, lineIndex, tokenIndex);
    if (next === current) {
      setTokenMenu(null);
      return;
    }
    if (!(next.flags?.length) && next.source === "auto") {
      acceptAsReviewed(
        next,
        "Accepted last flags. This take left the review queue."
      );
    } else {
      commitSync(next, { lineIndex, tokenIndex });
    }
    setTokenMenu(null);
  }

  function clearFromHere(lineIndex: number, tokenIndex: number) {
    const current = syncRef.current;
    if (!current || hasUnsavedRef.current) return;
    const seekSeconds = seekSecondsBeforeToken(
      current,
      lineIndex,
      tokenIndex,
      windowsRef.current
    );
    const next = clearStampsFrom(
      current,
      lineIndex,
      tokenIndex,
      lineStarts()[lineIndex]
    );
    const selected = { lineIndex, tokenIndex };
    if (next !== current) {
      commitSync(next, selected);
    } else {
      selectedRef.current = selected;
      setSelectedToken(selected);
    }
    setTokenMenu(null);
    if (onPlayFromSeconds) {
      onPlayFromSeconds(seekSeconds);
    } else {
      playLine(lineIndex);
    }
  }

  function splitToken(lineIndex: number, tokenIndex: number, offset: number) {
    const current = syncRef.current;
    if (!current || hasUnsavedRef.current) return;
    const next = splitTokenAt(current, lineIndex, tokenIndex, offset, {
      clearFromSplit: true,
      lineStartSeconds: lineStarts()[lineIndex],
    });
    if (next === current) {
      toast.error("Could not split that token.");
      return;
    }
    // Select the new right half (untimed) so stamp flow continues from the cut.
    commitSync(next, { lineIndex, tokenIndex: tokenIndex + 1 });
    setTokenMenu(null);
  }

  function clearAllTimes() {
    const current = syncRef.current;
    if (!current || hasUnsavedRef.current) return;
    if (!window.confirm("Clear every token time on this take? First words keep their line-start times. You restamp the rest.")) {
      return;
    }
    const next = clearAllStamps(current, lineStarts());
    if (next === current) return;
    commitSync(next, firstUnstamped(next));
    toast.success("Times cleared. First words still use the line marks — Stamp from there.");
  }

  function jumpToMissing() {
    const missing = firstUnstamped(syncRef.current);
    if (!missing) return;
    selectedRef.current = missing;
    setSelectedToken(missing);
    playLine(missing.lineIndex);
  }

  function playLine(lineIndex: number) {
    const window = windowsRef.current?.[lineIndex];
    const canPlay = window != null || lineIndex === 0;
    if (!canPlay) return;
    const current = syncRef.current;
    const firstUntimed = current?.lines[lineIndex]?.tokens.findIndex(
      (token) => token.startSeconds == null
    );
    const selected = {
      lineIndex,
      tokenIndex: firstUntimed != null && firstUntimed >= 0 ? firstUntimed : 0,
    };
    selectedRef.current = selected;
    setSelectedToken(selected);
    onPlayLine?.(lineIndex);
  }

  function selectToken(lineIndex: number, tokenIndex: number) {
    const current = syncRef.current;
    if (!current) return;
    const token = current.lines[lineIndex]?.tokens[tokenIndex];
    if (!token) return;
    const selected = { lineIndex, tokenIndex };
    selectedRef.current = selected;
    setSelectedToken(selected);
  }

  function merge(lineIndex: number, tokenIndex: number) {
    const current = syncRef.current;
    if (!current || hasUnsavedRef.current) return;
    commitSync(
      mergeTokenWithNext(current, lineIndex, tokenIndex),
      selectedRef.current
    );
  }

  function applySelection(lineIndex: number, container: HTMLElement) {
    const current = syncRef.current;
    if (!current || hasUnsavedRef.current) return;
    const offsets = selectionOffsetsIn(container);
    if (!offsets) return;
    const next = applyTokenSelection(current, lineIndex, offsets.start, offsets.end);
    window.getSelection()?.removeAllRanges();
    if (!next) return;
    commitSync(next, selectedRef.current);
  }

  const stampRef = useRef(stamp);
  const undoRef = useRef(undo);
  stampRef.current = stamp;
  undoRef.current = undo;

  // Stable handle: always calls through to the latest stamp/undo closures.
  useImperativeHandle(
    actionsRef,
    () => ({
      stamp: () => stampRef.current(),
      undo: () => undoRef.current(),
    }),
    []
  );

  const tokenizeDisabled =
    spokenTexts.length === 0 ||
    hasUnsavedChanges ||
    !contentHash ||
    tokenizeMutation.isPending ||
    !!autoStampControls?.isPending ||
    !!autoStampControls?.jobLive;
  const autoStampDisabled =
    autoStampDisabledProp === true ||
    !autoStampControls ||
    spokenTexts.length === 0 ||
    !!hasUnsavedChanges ||
    !contentHash ||
    tokenizeMutation.isPending;
  const canMarkReviewed =
    !!sync &&
    sync.source === "auto" &&
    status === "complete" &&
    !hasUnsavedChanges;

  const canStamp =
    !!sync && status !== "stale" && !hasUnsavedChanges && !!stampTarget;
  const canUndo = !!sync && !hasUnsavedChanges && stampedCount > 0;

  // The host passes a state setter here, so the identity is stable and this
  // only fires when availability actually flips.
  useEffect(() => {
    onAvailabilityChange?.({ canStamp, canUndo });
  }, [canStamp, canUndo, onAvailabilityChange]);

  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-wrap items-center gap-2">
        <Badge
          variant="outline"
          className={cn(
            status === "complete" &&
              "border-emerald-500/50 text-emerald-600 dark:text-emerald-400",
            status === "stale" &&
              "border-amber-500/50 text-amber-600 dark:text-amber-400",
            (status === "missing" || status === "tokens-only") &&
              "text-muted-foreground"
          )}
        >
          {status === "tokens-only" || status === "complete"
            ? `${stampedCount} / ${totalCount} stamped`
            : STATUS_LABEL[status]}
        </Badge>
        {sync?.source === "auto" && status !== "stale" && (
          <Badge
            variant="outline"
            className="border-amber-500/50 text-amber-600 dark:text-amber-400"
            title={
              sync.alignerVersion
                ? `Stamped automatically by ${sync.alignerVersion}. Review, then Mark reviewed.`
                : "Stamped automatically. Review, then Mark reviewed."
            }
          >
            auto
          </Badge>
        )}
        {sync?.source === "reviewed" && status !== "stale" && (
          <Badge
            variant="outline"
            className="border-emerald-500/50 text-emerald-600 dark:text-emerald-400"
            title="Auto stamps checked by an editor."
          >
            reviewed
          </Badge>
        )}
        {unstampedCount > 0 && (
          <Button
            type="button"
            size="xs"
            variant="outline"
            className="border-rose-500/50 text-rose-700 dark:text-rose-300"
            onClick={jumpToMissing}
          >
            {unstampedCount} missing
            {nextUntimed ? `: ${nextUntimed.text}` : ""}
          </Button>
        )}
        {flaggedTokens.length > 0 && status !== "stale" && (
          <FlaggedCountButton
            count={flaggedTokens.length}
            disabled={!!hasUnsavedChanges}
            onJump={jumpToFlagged}
            onClearAll={clearAllTokenFlags}
          />
        )}
      </div>
      <ol className="list-decimal space-y-0.5 pl-4 text-xs text-muted-foreground">
        <li>
          <span className="font-medium text-foreground">Auto-stamp</span>{" "}
          tokenizes, times every word from the audio, and places line marks
          if the take has none. Listen through, fix anything flagged in amber,
          or right-click / long-press a chip to unflag a stamp that looks right
          (right-click the flagged count to clear all),
          then <span className="font-medium text-foreground">Mark reviewed</span>.
        </li>
        <li>Or by hand: Tokenize splits each line into tap-sized words. The first word of each line is already timed from the line mark.</li>
        <li>Play the take from the waveform below.</li>
        <li>
          Tap <span className="font-medium text-foreground">Mark</span> in the
          player (or the next highlighted word) as that word starts. On a
          keyboard press <span className="font-medium text-foreground">M</span>.
          Timed chips keep a stable layout so the next target does not jump.
        </li>
        <li>
          Tap any other untimed word to make it next. Mark always uses the live
          playhead — tapping a chip does not jump the take.
        </li>
        <li>
          <span className="font-medium text-foreground">Undo mark</span> (or{" "}
          <span className="font-medium text-foreground">Backspace</span>) clears
          the last stamp.{" "}
          <span className="font-medium text-foreground">Clear times</span>{" "}
          resets a line but keeps its first-word line mark.{" "}
          <span className="font-medium text-foreground">Clear all times</span>{" "}
          does the same for the whole take. Right-click (or long-press) a word
          to clear from there and resume audio a couple words earlier, or to
          split a glued token in half / at a chosen character.
          Drag-select text to split or merge tokens.
        </li>
      </ol>
      {tokenMenu && sync && (
        <TokenContextMenu
          x={tokenMenu.x}
          y={tokenMenu.y}
          disabled={!!hasUnsavedChanges}
          flagged={
            (sync.flags ?? []).some(
              (flag) =>
                flag.lineIndex === tokenMenu.lineIndex &&
                flag.tokenIndex === tokenMenu.tokenIndex
            )
          }
          tokenText={
            sync.lines[tokenMenu.lineIndex]?.tokens[tokenMenu.tokenIndex]
              ?.text ?? ""
          }
          onUnflag={() => unflagToken(tokenMenu.lineIndex, tokenMenu.tokenIndex)}
          onClearFromHere={() =>
            clearFromHere(tokenMenu.lineIndex, tokenMenu.tokenIndex)
          }
          onSplitAt={(offset) =>
            splitToken(tokenMenu.lineIndex, tokenMenu.tokenIndex, offset)
          }
          onClose={() => setTokenMenu(null)}
        />
      )}
      {hasUnsavedChanges && (
        <p className="text-xs text-amber-600 dark:text-amber-400">
          Save line edits before tokenizing or timing.
        </p>
      )}
      {status === "stale" && (
        <p className="text-xs text-amber-600 dark:text-amber-400">
          Dialogue text changed — retokenize this take.
        </p>
      )}
      {!usesMarks && spokenTexts.length > 1 && (
        <p className="text-xs text-muted-foreground">
          Line timing is not finished yet — you can still stamp here. Publish
          the lesson to ship these times to the app.
        </p>
      )}
      <div className="sticky top-28 z-10 -mx-1 flex flex-wrap items-center gap-2 bg-background/95 px-1 py-2 backdrop-blur supports-[backdrop-filter]:bg-background/80">
        <Button
          size="sm"
          variant="outline"
          className="min-h-11 touch-manipulation md:min-h-8"
          onClick={() => tokenizeMutation.mutate()}
          disabled={tokenizeDisabled}
        >
          {tokenizeMutation.isPending ? "Tokenizing…" : "Tokenize"}
        </Button>
        {autoStampControls && (
          <AutoStampControls
            state={autoStampControls}
            disabled={autoStampDisabled}
          />
        )}
        {sync?.source === "auto" && (
          <Button
            size="sm"
            variant="outline"
            className="min-h-11 touch-manipulation border-emerald-500/50 md:min-h-8"
            onClick={markReviewed}
            disabled={!canMarkReviewed}
            title={
              canMarkReviewed
                ? "Confirm these auto stamps are checked"
                : "Stamp every word before marking reviewed"
            }
          >
            Mark reviewed
          </Button>
        )}
        <Button
          size="sm"
          variant="outline"
          className="min-h-11 touch-manipulation md:min-h-8"
          onClick={clearAllTimes}
          disabled={!canUndo}
        >
          Clear all times
        </Button>
      </div>
      {sync && status !== "stale" && (
        <div className="flex flex-col gap-2">
          {sync.lines.map((line, lineIndex) => {
            const activeToken = activeTokenIndexForTime(sync, lineIndex, currentTime);
            const missingOnLine = line.tokens.filter(
              (token) => token.startSeconds == null
            ).length;
            const lineHasStamps = missingOnLine < line.tokens.length;
            return (
              <div
                key={`${lineIndex}-${line.text}`}
                ref={(el) => {
                  lineRefs.current[lineIndex] = el;
                }}
                data-line-index={lineIndex}
                className={cn(
                  "flex flex-col gap-1 rounded-md px-1 py-1 transition-colors",
                  focusLineIndex === lineIndex &&
                    selectedToken?.lineIndex === lineIndex &&
                    "bg-primary/5 ring-1 ring-primary/30"
                )}
              >
                <div className="flex items-center gap-2">
                  <button
                    type="button"
                    title={
                      windows?.[lineIndex] || lineIndex === 0
                        ? "Play this line from its start mark"
                        : "Mark line switches first to play from this line"
                    }
                    disabled={!onPlayLine || (!windows?.[lineIndex] && lineIndex !== 0)}
                    onClick={() => playLine(lineIndex)}
                    className="flex size-9 shrink-0 touch-manipulation items-center justify-center text-muted-foreground hover:text-foreground disabled:opacity-30 md:size-auto"
                  >
                    {playingLineIndex === lineIndex ? (
                      <Pause className="size-4 md:size-3.5" />
                    ) : (
                      <Play className="size-4 md:size-3.5" />
                    )}
                  </button>
                  <p className="text-[11px] text-muted-foreground">
                    {spokenLines[lineIndex]?.speaker === "speaker2" ? "B" : "A"}
                  </p>
                  {missingOnLine > 0 && (
                    <span className="text-[10px] font-medium text-rose-600 dark:text-rose-400">
                      {missingOnLine} missing
                    </span>
                  )}
                  {(lineFlags.get(lineIndex) ?? []).map((flag) => (
                    <span
                      key={flag.code}
                      title={flag.detail ?? FLAG_LABEL[flag.code]}
                      className="rounded border border-amber-500/50 px-1 text-[10px] font-medium text-amber-700 dark:text-amber-300"
                    >
                      {FLAG_LABEL[flag.code]}
                    </span>
                  ))}
                  {lineHasStamps && (
                    <Button
                      type="button"
                      size="xs"
                      variant="ghost"
                      className="h-5 px-1.5 text-[10px] text-muted-foreground"
                      onClick={() => clearLine(lineIndex)}
                    >
                      Clear times
                    </Button>
                  )}
                </div>
                <TokenLine
                  lineText={line.text}
                  tokens={line.tokens}
                  lineIndex={lineIndex}
                  tokenFlags={tokenFlags}
                  activeToken={activeToken}
                  nextTokenIndex={
                    stampTarget?.lineIndex === lineIndex
                      ? stampTarget.tokenIndex
                      : null
                  }
                  onMouseUp={(container, event) => {
                    if (event.button !== 0) return;
                    const offsets = selectionOffsetsIn(container);
                    if (offsets) {
                      applySelection(lineIndex, container);
                      return;
                    }
                    const tokenEl = (event.target as HTMLElement | null)?.closest(
                      "[data-token-index]"
                    );
                    if (!(tokenEl instanceof HTMLElement)) return;
                    const tokenIndex = Number(tokenEl.dataset.tokenIndex);
                    if (!Number.isInteger(tokenIndex)) return;
                    const isNextTarget =
                      stampTarget?.lineIndex === lineIndex &&
                      stampTarget.tokenIndex === tokenIndex;
                    if (isNextTarget) {
                      stamp();
                      return;
                    }
                    selectToken(lineIndex, tokenIndex);
                  }}
                  onTokenMenu={(tokenIndex, x, y) => {
                    setTokenMenu({ lineIndex, tokenIndex, x, y });
                  }}
                  onMerge={(tokenIndex) => merge(lineIndex, tokenIndex)}
                />
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}

function TokenLine({
  lineText,
  tokens,
  lineIndex,
  tokenFlags,
  activeToken,
  nextTokenIndex,
  onMouseUp,
  onTokenMenu,
  onMerge,
}: {
  lineText: string;
  tokens: VariantTokenSync["lines"][number]["tokens"];
  lineIndex: number;
  tokenFlags: Map<string, TokenSyncFlag[]>;
  activeToken: number | null;
  nextTokenIndex: number | null;
  onMouseUp: (container: HTMLElement, event: MouseEvent<HTMLElement>) => void;
  onTokenMenu: (tokenIndex: number, x: number, y: number) => void;
  onMerge: (tokenIndex: number) => void;
}) {
  const pieces = lineDisplayPieces(lineText, tokens);

  if (!pieces) {
    return (
      <div
        className="flex flex-wrap gap-1"
        onMouseUp={(event) => onMouseUp(event.currentTarget, event)}
      >
        {tokens.map((token, tokenIndex) => (
          <TokenChip
            key={`${tokenIndex}-${token.text}`}
            text={token.text}
            startSeconds={token.startSeconds}
            tokenIndex={tokenIndex}
            flags={tokenFlags.get(flagKey(lineIndex, tokenIndex))}
            isNext={nextTokenIndex === tokenIndex}
            isPlaying={activeToken === tokenIndex && token.startSeconds != null}
            onOpenMenu={(x, y) => onTokenMenu(tokenIndex, x, y)}
          />
        ))}
      </div>
    );
  }

  return (
    <div
      className="select-text text-xs leading-relaxed"
      onMouseUp={(event) => {
        if ((event.target as HTMLElement | null)?.closest("button")) return;
        onMouseUp(event.currentTarget, event);
      }}
    >
      {pieces.map((piece) => {
        if (piece.type === "gap") {
          return (
            <span
              key={`gap-${piece.start}`}
              data-token-gap=""
              className="whitespace-pre text-muted-foreground"
            >
              {piece.text}
            </span>
          );
        }
        const { range } = piece;
        return (
          <span key={`tok-${range.tokenIndex}`}>
            <TokenChip
              text={range.text}
              startSeconds={range.startSeconds}
              tokenIndex={range.tokenIndex}
              flags={tokenFlags.get(flagKey(lineIndex, range.tokenIndex))}
              isNext={nextTokenIndex === range.tokenIndex}
              isPlaying={
                activeToken === range.tokenIndex && range.startSeconds != null
              }
              onOpenMenu={(x, y) => onTokenMenu(range.tokenIndex, x, y)}
            />
            {range.tokenIndex < tokens.length - 1 && (
              <button
                type="button"
                title="Merge with next"
                onClick={() => onMerge(range.tokenIndex)}
                className="inline-block w-3 select-none align-middle text-[10px] text-muted-foreground before:content-['+'] hover:text-foreground"
              />
            )}
          </span>
        );
      })}
    </div>
  );
}

/** Fixed mono width so stamped times never reflow neighboring chips. */
const STAMP_SLOT = "0.00s";

function TokenChip({
  text,
  startSeconds,
  tokenIndex,
  flags,
  isNext,
  isPlaying,
  onOpenMenu,
}: {
  text: string;
  startSeconds: number | null;
  tokenIndex: number;
  flags?: TokenSyncFlag[];
  isNext: boolean;
  isPlaying: boolean;
  onOpenMenu: (x: number, y: number) => void;
}) {
  const untimed = startSeconds == null;
  const flagged = !!flags && flags.length > 0;
  const flagText = flagged
    ? flags.map((flag) => flag.detail ?? FLAG_LABEL[flag.code]).join("; ")
    : null;
  const longPressRef = useRef<number | null>(null);
  const suppressClickRef = useRef(false);

  function clearLongPress() {
    if (longPressRef.current != null) {
      window.clearTimeout(longPressRef.current);
      longPressRef.current = null;
    }
  }

  function openMenuAt(clientX: number, clientY: number) {
    onOpenMenu(clientX, clientY);
  }

  function onContextMenu(event: MouseEvent<HTMLSpanElement>) {
    event.preventDefault();
    event.stopPropagation();
    openMenuAt(event.clientX, event.clientY);
  }

  function onPointerDown(event: ReactPointerEvent<HTMLSpanElement>) {
    if (event.pointerType === "mouse" && event.button !== 0) return;
    clearLongPress();
    longPressRef.current = window.setTimeout(() => {
      longPressRef.current = null;
      suppressClickRef.current = true;
      openMenuAt(event.clientX, event.clientY);
    }, LONG_PRESS_MS);
  }

  function onPointerUp() {
    clearLongPress();
  }

  function onPointerCancel() {
    clearLongPress();
  }

  function onPointerMove(event: ReactPointerEvent<HTMLSpanElement>) {
    // Cancel long-press if the finger drifts (scroll / swipe).
    if (longPressRef.current == null) return;
    if (Math.abs(event.movementX) + Math.abs(event.movementY) > 6) {
      clearLongPress();
    }
  }

  useEffect(() => () => clearLongPress(), []);

  return (
    <span
      data-token-index={tokenIndex}
      title={
        (flagText ? `Flagged: ${flagText}. ` : "") +
        (untimed
          ? isNext
            ? "Tap to stamp this word at the playhead. Right-click or long-press to clear from here."
            : "Tap to make this the next word to stamp. Right-click or long-press to clear from here."
          : `Stamped at ${formatStamp(startSeconds)}. Right-click or long-press to clear from here.`)
      }
      onContextMenu={onContextMenu}
      onPointerDown={onPointerDown}
      onPointerUp={onPointerUp}
      onPointerCancel={onPointerCancel}
      onPointerMove={onPointerMove}
      onMouseUpCapture={(event) => {
        if (!suppressClickRef.current) return;
        suppressClickRef.current = false;
        event.preventDefault();
        event.stopPropagation();
      }}
      onClickCapture={(event) => {
        if (!suppressClickRef.current) return;
        suppressClickRef.current = false;
        event.preventDefault();
        event.stopPropagation();
      }}
      className={cn(
        "mx-px inline-block cursor-pointer touch-manipulation whitespace-nowrap rounded-md border px-1.5 py-1 align-middle md:px-1 md:py-px",
        untimed && "border-dashed border-rose-400 bg-rose-500/15",
        !untimed && "border-sky-500/30 bg-sky-500/10",
        flagged && "border-amber-500/70 bg-amber-500/15",
        isNext && untimed && "border-solid ring-2 ring-rose-400",
        isNext && !untimed && "ring-2 ring-amber-400",
        isPlaying && !untimed && "border-primary bg-primary/15"
      )}
    >
      <span data-token-chars="">{text}</span>
      <span
        aria-hidden={untimed}
        className={cn(
          "ml-1 inline-block w-[6ch] select-none overflow-hidden font-mono text-[9px] tabular-nums text-muted-foreground",
          untimed && "opacity-0"
        )}
      >
        {untimed ? STAMP_SLOT : formatStamp(startSeconds)}
      </span>
    </span>
  );
}

function FlaggedCountButton({
  count,
  disabled,
  onJump,
  onClearAll,
}: {
  count: number;
  disabled: boolean;
  onJump: () => void;
  onClearAll: () => void;
}) {
  const longPressRef = useRef<number | null>(null);
  const suppressClickRef = useRef(false);

  function clearLongPress() {
    if (longPressRef.current != null) {
      window.clearTimeout(longPressRef.current);
      longPressRef.current = null;
    }
  }

  function clearAll(event: { preventDefault: () => void; stopPropagation: () => void }) {
    event.preventDefault();
    event.stopPropagation();
    if (disabled) return;
    onClearAll();
  }

  useEffect(() => () => clearLongPress(), []);

  return (
    <Button
      type="button"
      size="xs"
      variant="outline"
      className="border-amber-500/50 text-amber-700 dark:text-amber-300"
      disabled={disabled}
      onClick={() => {
        if (suppressClickRef.current) {
          suppressClickRef.current = false;
          return;
        }
        onJump();
      }}
      onContextMenu={clearAll}
      onPointerDown={(event) => {
        if (event.pointerType === "mouse" && event.button !== 0) return;
        clearLongPress();
        longPressRef.current = window.setTimeout(() => {
          longPressRef.current = null;
          suppressClickRef.current = true;
          if (!disabled) onClearAll();
        }, LONG_PRESS_MS);
      }}
      onPointerUp={clearLongPress}
      onPointerCancel={clearLongPress}
      onPointerMove={(event) => {
        if (longPressRef.current == null) return;
        if (Math.abs(event.movementX) + Math.abs(event.movementY) > 6) {
          clearLongPress();
        }
      }}
      title="Click to cycle flagged stamps. Right-click or long-press to accept all stamps and leave the review queue."
    >
      {count} flagged
    </Button>
  );
}

function TokenContextMenu({
  x,
  y,
  disabled,
  flagged,
  tokenText,
  onUnflag,
  onClearFromHere,
  onSplitAt,
  onClose,
}: {
  x: number;
  y: number;
  disabled: boolean;
  flagged: boolean;
  tokenText: string;
  onUnflag: () => void;
  onClearFromHere: () => void;
  onSplitAt: (offset: number) => void;
  onClose: () => void;
}) {
  const menuRef = useRef<HTMLDivElement>(null);
  const [mode, setMode] = useState<"menu" | "split">("menu");
  const canSplit = graphemeSplitOffsets(tokenText).length > 0;
  const halfOffset = midpointSplitOffset(tokenText);

  useEffect(() => {
    function onKey(event: KeyboardEvent) {
      if (event.key === "Escape") {
        if (mode === "split") {
          setMode("menu");
          return;
        }
        onClose();
      }
    }
    function onPointer(event: globalThis.PointerEvent) {
      if (!menuRef.current?.contains(event.target as Node)) {
        onClose();
      }
    }
    window.addEventListener("keydown", onKey);
    window.addEventListener("pointerdown", onPointer, true);
    return () => {
      window.removeEventListener("keydown", onKey);
      window.removeEventListener("pointerdown", onPointer, true);
    };
  }, [onClose, mode]);

  const left = Math.min(
    x,
    typeof window !== "undefined" ? window.innerWidth - 220 : x
  );
  const top = Math.min(
    y,
    typeof window !== "undefined" ? window.innerHeight - 160 : y
  );

  return (
    <div
      ref={menuRef}
      role="menu"
      className="fixed z-50 min-w-[11rem] rounded-md border bg-popover p-1 text-popover-foreground shadow-md"
      style={{ left, top }}
    >
      {mode === "menu" ? (
        <>
          {flagged && (
            <button
              type="button"
              role="menuitem"
              disabled={disabled}
              className="flex w-full rounded-sm px-2 py-1.5 text-left text-sm hover:bg-accent disabled:opacity-50"
              onClick={onUnflag}
            >
              Unflag
            </button>
          )}
          <button
            type="button"
            role="menuitem"
            disabled={disabled}
            className="flex w-full rounded-sm px-2 py-1.5 text-left text-sm hover:bg-accent disabled:opacity-50"
            onClick={onClearFromHere}
          >
            Clear from here
          </button>
          <button
            type="button"
            role="menuitem"
            disabled={disabled || halfOffset == null}
            className="flex w-full rounded-sm px-2 py-1.5 text-left text-sm hover:bg-accent disabled:opacity-50"
            onClick={() => {
              if (halfOffset == null) return;
              onSplitAt(halfOffset);
            }}
          >
            Split in half
          </button>
          <button
            type="button"
            role="menuitem"
            disabled={disabled || !canSplit}
            className="flex w-full rounded-sm px-2 py-1.5 text-left text-sm hover:bg-accent disabled:opacity-50"
            onClick={() => setMode("split")}
          >
            Split…
          </button>
        </>
      ) : (
        <div className="flex flex-col gap-1.5 px-1 py-1">
          <p className="text-[11px] text-muted-foreground">
            Tap between characters to split
          </p>
          <div className="flex flex-wrap items-center gap-0.5 font-mono text-sm">
            {[...tokenText].map((char, index) => {
              const offset = [...tokenText].slice(0, index + 1).join("").length;
              const isLast = index === [...tokenText].length - 1;
              return (
                <span key={`${offset}-${char}`} className="inline-flex items-center">
                  <span className="rounded px-0.5">{char}</span>
                  {!isLast && (
                    <button
                      type="button"
                      title={`Split after “${tokenText.slice(0, offset)}”`}
                      className="mx-px h-5 w-2 rounded-sm bg-border/80 hover:bg-primary hover:text-primary-foreground"
                      onClick={() => onSplitAt(offset)}
                    />
                  )}
                </span>
              );
            })}
          </div>
          <button
            type="button"
            className="self-start rounded-sm px-2 py-1 text-xs text-muted-foreground hover:bg-accent hover:text-foreground"
            onClick={() => setMode("menu")}
          >
            Back
          </button>
        </div>
      )}
    </div>
  );
}

function graphemeSplitOffsets(text: string): number[] {
  const ends: number[] = [];
  if (typeof Intl !== "undefined" && "Segmenter" in Intl) {
    const segmenter = new Intl.Segmenter(undefined, { granularity: "grapheme" });
    let offset = 0;
    const clusters = [...segmenter.segment(text)].map((part) => part.segment);
    for (let i = 0; i < clusters.length - 1; i++) {
      offset += clusters[i]!.length;
      ends.push(offset);
    }
    return ends;
  }
  let i = 0;
  while (i < text.length) {
    const codePoint = text.codePointAt(i);
    if (codePoint == null) break;
    i += String.fromCodePoint(codePoint).length;
    if (i < text.length) ends.push(i);
  }
  return ends;
}


function stampTargetFrom(
  sync: VariantTokenSync,
  selected: { lineIndex: number; tokenIndex: number } | null
): { lineIndex: number; tokenIndex: number; text: string } | null {
  if (!selected) return null;
  const token = sync.lines[selected.lineIndex]?.tokens[selected.tokenIndex];
  if (!token) return null;
  if (token.startSeconds != null) {
    return firstUnstamped(sync);
  }
  return {
    lineIndex: selected.lineIndex,
    tokenIndex: selected.tokenIndex,
    text: token.text,
  };
}

function firstUnstamped(
  sync: VariantTokenSync | null
): { lineIndex: number; tokenIndex: number; text: string } | null {
  if (!sync) return null;
  for (let lineIndex = 0; lineIndex < sync.lines.length; lineIndex++) {
    const line = sync.lines[lineIndex];
    for (let tokenIndex = 0; tokenIndex < line.tokens.length; tokenIndex++) {
      if (line.tokens[tokenIndex].startSeconds == null) {
        return {
          lineIndex,
          tokenIndex,
          text: line.tokens[tokenIndex].text,
        };
      }
    }
  }
  return null;
}

function nextUnstamped(
  sync: VariantTokenSync,
  lineIndex: number,
  tokenIndex: number
): { lineIndex: number; tokenIndex: number } | null {
  for (let li = lineIndex; li < sync.lines.length; li++) {
    const start = li === lineIndex ? tokenIndex + 1 : 0;
    const line = sync.lines[li];
    for (let ti = start; ti < line.tokens.length; ti++) {
      if (line.tokens[ti].startSeconds == null) {
        return { lineIndex: li, tokenIndex: ti };
      }
    }
  }
  return firstUnstamped(sync);
}

function selectionOffsetsIn(
  container: HTMLElement
): { start: number; end: number } | null {
  const selection = window.getSelection();
  if (!selection || selection.rangeCount === 0 || selection.isCollapsed) {
    return null;
  }
  if (
    !container.contains(selection.anchorNode) ||
    !container.contains(selection.focusNode)
  ) {
    return null;
  }
  const range = selection.getRangeAt(0);
  const parts = [
    ...container.querySelectorAll("[data-token-chars], [data-token-gap]"),
  ];
  const start = offsetInTokenLine(parts, range.startContainer, range.startOffset);
  const end = offsetInTokenLine(parts, range.endContainer, range.endOffset);
  if (start == null || end == null) return null;
  const from = Math.min(start, end);
  const to = Math.max(start, end);
  if (to <= from) return null;
  return { start: from, end: to };
}

function offsetInTokenLine(
  parts: Element[],
  node: Node,
  nodeOffset: number
): number | null {
  let pos = 0;
  for (const part of parts) {
    const text = part.textContent ?? "";
    if (part === node || part.contains(node)) {
      try {
        const inner = document.createRange();
        inner.selectNodeContents(part);
        inner.setEnd(node, nodeOffset);
        return pos + inner.toString().length;
      } catch {
        return pos;
      }
    }
    const position = node.compareDocumentPosition(part);
    if (position & Node.DOCUMENT_POSITION_FOLLOWING) {
      return pos;
    }
    pos += text.length;
  }
  return pos;
}
