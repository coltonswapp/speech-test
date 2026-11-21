import type { ClipFeedbackReason, ClipFeedbackStatus } from "@/lib/clip-feedback/schema";
import { lessonReportCategoryLabels, type LessonReportCategory } from "@/lib/lesson-reports/types";
import type { IssueSubject } from "./subjects";

/** Same wording as the app's report screen (ClipFeedback.swift). */
export const CLIP_REASON_LABELS: Record<ClipFeedbackReason, string> = {
  translation: "Bad translation",
  tokenization: "Words split wrong",
  reading: "Wrong reading",
  timing: "Subtitles out of sync",
  video: "Video problem",
  other: "Something else",
};

export const ISSUE_STATUS_LABELS: Record<ClipFeedbackStatus, string> = {
  open: "Open",
  resolved: "Resolved",
  wontfix: "Won’t fix",
  duplicate: "Duplicate",
};

export const ISSUE_SUBJECT_LABELS: Record<IssueSubject, string> = {
  clip: "Clip",
  scene: "Scene",
};

/** A clip reason or a scene category, whichever the issue carries. */
export function issueReasonLabel(subject: IssueSubject, reason: string): string {
  const labels: Record<string, string> =
    subject === "clip" ? CLIP_REASON_LABELS : (lessonReportCategoryLabels as Record<LessonReportCategory, string>);
  return labels[reason] ?? reason;
}

export function issueStatusLabel(status: string): string {
  return ISSUE_STATUS_LABELS[status as ClipFeedbackStatus] ?? status;
}

export function formatIssueDate(iso: string | null | undefined): string {
  if (!iso) return "—";
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return iso;
  return date.toLocaleString(undefined, { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" });
}
