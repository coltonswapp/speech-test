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
//      A feed clip should be mostly people talking in sentences, not
//      reactions with scenery in between. Computed
//      from the draft every time, so tuning a threshold applies to every
//      clip at once.
//   2. The Feed step's verdict (feed-review.ts): does the clip stand on its
//      own and is it worth watching? Stored on the draft.
// A hand-set answer in Studio overrides both.

export const FEED_MIN_SECONDS = 30;
export const FEED_MAX_SECONDS = 90;
/** A line of at least this many words is a sentence; shorter ones are reactions (うん。 / えっ、うま。). */
export const FEED_SENTENCE_WORDS = 4;
/**
 * Words said in sentences, per 10 s of clip. Counting words rather than lines
 * keeps it independent of where the transcriber breaks lines: a monologue in
 * three long sentences and a quick back-and-forth both score on what is said.
 * Calibrated on 24 clips (Nov 14): talky clips scored 10–21, reaction and
 * scenery clips 0–9.
 */
export const FEED_MIN_SENTENCE_WORDS_PER_10S = 10;

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
      problem: `Not much said in sentences (${m.sentenceWordsPer10s.toFixed(1)} words per 10 s; the feed needs ${FEED_MIN_SENTENCE_WORDS_PER_10S}). Mostly reactions or quiet.`,
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
