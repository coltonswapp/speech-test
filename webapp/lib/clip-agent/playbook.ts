/**
 * How an agent works a learner clip report. Returned by claim and carried in
 * the dispatch webhook, so agents without the repo get it too. Tool names are
 * the shizen-studio MCP's. Pure.
 */
import type { ClipFeedbackReason } from "@/lib/clip-feedback/schema";

const RULES = `Rules:
- Fix only what the report is about. Note other problems you see in the summary instead of fixing them.
- Never delete_clip. If a clip is clearly broken beyond repair, patch_clip deprecated {reason} and finish could_not_fix.
- For a single misheard or mistyped word (token count unchanged): patch_clip swap {sentence, token, text, reading?, english?}. That keeps timings, alignment and the feed verdict. Don't send sentences for a one-word fix — that drops alignment and re-runs tokenize/align/feed.
- When you rewrite a line or add/remove lines, send sentences and hand-written english in the same patch_clip call, then run_clip_steps mode "missing". Don't rely on the Translate step for lines you wrote.
- To break a long subtitle line, use patch_clip split {sentence, atToken, english?}. That keeps tokens, timings, alignment and the feed verdict. Don't send sentences just to move a line break — that retokenizes and can change readings.
- To join adjacent lines, use patch_clip merge {sentence, count?, english?}. Same preservation.
- Unsure (models disagree, the fix would touch more than the reported lines, or you can't tell from the evidence): finish needs_review and say what a person should compare. Applying a fix and asking for review is fine.
- Always call finish_clip_feedback, also when you give up (could_not_fix). Summary: first line = cause and fix in one sentence; then the details.`;

const SECTIONS: Record<ClipFeedbackReason, string> = {
  timing: `Subtitles out of sync:
1. get_clip view "full". Look for tokens stretched over several seconds, or with scores near 0. These usually sit next to speech the transcript is missing.
2. compare_clip_asr with models gemini-3.1-pro-preview and gemini-3.8-flash. Find spoken text the saved transcript lacks: title cards, intro/outro lines, interjections.
3. If text is missing: patch_clip with the FULL sentences (missing lines added in order) and english for every line, then run_clip_steps mode "missing". Check that the reported line's new start/end look sane against its neighbours.
4. Only if every line is off by the same amount (lyrics early or late throughout): patch_clip shiftSec instead (−2…2 s).
5. Re-running align alone rarely fixes a sync report. Don't loop on it.`,
  translation: `Bad translation:
1. get_clip, read the reported line and the lines around it for context.
2. Rewrite that line's English by hand (patch_clip english, every line sent, only that one changed). Natural, short subtitle English.
3. If the neighbouring lines have the same mistake (same term, same misread), fix them too and say so.`,
  transcription: `Bad transcription:
1. get_clip view "full", find the reported line (and the picked word, if any). compare_clip_asr if you need to confirm what was said.
2. A single misheard word (same token count): patch_clip swap {sentence, token, text, reading?, english?}. That keeps timings and the feed verdict.
3. If you need to add, remove or rewrite lines: patch_clip with the FULL sentences and english for every line, then run_clip_steps mode "missing". Don't send sentences for a one-word fix.`,
  tokenization: `Words split wrong:
1. get_clip view "full", find the reported line (and the picked word, if any).
2. If the surface is right and only the split is wrong: patch_clip tokens {sentence, tokens:[{text, reading?}]}. Texts must join to exactly the line.
3. If you split a token, run_clip_steps steps ["align"] with onlyUntimed: true.
4. If a word was misheard (wrong kanji, same number of tokens): patch_clip swap {sentence, token, text, reading?} instead.`,
  reading: `Wrong reading:
1. get_clip view "full", find the token. Tokens with readingFallback came from the dictionary fallback and are often wrong.
2. If only the reading is wrong: patch_clip tokens for that sentence with the corrected reading (hiragana). Keep the split as it is.
3. If the surface is wrong (misheard word) and the split stays the same: patch_clip swap {sentence, token, text, reading}. That keeps timings and the feed verdict.
4. Check the same word elsewhere in the clip.`,
  video: `Video problem:
Don't edit lines. Check get_clip / get_public_clip (video id, start/end, orientation, deprecated). If the video is gone or the range is clearly wrong, patch_clip deprecated {reason} and finish fixed. Otherwise finish could_not_fix (or needs_review) with what you saw.`,
  other: `Something else:
Read the note and the reported line. Diagnose from the clip (get_clip view "full") and the audio (compare_clip_asr) and fix only what the evidence supports. A one-word transcript fix is patch_clip swap (keeps timings and the feed verdict). If the report is unclear, finish needs_review with your reading of it.`,
};

/** The playbook for one reason (or every section), with the rules. */
export function clipFeedbackPlaybook(reason: ClipFeedbackReason | null): string {
  const body = reason
    ? SECTIONS[reason]
    : Object.values(SECTIONS).join("\n\n");
  return `${body}\n\n${RULES}`;
}
