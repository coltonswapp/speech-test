"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { useMutation } from "@tanstack/react-query";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import {
  formatAutoStampDuration,
  type AutoStampResult,
} from "@/lib/tts/client";
import { cn } from "@/lib/utils";

export type AutoStampControlsState = {
  run: (options?: { force?: boolean }) => void;
  abort: () => void;
  isPending: boolean;
  isAborting: boolean;
  /** Background generate→align job is live and Abort is wired. */
  canAbort: boolean;
  /** True while a background generate→align job is live on this take. */
  jobLive: boolean;
  stampElapsedMs: number;
  lastStampDurationMs: number | null;
};

/**
 * Shared Auto-stamp / Abort / duration state for the Audio chrome and Token
 * timing toolbar so both surfaces stay in sync.
 */
export function useAutoStampControls(params: {
  onAutoStamp: (options: { force?: boolean }) => Promise<AutoStampResult>;
  onAbort?: () => Promise<unknown>;
  jobLive?: boolean;
  /** Optional side effect after a successful stamp (e.g. jump to first flag). */
  onSuccess?: (result: AutoStampResult) => void;
}): AutoStampControlsState {
  const [stampElapsedMs, setStampElapsedMs] = useState(0);
  const [lastStampDurationMs, setLastStampDurationMs] = useState<number | null>(
    null
  );
  const stampStartedAtRef = useRef<number | null>(null);
  const stampElapsedMsRef = useRef(0);
  const onSuccessRef = useRef(params.onSuccess);
  useEffect(() => {
    onSuccessRef.current = params.onSuccess;
  }, [params.onSuccess]);

  const mutation = useMutation({
    mutationFn: async (options: { force?: boolean }) => {
      const started = performance.now();
      stampStartedAtRef.current = started;
      stampElapsedMsRef.current = 0;
      setStampElapsedMs(0);
      try {
        return await params.onAutoStamp(options);
      } finally {
        if (stampStartedAtRef.current != null) {
          stampElapsedMsRef.current = performance.now() - stampStartedAtRef.current;
          stampStartedAtRef.current = null;
        }
      }
    },
    onSuccess: (result) => {
      setLastStampDurationMs(stampElapsedMsRef.current);
      toast.success(result.summary);
      onSuccessRef.current?.(result);
    },
    onError: (error, options) => {
      setLastStampDurationMs(stampElapsedMsRef.current);
      const message = error instanceof Error ? error.message : String(error);
      if (!options.force && /human stamps|line marks but needs/.test(message)) {
        toast.warning(message, {
          duration: 10000,
          action: {
            label: "Replace",
            onClick: () => mutation.mutate({ force: true }),
          },
        });
        return;
      }
      toast.error(message);
    },
  });

  const abortMutation = useMutation({
    mutationFn: async () => {
      if (!params.onAbort) {
        throw new Error("Abort is not available here.");
      }
      return params.onAbort();
    },
    onSuccess: () => {
      toast.success("Auto-stamp aborted.");
    },
    onError: (error) =>
      toast.error(error instanceof Error ? error.message : String(error)),
  });

  useEffect(() => {
    if (!mutation.isPending) return;
    const id = window.setInterval(() => {
      const started = stampStartedAtRef.current;
      if (started != null) {
        const ms = performance.now() - started;
        stampElapsedMsRef.current = ms;
        setStampElapsedMs(ms);
      }
    }, 200);
    return () => window.clearInterval(id);
  }, [mutation.isPending]);

  const run = useCallback(
    (options?: { force?: boolean }) => mutation.mutate(options ?? {}),
    [mutation]
  );
  const abort = useCallback(() => abortMutation.mutate(), [abortMutation]);

  const jobLive = params.jobLive === true;

  return {
    run,
    abort,
    isPending: mutation.isPending,
    isAborting: abortMutation.isPending,
    canAbort: jobLive && typeof params.onAbort === "function",
    jobLive,
    stampElapsedMs,
    lastStampDurationMs,
  };
}

export function AutoStampControls({
  state,
  disabled,
  className,
  /** Phone Timing chrome: single-row denser buttons. */
  compact = false,
}: {
  state: AutoStampControlsState;
  disabled?: boolean;
  className?: string;
  compact?: boolean;
}) {
  const aligning = state.isPending || state.jobLive;
  return (
    <div
      className={cn(
        "flex items-center gap-1.5 md:gap-2",
        compact ? "flex-nowrap" : "flex-wrap",
        className
      )}
    >
      <Button
        type="button"
        size="sm"
        variant="outline"
        className={cn(
          "touch-manipulation border-amber-500/50",
          compact ? "min-h-9 shrink-0" : "min-h-11 md:min-h-8"
        )}
        onClick={() => state.run({})}
        disabled={disabled || aligning}
        title="Time every word from the audio with the aligner"
      >
        {aligning ? "Aligning…" : "Auto-stamp"}
      </Button>
      {state.canAbort && (
        <Button
          type="button"
          size="sm"
          variant="outline"
          className={cn(
            "touch-manipulation",
            compact ? "min-h-9 shrink-0" : "min-h-11 md:min-h-8"
          )}
          disabled={state.isAborting}
          onClick={() => state.abort()}
          title="Cancel tokenize/align so this take does not write stamps"
        >
          {state.isAborting ? "Aborting…" : "Abort"}
        </Button>
      )}
      {state.isPending && (
        <span className="shrink-0 text-xs tabular-nums text-muted-foreground">
          {formatAutoStampDuration(state.stampElapsedMs, { live: true })}
        </span>
      )}
      {!state.isPending && state.lastStampDurationMs != null && (
        <span className="shrink-0 text-xs tabular-nums text-muted-foreground">
          {formatAutoStampDuration(state.lastStampDurationMs)}
        </span>
      )}
    </div>
  );
}
