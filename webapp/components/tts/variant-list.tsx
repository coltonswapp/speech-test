"use client";

import { useEffect, useMemo, useState, type ReactNode } from "react";
import { useSearchParams } from "next/navigation";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { MoreVertical } from "lucide-react";
import { Card, CardAction, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Accordion,
  AccordionItem,
  AccordionTrigger,
  AccordionPanel,
} from "@/components/ui/accordion";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuTrigger,
  DropdownMenuContent,
  DropdownMenuItem,
} from "@/components/ui/dropdown-menu";
import {
  autoStampElapsedMs,
  autoStampInProgress,
  formatAutoStampDuration,
  ttsApi,
  type AutoStampJob,
  type Variant,
} from "@/lib/tts/client";
import { WaveformEditor } from "@/components/tts/waveform-editor";
import type { EditableDialogueLine } from "@/components/tts/dialogue-line-editor";
import type { AmbienceMixContext } from "@/components/tts/ambience-mix-tab";
import { cn } from "@/lib/utils";

function useNowMs(active: boolean, intervalMs = 500): number {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    if (!active) return;
    const id = window.setInterval(() => setNow(Date.now()), intervalMs);
    return () => window.clearInterval(id);
  }, [active, intervalMs]);
  return now;
}

function AutoStampJobBadge({
  job,
  nowMs,
}: {
  job: AutoStampJob;
  nowMs: number;
}) {
  const ms = autoStampElapsedMs(job, nowMs);
  if (job.status === "queued" || job.status === "running") {
    return (
      <Badge
        variant="outline"
        className="animate-pulse border-amber-500/50 text-amber-600 dark:text-amber-400"
        title="Tokenizing and aligning this take in the background"
      >
        Auto-stamping {formatAutoStampDuration(ms, { live: true })}
      </Badge>
    );
  }
  if (job.status === "error") {
    return (
      <Badge
        variant="outline"
        className="border-rose-500/50 text-rose-600 dark:text-rose-400"
        title={job.message ?? "Auto-stamp failed"}
      >
        Auto-stamp failed · {formatAutoStampDuration(ms)}
      </Badge>
    );
  }
  if (job.status === "cancelled") {
    return (
      <Badge
        variant="outline"
        className="text-muted-foreground"
        title="Auto-stamp was aborted"
      >
        Aborted · {formatAutoStampDuration(ms)}
      </Badge>
    );
  }
  if (job.status === "done") {
    return (
      <Badge
        variant="outline"
        className="border-emerald-500/50 text-emerald-600 dark:text-emerald-400"
        title="Background auto-stamp finished"
      >
        Stamped · {formatAutoStampDuration(ms)}
      </Badge>
    );
  }
  return null;
}

