"use client";

import type { ReactNode, SyntheticEvent } from "react";
import Link from "next/link";
import { Badge } from "@/components/ui/badge";
import {
  formatPublishedAt,
  type ScenarioReadinessSummary,
} from "@/lib/dialogue/client";
import {
  alignChipLabel,
  contentQaChipLabel,
  curriculumAlignStatus,
  curriculumPublishedStatus,
  formatCurriculumUpdatedAt,
  publishedChipLabel,
  reviewChipLabel,
  thumbnailChipLabel,
} from "@/lib/dialogue/scenario-readiness";
import {
  readinessChipHref,
  type ReadinessChipKey,
} from "@/lib/dialogue/scenario-editor-deep-link";
import { cn } from "@/lib/utils";

export type { ReadinessChipTab } from "@/lib/dialogue/scenario-editor-deep-link";

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
  chip,
  tone,
  title,
  children,
}: {
  hrefBase?: string;
  chip: ReadinessChipKey;
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
          href={readinessChipHref(hrefBase, chip)}
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
  const align =
    readiness.align ??
    curriculumAlignStatus(readiness.timing, readiness.sync);
  const alignTone =
    align === "done"
      ? ("ok" as const)
      : align === "ready" || align === "partial" || align === "stale"
        ? ("warn" as const)
        : ("muted" as const);
  const review = readiness.review ?? "pending";
  const reviewTone =
    review === "reviewed"
      ? ("ok" as const)
      : review === "flagged"
        ? ("warn" as const)
        : ("muted" as const);
  const published =
    readiness.published ??
    curriculumPublishedStatus({
      publishedAudioUrl: readiness.audio === "draft" ? null : "published",
      audioStale: readiness.audio === "stale",
    });
  const publishedTone =
    published === "published"
      ? ("ok" as const)
      : published === "stale"
        ? ("warn" as const)
        : ("muted" as const);
  const publishedAtLabel = formatPublishedAt(readiness.publishedAt);
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
        "flex max-w-[min(100%,22rem)] flex-wrap items-center justify-end gap-1 sm:max-w-none",
        className,
      )}
    >
      <ReadinessChip
        hrefBase={hrefBase}
        chip="audio"
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
        chip="align"
        tone={alignTone}
        title={
          align === "done"
            ? "Aligner: line timing + token karaoke published with the current clip"
            : align === "ready"
              ? "Aligner ready — republish to ship timing and karaoke with audio"
              : align === "partial"
                ? "Aligner partial (line marks or karaoke incomplete)"
                : align === "stale"
                  ? "Aligner stale vs the last publish — republish to refresh karaoke"
                  : "No aligner output yet (line timing and karaoke missing)"
        }
      >
        {alignChipLabel(align)}
      </ReadinessChip>
      <ReadinessChip
        hrefBase={hrefBase}
        chip="review"
        tone={reviewTone}
        title={
          review === "reviewed"
            ? "Alignment has had its human-ear review pass (tokenSync source: reviewed or hand-stamped)"
            : review === "flagged"
              ? "Auto-stamped alignment still has flags — review in the queue or Token timing"
              : "Alignment not yet reviewed by ear"
        }
      >
        {reviewChipLabel(review)}
      </ReadinessChip>
      <ReadinessChip
        hrefBase={hrefBase}
        chip="published"
        tone={publishedTone}
        title={
          published === "unpublished"
            ? "No published take (Gate A) — scene is not in the learner CDN/DB yet"
            : published === "stale"
              ? `Published take is stale vs current lines or bed — republish (Gate A)${
                  publishedAtLabel ? ` · last published ${publishedAtLabel}` : ""
                }`
              : `Has a published take (Gate A)${
                  publishedAtLabel ? ` · last published ${publishedAtLabel}` : ""
                }`
        }
      >
        {publishedChipLabel(published)}
      </ReadinessChip>
      <ReadinessChip
        hrefBase={hrefBase}
        chip="quiz"
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
        chip="thumbnail"
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
        chip="contentQa"
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
