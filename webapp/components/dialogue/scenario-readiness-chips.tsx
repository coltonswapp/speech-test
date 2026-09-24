"use client";

import type { ReactNode, SyntheticEvent } from "react";
import Link from "next/link";
import { Badge } from "@/components/ui/badge";
import type { ScenarioReadinessSummary } from "@/lib/dialogue/client";
import {
  contentQaChipLabel,
  formatCurriculumUpdatedAt,
  syncChipLabel,
  thumbnailChipLabel,
} from "@/lib/dialogue/scenario-readiness";
import { cn } from "@/lib/utils";

/** Scenario editor section ids used by `?tab=` deep links. */
export type ReadinessChipTab = "audio" | "quiz" | "overview";

const CHIP_TAB: Record<
  "audio" | "timing" | "sync" | "quiz" | "thumbnail" | "contentQa",
  ReadinessChipTab
> = {
  audio: "audio",
  timing: "audio",
  sync: "audio",
  quiz: "quiz",
  thumbnail: "overview",
  contentQa: "overview",
};

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

function stopChipNavigation(event: SyntheticEvent) {
  // Chips sit inside expandable / sortable rows; don't toggle or drag.
  event.stopPropagation();
}

function ReadinessChip({
  hrefBase,
  tab,
  tone,
  title,
  children,
}: {
  hrefBase?: string;
  tab: ReadinessChipTab;
  tone: "ok" | "warn" | "muted" | "draft";
  title: string;
  children: ReactNode;
}) {
  const className = cn("text-[9px]", readinessChipClass(tone));

  if (!hrefBase) {
    return (
      <Badge variant="outline" className={className} title={title}>
        {children}
      </Badge>
    );
  }

  return (
    <Badge
      variant="outline"
      className={className}
      title={title}
      render={
        <Link
          href={`${hrefBase}?tab=${tab}`}
          onClick={stopChipNavigation}
          onPointerDown={stopChipNavigation}
        />
      }
    >
      {children}
    </Badge>
  );
}

export function ScenarioReadinessChips({
  readiness,
  audioTitle,
  hrefBase,
  className,
}: {
  readiness: ScenarioReadinessSummary;
  /** Optional override for the audio chip tooltip (e.g. publish-stale detail). */
  audioTitle?: string;
  /**
   * Scenario editor path without query, e.g.
   * `/content/dialogues/{collectionId}/{scenarioSlug}`.
   * When set, chips link to `?tab=` sections in the editor.
   */
  hrefBase?: string;
  className?: string;
}) {
  const audioTone =
    readiness.audio === "published"
      ? ("ok" as const)
      : readiness.audio === "stale"
        ? ("warn" as const)
        : ("draft" as const);
  const timingTone =
    readiness.timing === "done"
      ? ("ok" as const)
      : readiness.timing === "ready" || readiness.timing === "partial"
        ? ("warn" as const)
        : ("muted" as const);
  const syncTone =
    readiness.sync === "complete"
      ? ("ok" as const)
      : readiness.sync === "stale" || readiness.sync === "ready"
        ? ("warn" as const)
        : ("muted" as const);
  const quizStatus =
    readiness.quiz ??
    (readiness.quizCount <= 0
      ? "missing"
      : readiness.audio === "published"
        ? "published"
        : "ready");
  const quizTone =
    quizStatus === "published"
      ? ("ok" as const)
      : quizStatus === "ready"
        ? ("warn" as const)
        : ("muted" as const);
  const quizLabel =
    readiness.quizCount === 0 ? "—" : `quiz ${readiness.quizCount}`;
  const thumbnail = readiness.thumbnail ?? "missing";
  const thumbnailTone =
    thumbnail === "own"
      ? ("ok" as const)
      : thumbnail === "inherited"
        ? ("draft" as const)
        : ("muted" as const);
  const contentQa = readiness.contentQa ?? "pending";
  const contentQaHasNote = readiness.contentQaHasNote === true;
  const contentQaTone =
    contentQa === "done"
      ? ("ok" as const)
      : contentQa === "dialogue" || contentQa === "quiz"
        ? ("warn" as const)
        : ("muted" as const);

  return (
    <div
      className={cn(
        "flex max-w-[min(100%,16rem)] flex-wrap items-center justify-end gap-1 sm:max-w-none",
        className,
      )}
    >
      <ReadinessChip
        hrefBase={hrefBase}
        tab={CHIP_TAB.audio}
        tone={audioTone}
        title={
          audioTitle ??
          (readiness.audio === "published"
            ? "Published audio"
            : readiness.audio === "stale"
              ? "Published audio is stale vs current lines or bed"
              : "No published audio yet")
        }
      >
        {readiness.audio === "draft" ? "draft" : "audio"}
      </ReadinessChip>
      <ReadinessChip
        hrefBase={hrefBase}
        tab={CHIP_TAB.timing}
        tone={timingTone}
        title={
          readiness.timing === "done"
            ? "Line timing published with the current clip"
            : readiness.timing === "ready"
              ? "Line timing ready — republish to ship with audio"
              : readiness.timing === "partial"
                ? "Line timing partial"
                : "Line timing missing"
        }
      >
        timing
      </ReadinessChip>
      <ReadinessChip
        hrefBase={hrefBase}
        tab={CHIP_TAB.sync}
        tone={syncTone}
        title={
          readiness.sync === "complete"
            ? "Token karaoke published with the current clip"
            : readiness.sync === "ready"
              ? "Token karaoke ready — republish to ship with audio"
              : readiness.sync === "tokens-only"
                ? "Tokens present, times incomplete"
                : readiness.sync === "stale"
                  ? "Token karaoke stale vs the last publish"
                  : "No token sync"
        }
      >
        {syncChipLabel(readiness.sync)}
      </ReadinessChip>
      <ReadinessChip
        hrefBase={hrefBase}
        tab={CHIP_TAB.quiz}
        tone={quizTone}
        title={
          quizStatus === "missing"
            ? "No quiz"
            : `${readiness.quizCount} quiz question${readiness.quizCount === 1 ? "" : "s"}${
                readiness.quizWithEvidence > 0
                  ? ` (${readiness.quizWithEvidence} with evidence links)`
                  : ""
              }${
                quizStatus === "ready"
                  ? " — republish audio to keep the lesson in lock step"
                  : ""
              }`
        }
      >
        {quizLabel}
      </ReadinessChip>
      <ReadinessChip
        hrefBase={hrefBase}
        tab={CHIP_TAB.thumbnail}
        tone={thumbnailTone}
        title={
          thumbnail === "own"
            ? "Scene has its own thumbnail"
            : thumbnail === "inherited"
              ? "No scene thumbnail — inherits the lesson thumbnail"
              : "No thumbnail on scene or lesson"
        }
      >
        {thumbnailChipLabel(thumbnail)}
      </ReadinessChip>
      <ReadinessChip
        hrefBase={hrefBase}
        tab={CHIP_TAB.contentQa}
        tone={contentQaTone}
        title={
          contentQa === "done"
            ? `Learner-client content QA complete (dialogue + quiz)${
                contentQaHasNote ? " — has review note" : ""
              }`
            : contentQa === "dialogue"
              ? `Dialogue reviewed from the client; quiz still awaiting${
                  contentQaHasNote ? " — has review note" : ""
                }`
              : contentQa === "quiz"
                ? `Quiz reviewed from the client; dialogue still awaiting${
                    contentQaHasNote ? " — has review note" : ""
                  }`
                : "No learner-client content QA yet (dialogue + quiz)"
        }
      >
        {contentQaChipLabel(contentQa, contentQaHasNote)}
      </ReadinessChip>
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
