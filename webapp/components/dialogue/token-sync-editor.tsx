"use client";

import {
  useEffect,
  useImperativeHandle,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
  type MouseEvent,
  type Ref,
} from "react";
import { useMutation } from "@tanstack/react-query";
import { toast } from "sonner";
import { Play, Pause } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { dialogueApi } from "@/lib/dialogue/client";
import type { Variant } from "@/lib/tts/client";
import type { VariantTokenSync } from "@/lib/dialogue/types";
import { cn } from "@/lib/utils";
import {
  activeTokenIndexForTime,
  applyTokenSelection,
  applyLineStartToFirstTokens,
  clearAllStamps,
  clearLineStamps,
  lineDisplayPieces,
  lineStartSecondsForTokenSync,
  mergeTokenWithNext,
  parseVariantTokenSync,
  restampToken,
  spokenLineWindows,
  tokenSyncFromSurfaces,
  tokenSyncStatus,
  unstampLastToken,
  type TokenSyncStatus,
} from "@/lib/dialogue/token-sync";

const STATUS_LABEL: Record<TokenSyncStatus, string> = {
  missing: "not started",
  stale: "stale",
  "tokens-only": "stamping",
  complete: "complete",
};

function formatStamp(seconds: number): string {
  return `${seconds.toFixed(2)}s`;
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
  actionsRef,
  onAvailabilityChange,
  onPersist,
  onGetPlayhead,
  onPlayLine,
  playingLineIndex,
}: {
  variant: Variant;
  spokenLines: Array<{ speaker: string; text: string }>;
  currentTime: number;
  duration: number;
  usesMarks: boolean;
  currentContentHash?: string;
  hasUnsavedChanges?: boolean;
  actionsRef?: Ref<TokenSyncActions | null>;
  onAvailabilityChange?: (state: TokenSyncAvailability) => void;
  onPersist: (tokenSync: VariantTokenSync | null) => void;
  onGetPlayhead?: () => number;
  onPlayLine?: (lineIndex: number) => void;
  playingLineIndex?: number | null;
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
  const windowsRef = useRef(windows);
  const statusRef = useRef(status);
  const hasUnsavedRef = useRef(hasUnsavedChanges);
  currentTimeRef.current = currentTime;
  getPlayheadRef.current = onGetPlayhead;
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
    const next = restampToken(
      current,
      target.lineIndex,
      target.tokenIndex,
      clipSeconds,
      windowsRef.current
    );
    commitSync(next, nextUnstamped(next, target.lineIndex, target.tokenIndex));
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
    tokenizeMutation.isPending;

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
      </div>
      <ol className="list-decimal space-y-0.5 pl-4 text-xs text-muted-foreground">
        <li>Tokenize splits each line into tap-sized words. The first word of each line is already timed from the line mark.</li>
        <li>Play the take from the waveform below.</li>
        <li>
          Tap <span className="font-medium text-foreground">Mark</span> in the
          player (or the next highlighted word) as that word starts. On a
          keyboard press <span className="font-medium text-foreground">M</span>.
          Filled chips show their time.
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
          does the same for the whole take. Drag-select text to split or merge
          tokens.
        </li>
      </ol>
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
              <div key={`${lineIndex}-${line.text}`} className="flex flex-col gap-1">
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
                  activeToken={activeToken}
                  nextTokenIndex={
                    stampTarget?.lineIndex === lineIndex
                      ? stampTarget.tokenIndex
                      : null
                  }
                  onMouseUp={(container, event) => {
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
  activeToken,
  nextTokenIndex,
  onMouseUp,
  onMerge,
}: {
  lineText: string;
  tokens: VariantTokenSync["lines"][number]["tokens"];
  activeToken: number | null;
  nextTokenIndex: number | null;
  onMouseUp: (container: HTMLElement, event: MouseEvent<HTMLElement>) => void;
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
            isNext={nextTokenIndex === tokenIndex}
            isPlaying={activeToken === tokenIndex && token.startSeconds != null}
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
              isNext={nextTokenIndex === range.tokenIndex}
              isPlaying={
                activeToken === range.tokenIndex && range.startSeconds != null
              }
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

function TokenChip({
  text,
  startSeconds,
  tokenIndex,
  isNext,
  isPlaying,
}: {
  text: string;
  startSeconds: number | null;
  tokenIndex: number;
  isNext: boolean;
  isPlaying: boolean;
}) {
  const untimed = startSeconds == null;
  return (
    <span
      data-token-index={tokenIndex}
      title={
        untimed
          ? isNext
            ? "Tap to stamp this word at the playhead"
            : "Tap to make this the next word to stamp"
          : `Stamped at ${formatStamp(startSeconds)}. Stamp times the next untimed word from the playhead.`
      }
      className={cn(
        "mx-px inline-block cursor-pointer touch-manipulation whitespace-nowrap rounded-md border px-1.5 py-1 align-middle md:px-1 md:py-px",
        untimed && "border-dashed border-rose-400 bg-rose-500/15",
        !untimed && "border-sky-500/30 bg-sky-500/10",
        isNext && untimed && "border-solid ring-2 ring-rose-400",
        isNext && !untimed && "ring-2 ring-amber-400",
        isPlaying && !untimed && "border-primary bg-primary/15"
      )}
    >
      <span data-token-chars="">{text}</span>
      {!untimed && (
        <span className="ml-1 select-none font-mono text-[9px] text-muted-foreground">
          {formatStamp(startSeconds)}
        </span>
      )}
    </span>
  );
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