export function VariantList({
  projectId,
  dialogueLines,
  currentContentHash,
  selectedVariantId,
  hasUnsavedChanges,
  headerActions,
  emptyHint,
  ambience,
}: {
  projectId: string;
  dialogueLines?: EditableDialogueLine[];
  /** When set, takes whose contentHash differs are badged as stale. */
  currentContentHash?: string;
  /** When set, enables explicit take selection and badges off this id instead of isSelected. */
  selectedVariantId?: string | null;
  hasUnsavedChanges?: boolean;
  /** Optional actions rendered in the Takes card header (e.g. Generate take). */
  headerActions?: ReactNode;
  /** Empty-state copy when there are no takes yet. */
  emptyHint?: string;
  /** Scene-level ambience mix; shown as an Ambience tab on each take. */
  ambience?: AmbienceMixContext;
}) {
  const queryClient = useQueryClient();
  // Review queue deep-links a specific take (?take=<variantId>), optional line
  // (?line=N) and Token timing tab (?timing=tokens).
  const searchParams = useSearchParams();
  const requestedTakeId = searchParams.get("take");
  const requestedLineRaw = searchParams.get("line");
  const requestedLineIndex = (() => {
    if (requestedLineRaw == null || requestedLineRaw === "") return null;
    const n = Number.parseInt(requestedLineRaw, 10);
    return Number.isFinite(n) && n >= 0 ? n : null;
  })();
  const requestedTiming = searchParams.get("timing");
  const focusTimingMode =
    requestedTiming === "tokens" || requestedTiming === "lines"
      ? requestedTiming
      : requestedLineIndex != null
        ? ("tokens" as const)
        : null;
  const { data, isLoading } = useQuery({
    queryKey: ["tts-variants", projectId],
    queryFn: () => ttsApi.listVariants(projectId),
    // Poll while a fresh take is being tokenized/aligned in the background.
    refetchInterval: (query) =>
      query.state.data?.variants.some(autoStampInProgress) ? 3000 : false,
  });

  const [selectionMode, setSelectionMode] = useState(false);
  const [selectedIds, setSelectedIds] = useState<Set<string>>(() => new Set());

  const variants = useMemo(() => data?.variants ?? [], [data?.variants]);
  const anyJobLive = variants.some(autoStampInProgress);
  const nowMs = useNowMs(anyJobLive);

  const selectMutation = useMutation({
    mutationFn: (variantId: string) =>
      ttsApi.selectVariant(projectId, variantId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["tts-project", projectId] });
      queryClient.invalidateQueries({ queryKey: ["tts-projects"] });
      queryClient.invalidateQueries({ queryKey: ["scenario-audio"] });
      toast.success("Take selected.");
    },
    onError: (error) => toast.error(error.message),
  });

  function invalidateAfterDelete() {
    queryClient.invalidateQueries({ queryKey: ["tts-variants", projectId] });
    queryClient.invalidateQueries({ queryKey: ["tts-project", projectId] });
    queryClient.invalidateQueries({ queryKey: ["tts-projects"] });
    queryClient.invalidateQueries({ queryKey: ["scenario-audio"] });
  }

  const deleteMutation = useMutation({
    mutationFn: (variantId: string) =>
      ttsApi.deleteVariant(projectId, variantId),
    onSuccess: () => {
      invalidateAfterDelete();
      toast.success("Take deleted.");
    },
    onError: (error) => toast.error(error.message),
  });

  const bulkDeleteMutation = useMutation({
    mutationFn: async (variantIds: string[]) => {
      for (const variantId of variantIds) {
        await ttsApi.deleteVariant(projectId, variantId);
      }
      return variantIds.length;
    },
    onSuccess: (count) => {
      invalidateAfterDelete();
      setSelectedIds(new Set());
      setSelectionMode(false);
      toast.success(count === 1 ? "Take deleted." : `${count} takes deleted.`);
    },
    onError: (error) => toast.error(error.message),
  });

  const regenerateMutation = useMutation({
    mutationFn: (variant: Variant) => {
      const isConversation = variant.voice.includes("/");
      if (isConversation) {
        const [speaker1Voice, speaker2Voice] = variant.voice.split("/");
        return ttsApi.generate(projectId, { speaker1Voice, speaker2Voice });
      }
      return ttsApi.generate(projectId, {
        voice: variant.voice,
        provider: variant.provider,
      });
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["tts-variants", projectId] });
      queryClient.invalidateQueries({ queryKey: ["tts-projects"] });
      toast.success("New take generated with the same settings.");
    },
    onError: (error) => toast.error(error.message),
  });

  const ignoreMutation = useMutation({
    mutationFn: (variantId: string) =>
      ttsApi.acceptScript(projectId, variantId, currentContentHash),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["tts-variants", projectId] });
      queryClient.invalidateQueries({ queryKey: ["tts-project", projectId] });
      queryClient.invalidateQueries({ queryKey: ["tts-projects"] });
      queryClient.invalidateQueries({ queryKey: ["scenario-audio"] });
      queryClient.invalidateQueries({ queryKey: ["dialogue-scenario"] });
      queryClient.invalidateQueries({
        queryKey: ["dialogue-collection-audio-status"],
      });
      toast.success("Kept this take. Text-change badge cleared.");
    },
    onError: (error) => toast.error(error.message),
  });

  const abortMutation = useMutation({
    mutationFn: (variantId: string) => ttsApi.cancelAutoStamp(projectId, variantId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["tts-variants", projectId] });
      toast.success("Auto-stamp aborted.");
    },
    onError: (error) => toast.error(error.message),
  });

  const selectionEnabled = selectedVariantId !== undefined;
  const variantIdSet = useMemo(
    () => new Set(variants.map((variant) => variant.id)),
    [variants]
  );
  const effectiveSelectedIds = useMemo(
    () => new Set([...selectedIds].filter((id) => variantIdSet.has(id))),
    [selectedIds, variantIdSet]
  );

  const allSelected =
    variants.length > 0 &&
    variants.every((variant) => effectiveSelectedIds.has(variant.id));

  function toggleSelected(variantId: string) {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (next.has(variantId)) next.delete(variantId);
      else next.add(variantId);
      return next;
    });
  }

  function toggleSelectAll() {
    if (allSelected) {
      setSelectedIds(new Set());
      return;
    }
    setSelectedIds(new Set(variants.map((variant) => variant.id)));
  }

  function exitSelectionMode() {
    setSelectionMode(false);
    setSelectedIds(new Set());
  }

  function confirmBulkDelete() {
    const ids = [...effectiveSelectedIds];
    if (ids.length === 0) return;
    const label =
      ids.length === 1
        ? "Delete 1 selected take? This cannot be undone."
        : `Delete ${ids.length} selected takes? This cannot be undone.`;
    if (!window.confirm(label)) return;
    bulkDeleteMutation.mutate(ids);
  }

  return (
    // overflow-visible so the waveform editor's sticky player can pin to the
    // viewport while sentence-map rows scroll underneath (Card defaults to
    // overflow-hidden for corner clipping).
    <Card className="overflow-visible">
      <CardHeader>
        <CardTitle className="text-base font-medium">Takes</CardTitle>
        <CardAction>
          <div className="flex flex-wrap items-center justify-end gap-2">
            {headerActions}
            {variants.length > 0 && (
              <Button
                type="button"
                size="sm"
                variant="outline"
                onClick={() => {
                  if (selectionMode) exitSelectionMode();
                  else setSelectionMode(true);
                }}
              >
                {selectionMode ? "Cancel" : "Select"}
              </Button>
            )}
          </div>
        </CardAction>
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        {selectionMode && variants.length > 0 && (
          <div className="flex flex-wrap items-center gap-2 rounded-md border bg-muted/40 px-3 py-2">
            <label className="flex cursor-pointer items-center gap-2 text-sm">
              <input
                type="checkbox"
                className="size-4 accent-foreground"
                checked={allSelected}
                onChange={toggleSelectAll}
              />
              {selectedIds.size === 0
                ? "Select takes"
                : `${effectiveSelectedIds.size} selected`}
            </label>
            <Button
              type="button"
              size="sm"
              variant="destructive"
              className="ml-auto"
              disabled={effectiveSelectedIds.size === 0 || bulkDeleteMutation.isPending}
              onClick={confirmBulkDelete}
            >
              {bulkDeleteMutation.isPending
                ? "Deleting…"
                : effectiveSelectedIds.size === 0
                  ? "Delete selected"
                  : `Delete ${effectiveSelectedIds.size} selected`}
            </Button>
          </div>
        )}
        {isLoading && (
          <p className="text-sm text-muted-foreground">Loading…</p>
        )}
        {!isLoading && variants.length === 0 && (
          <p className="text-sm text-muted-foreground">
            {emptyHint ?? "No takes yet — generate one to get started."}
          </p>
        )}
        {variants.length > 0 && (
          <Accordion
            defaultValue={[
              requestedTakeId && variants.some((v) => v.id === requestedTakeId)
                ? requestedTakeId
                : variants[0].id,
            ]}
          >
            {variants.map((variant) => {
              const isSelected = selectionEnabled
                ? variant.id === selectedVariantId
                : variant.isSelected;
              const isStale =
                !!currentContentHash &&
                !!variant.contentHash &&
                variant.contentHash !== currentContentHash;
              const checked = effectiveSelectedIds.has(variant.id);
              const job = variant.autoStampJob ?? null;
              const jobLive = autoStampInProgress(variant);
              const showAutoStampsBadge =
                !jobLive &&
                variant.tokenSync?.source === "auto" &&
                job?.status !== "error" &&
                job?.status !== "cancelled";
              return (
                <AccordionItem key={variant.id} value={variant.id}>
                  <div className="flex min-w-0 items-center gap-1">
                    {selectionMode && (
                      <label
                        className="flex shrink-0 cursor-pointer items-center px-1 py-2"
                        onClick={(event) => event.stopPropagation()}
                      >
                        <input
                          type="checkbox"
                          className="size-4 accent-foreground"
                          checked={checked}
                          onChange={() => toggleSelected(variant.id)}
                          aria-label={`Select take from ${new Date(variant.createdAt).toLocaleString()}`}
                        />
                      </label>
                    )}
                    <AccordionTrigger
                      className={cn(
                        "min-h-11 flex-1 touch-manipulation justify-start gap-2 py-2 md:min-h-0",
                        selectionMode && checked && "opacity-90"
                      )}
                    >
                      <span className="flex min-w-0 flex-wrap items-center gap-2 text-sm">
                        <span>
                          {new Date(variant.createdAt).toLocaleString()}
                        </span>
                        <span className="text-xs text-muted-foreground">
                          {variant.voice}
                        </span>
                        {isSelected && (
                          <Badge variant="secondary">Selected</Badge>
                        )}
                        {isStale && (
                          <Badge
                            variant="outline"
                            className="border-amber-500/50 text-amber-600 dark:text-amber-400"
                          >
                            Text changed
                          </Badge>
                        )}
                        {job && <AutoStampJobBadge job={job} nowMs={nowMs} />}
                        {showAutoStampsBadge && (
                          <Badge
                            variant="outline"
                            className="border-amber-500/50 text-amber-600 dark:text-amber-400"
                            title="Stamped automatically — review in the Tokens tab, then Mark reviewed"
                          >
                            auto stamps
                          </Badge>
                        )}
                        {variant.tokenSync?.source === "reviewed" && (
                          <Badge
                            variant="outline"
                            className="border-emerald-500/50 text-emerald-600 dark:text-emerald-400"
                          >
                            reviewed
                          </Badge>
                        )}
                        {!!currentContentHash && !variant.contentHash && (
                          <span
                            className="text-xs text-muted-foreground"
                            title="Generated before change tracking — staleness unknown."
                          >
                            untracked
                          </span>
                        )}
                      </span>
                    </AccordionTrigger>
                    {!selectionMode && (
                      <div className="ml-auto flex shrink-0 items-center gap-1">
                        {jobLive && (
                          <Button
                            type="button"
                            size="sm"
                            variant="outline"
                            className="min-h-10 touch-manipulation md:min-h-8"
                            disabled={
                              abortMutation.isPending &&
                              abortMutation.variables === variant.id
                            }
                            onClick={(e) => {
                              e.stopPropagation();
                              abortMutation.mutate(variant.id);
                            }}
                            title="Cancel tokenize/align so this take does not write stamps"
                          >
                            {abortMutation.isPending &&
                            abortMutation.variables === variant.id
                              ? "Aborting…"
                              : "Abort"}
                          </Button>
                        )}
                        <DropdownMenu>
                          <DropdownMenuTrigger
                            render={
                              <Button
                                variant="ghost"
                                size="icon"
                                className="size-10 shrink-0 touch-manipulation md:size-8"
                                onClick={(e) => e.stopPropagation()}
                              >
                                <MoreVertical className="size-4" />
                              </Button>
                            }
                          />
                          <DropdownMenuContent align="end">
                            {!!currentContentHash &&
                              variant.contentHash !== currentContentHash && (
                              <DropdownMenuItem
                                onClick={() => ignoreMutation.mutate(variant.id)}
                                disabled={ignoreMutation.isPending}
                              >
                                Ignore text changed
                              </DropdownMenuItem>
                            )}
                            <DropdownMenuItem
                              onClick={() => regenerateMutation.mutate(variant)}
                              disabled={regenerateMutation.isPending}
                            >
                              Regenerate with same settings
                            </DropdownMenuItem>
                            <DropdownMenuItem
                              variant="destructive"
                              onClick={() => {
                                if (
                                  window.confirm(
                                    "Delete this take? This cannot be undone."
                                  )
                                ) {
                                  deleteMutation.mutate(variant.id);
                                }
                              }}
                              disabled={deleteMutation.isPending}
                            >
                              Delete take
                            </DropdownMenuItem>
                          </DropdownMenuContent>
                        </DropdownMenu>
                      </div>
                    )}
                  </div>
                  <AccordionPanel className="overflow-visible">
                    <div className="flex flex-col gap-3">
                      {selectionEnabled && !isSelected && (
                        <Button
                          variant="outline"
                          size="sm"
                          className="min-h-11 w-full touch-manipulation sm:w-fit md:min-h-8"
                          onClick={() => selectMutation.mutate(variant.id)}
                          disabled={selectMutation.isPending}
                        >
                          Use this take
                        </Button>
                      )}
                      <WaveformEditor
                        projectId={projectId}
                        variant={variant}
                        dialogueLines={dialogueLines}
                        currentContentHash={currentContentHash}
                        hasUnsavedChanges={hasUnsavedChanges}
                        focusLineIndex={
                          requestedTakeId === variant.id
                            ? requestedLineIndex
                            : null
                        }
                        focusTimingMode={
                          requestedTakeId === variant.id
                            ? focusTimingMode
                            : null
                        }
                        ambience={ambience}
                        isSelectedTake={isSelected}
                      />
                    </div>
                  </AccordionPanel>
                </AccordionItem>
              );
            })}
          </Accordion>
        )}
      </CardContent>
    </Card>
  );
}
