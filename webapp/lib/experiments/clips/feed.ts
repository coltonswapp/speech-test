import {
  clipIsAligned,
  clipIsTranslated,
  type ClipDraft,
  type ClipFeedState,
} from "@/lib/experiments/clips/types";

// Feed eligibility: which clips are worth a learner's swipe. Client-safe.
//
// Every aligned clip can be studied (list, "more from this video"); the feed
// only takes clips that pass two gates:
//   1. Measured rules (below): length, how much is said, how many real lines.
//      A floor: the clip has to have people talking, not mostly
//      scenery or silence. Computed
//      from the draft every time, so tuning a threshold applies to every
//      clip at once.
//   2. The Feed step's verdict (feed-review.ts): does the clip stand on its
//      own and is it worth watching? Stored on the draft.
// A hand-set answer in Studio overrides both.

export const FEED_MIN_SECONDS = 30;
export const FEED_MAX_SECONDS = 90;
/**
 * A line of at least this many words counts; single-word lines (えい！ / 妹？)
 * don't. Two, not more: slow, simple dialogue (答えてよ。 / あれ妹。) is
 * exactly what beginners need, and it is made of short lines.
 */
export const FEED_SENTENCE_WORDS = 2;
/**
 * Words said in lines of FEED_SENTENCE_WORDS+ words, per 10 s of clip. Only
 * a floor that keeps out near-silent and scenery clips: whether the talk adds
 * up to something (a story, an exchange) or is just reactions is the Feed
 * step's call (feed-review.ts), since word counts can't tell them apart.
 * Recalibrated on 38 clips (Nov 15): an editor-approved slow dialogue clip
 * (Minecraft skit) scored 8.2 and 9.6 while a rejected reaction clip scored
 * 11.6; scenery and walking clips scored 1–5.
 */
export const FEED_MIN_SENTENCE_WORDS_PER_10S = 6;

/** Tokens that are only punctuation aren't words. */
const WORD_TOKEN = /[\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Han}0-9０-９]/u;

export type ClipFeedMetrics = {
  seconds: number;
  lines: number;
  /** Words (tokens) in the whole transcript. */
  words: number;
  /** Words in lines of FEED_SENTENCE_WORDS or more. */
  sentenceWords: number;
  /** sentenceWords per 10 s of clip. */
  sentenceWordsPer10s: number;
};

export function clipFeedMetrics(draft: ClipDraft): ClipFeedMetrics {
  const seconds = draft.durationSec;
  let words = 0;
  let sentenceWords = 0;
  for (const sentence of draft.sentences) {
    const count = (sentence.tokens ?? []).filter((t) => WORD_TOKEN.test(t.text)).length;
    words += count;
    if (count >= FEED_SENTENCE_WORDS) sentenceWords += count;
  }
  return {
    seconds,
    lines: draft.sentences.length,
    words,
    sentenceWords,
    sentenceWordsPer10s: seconds > 0 ? (10 * sentenceWords) / seconds : 0,
  };
}

export type ClipFeedRule = { label: string; value: string; ok: boolean; problem: string };

/** The measured rules, each with what the clip scored. */
export function clipFeedRules(draft: ClipDraft): ClipFeedRule[] {
  const m = clipFeedMetrics(draft);
  return [
    {
      label: `Length ${FEED_MIN_SECONDS}–${FEED_MAX_SECONDS} s`,
      value: `${m.seconds.toFixed(1)} s`,
      ok: m.seconds >= FEED_MIN_SECONDS && m.seconds <= FEED_MAX_SECONDS,
      problem:
        m.seconds < FEED_MIN_SECONDS
          ? `Too short (${m.seconds.toFixed(0)} s; the feed takes ${FEED_MIN_SECONDS}–${FEED_MAX_SECONDS} s).`
          : `Too long (${m.seconds.toFixed(0)} s; the feed takes ${FEED_MIN_SECONDS}–${FEED_MAX_SECONDS} s).`,
    },
    {
      label: `Said in sentences: ${FEED_MIN_SENTENCE_WORDS_PER_10S}+ words per 10 s, counting lines of ${FEED_SENTENCE_WORDS}+ words`,
      value: `${m.sentenceWordsPer10s.toFixed(1)} per 10 s (${m.sentenceWords} of ${m.words} words)`,
      ok: m.sentenceWordsPer10s >= FEED_MIN_SENTENCE_WORDS_PER_10S,
      problem: `Not much said (${m.sentenceWordsPer10s.toFixed(1)} words per 10 s; the feed needs ${FEED_MIN_SENTENCE_WORDS_PER_10S}). Mostly quiet, scenery or one-word reactions.`,
    },
  ];
}

/** What still has to happen before the clip can be judged at all; null when ready. */
export function clipFeedNotReady(draft: ClipDraft): string | null {
  if (draft.sentences.length === 0) return "No transcript.";
  if (!clipIsAligned(draft)) return "Not aligned yet.";
  if (!clipIsTranslated(draft)) return "Not translated yet.";
  return null;
}

export type ClipFeedStatus = {
  state: ClipFeedState;
  /** What the app's feed does with the clip. */
  eligible: boolean;
  reason: string | null;
};

export function clipFeedStatus(draft: ClipDraft): ClipFeedStatus {
  if (draft.deprecated) return { state: "out", eligible: false, reason: "Deprecated." };
  const manual = draft.feed?.manual;
  if (manual) {
    // A hand-picked clip still has to be playable.
    const eligible = manual.eligible && clipIsAligned(draft);
    return { state: manual.eligible ? "manual-in" : "manual-out", eligible, reason: "Set by hand." };
  }
  const notReady = clipFeedNotReady(draft);
  if (notReady) return { state: "unchecked", eligible: false, reason: notReady };
  const failed = clipFeedRules(draft).filter((rule) => !rule.ok);
  if (failed.length > 0) {
    return { state: "out", eligible: false, reason: failed.map((rule) => rule.problem).join(" ") };
  }
  const auto = draft.feed?.auto;
  if (!auto) return { state: "unchecked", eligible: false, reason: "Feed check not run yet." };
  return {
    state: auto.eligible ? "in" : "out",
    eligible: auto.eligible,
    reason: auto.reason ?? null,
  };
}

export const FEED_STATE_LABELS: Record<ClipFeedState, string> = {
  in: "In feed",
  out: "Not in feed",
  "manual-in": "In feed (by hand)",
  "manual-out": "Not in feed (by hand)",
  unchecked: "Feed unchecked",
};
