/**
 * A small copy of what a learner sees in a clip, taken by the server when an
 * agent claims a report and again when it finishes, so Studio can show what
 * changed without trusting the agent's summary. Pure.
 */
import type { ClipDraft } from "@/lib/experiments/clips/types";

export type SnapshotToken = { text: string; reading?: string };

export type SnapshotLine = {
  ja: string;
  en: string | null;
  /** First and last token time in clip seconds (before shiftSec); null when unaligned. */
  start: number | null;
  end: number | null;
  tokens: SnapshotToken[] | null;
};

export type ClipSnapshot = {
  takenAt: string;
  durationSec: number;
  shiftSec: number;
  /** Effective feed answer: hand-set wins over the Feed step; null = not judged. */
  feedEligible: boolean | null;
  jlptLevel: number | null;
  /** Deprecation reason ("" when deprecated without one); null = live. */
  deprecated: string | null;
  lines: SnapshotLine[];
};

const round = (n: number) => Math.round(n * 1000) / 1000;

export function snapshotClip(draft: ClipDraft, takenAt = new Date()): ClipSnapshot {
  return {
    takenAt: takenAt.toISOString(),
    durationSec: round(draft.durationSec),
    shiftSec: draft.shiftSec,
    feedEligible: draft.feed?.manual?.eligible ?? draft.feed?.auto?.eligible ?? null,
    jlptLevel: draft.difficulty?.jlptLevel ?? null,
    deprecated: draft.deprecated ? (draft.deprecated.reason ?? "") : null,
    lines: draft.sentences.map((sentence) => {
      const tokens = sentence.tokens;
      const starts = (tokens ?? []).map((t) => t.startSec).filter((n): n is number => n != null);
      const ends = (tokens ?? []).map((t) => t.endSec).filter((n): n is number => n != null);
      return {
        ja: sentence.text,
        en: sentence.en?.trim() || null,
        start: starts.length ? round(Math.min(...starts)) : null,
        end: ends.length ? round(Math.max(...ends)) : null,
        tokens: tokens
          ? tokens.map((t) => (t.reading ? { text: t.text, reading: t.reading } : { text: t.text }))
          : null,
      };
    }),
  };
}
