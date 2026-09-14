"use client";

import { Badge } from "@/components/ui/badge";
import type { ScenarioReadinessSummary } from "@/lib/dialogue/client";
import {
  formatCurriculumUpdatedAt,
  syncChipLabel,
} from "@/lib/dialogue/scenario-readiness";
import { cn } from "@/lib/utils";

function readinessChipClass(
  tone: "ok" | "warn" | "muted" | "draft",
): string {
  switch (tone) {
    case "ok":
      return "border-emerald-500/40 text-emerald-600 dark:text-emerald-400";
    case "warn":
      return "border-amber-500/50 text-amber-600 dark:text-amber-400";
    case "draft":
      return "text-muted-foreground";
    case "muted":
      return "text-muted-foreground/70";
  }
}

export function ScenarioReadinessChips({
  readiness,
  audioTitle,
}: {
  readiness: ScenarioReadinessSummary;
  /** Optional override for the audio chip tooltip (e.g. publish-stale detail). */
  audioTitle?: string;
}) {
  const audioTone =
    readiness.audio === "published" ? ("ok" as const) : ("draft" as const);
  const timingTone =
    readiness.timing === "done"
      ? ("ok" as const)
      : readiness.timing === "partial"
        ? ("warn" as const)
        : ("muted" as const);
  const syncTone =
    readiness.sync === "complete"
      ? ("ok" as const)
      : readiness.sync === "stale"
        ? ("warn" as const)
        : ("muted" as const);
  const quizTone =
    readiness.quizCount > 0 ? ("ok" as const) : ("muted" as const);
  const quizLabel =
    readiness.quizCount === 0 ? "—" : `quiz ${readiness.quizCount}`;

  return (
    <div className="flex max-w-[min(100%,14rem)] flex-wrap items-center justify-end gap-1 sm:max-w-none">
      <Badge
        variant="outline"
        className={cn("text-[9px]", readinessChipClass(audioTone))}
        title={
          audioTitle ??
          (readiness.audio === "published"
            ? "Published audio"
            : "No published audio yet")
        }
      >
        {readiness.audio === "published" ? "audio" : "draft"}
      </Badge>
      <Badge
        variant="outline"
        className={cn("text-[9px]", readinessChipClass(timingTone))}
        title={
          readiness.timing === "done"
            ? "Line timing complete"
            : readiness.timing === "partial"
              ? "Line timing partial"
              : "Line timing missing"
        }
      >
        timing
      </Badge>
      <Badge
        variant="outline"
        className={cn("text-[9px]", readinessChipClass(syncTone))}
        title={
          readiness.sync === "complete"
            ? "Token karaoke complete"
            : readiness.sync === "tokens-only"
              ? "Tokens present, times incomplete"
              : readiness.sync === "stale"
                ? "Token sync stale vs current lines"
                : "No token sync"
        }
      >
        {syncChipLabel(readiness.sync)}
      </Badge>
      <Badge
        variant="outline"
        className={cn("text-[9px]", readinessChipClass(quizTone))}
        title={
          readiness.quizCount === 0
            ? "No quiz"
            : `${readiness.quizCount} quiz question${readiness.quizCount === 1 ? "" : "s"}${
                readiness.quizWithEvidence > 0
                  ? ` (${readiness.quizWithEvidence} with evidence links)`
                  : ""
              }`
        }
      >
        {quizLabel}
      </Badge>
    </div>
  );
}

/** Compact last-updated label used next to readiness chips. */
export function ScenarioUpdatedLabel({
  updatedAt,
}: {
  updatedAt: string;
}) {
  const updatedLabel = formatCurriculumUpdatedAt(updatedAt);
  if (!updatedLabel) return null;
  return (
    <span
      className="whitespace-nowrap text-[10px] text-muted-foreground"
      title={new Date(updatedAt).toLocaleString()}
    >
      {updatedLabel}
    </span>
  );
}
