import "server-only";
import { z } from "zod";
import { getProviderKey } from "@/lib/secrets";
import { GEMINI_FEED_MODEL_DEFAULT } from "@/lib/gemini/models";
import { geminiGenerateContentUrl, geminiThinkingConfig } from "@/lib/gemini/text-model";
import { ClipPipelineError } from "@/lib/experiments/clips/asr";
import type { ClipDraft, GeminiTokenCounts } from "@/lib/experiments/clips/types";
import { geminiTokenCounts } from "@/lib/experiments/clips/usage";

const responseSchema = z.object({ suitable: z.boolean(), reason: z.string() });

function buildPrompt(draft: ClipDraft): string {
  const lines = draft.sentences
    .map((s, i) => `${i + 1}. ${s.text}${s.en?.trim() ? `\n   ${s.en.trim()}` : ""}`)
    .join("\n");
  const source = draft.video ? `\nVideo: “${draft.video.title}” by ${draft.video.channelName}` : "";
  return `You are choosing clips for the feed of a Japanese learning app. A learner swipes through short clips cut from YouTube videos, one at a time, each with its transcript. They have not seen the rest of the video. This clip was cut automatically at a pause, so it may start or end anywhere.

Decide whether this clip is worth showing in the feed.

Suitable:
- Someone says something: an explanation, a story, an opinion, a description, a real exchange between people. There are sentences to learn from.
- It makes sense on its own. A learner can tell what is being talked about without the minutes before it.
- Short, simple lines are fine, even good, when they add up to something: a little scene or story with a point (a misunderstanding cleared up, a request and a reply, a joke with a payoff). Slow, simple dialogue is what beginners need.

Not suitable:
- Mostly reactions, exclamations, single words, greetings or fillers (うま！, すごい, かわいい, えー) with little said in sentences.
- A string of reactions to what is on screen (おっ、なんだこれ？ / すっご / めっちゃ美味しそう) that doesn't build into a story or exchange, even if each line is a sentence. Ask: could a learner retell what happened or what was said?
- A fragment that depends on what came before or stops before its point, so it is confusing alone.
- Channel housekeeping: intro or outro patter, asking for likes and subscriptions, sponsor reads.
- The transcript looks wrong or garbled (lines that don't fit together), so the clip would teach mistakes.

A clip can be casual, short on vocabulary or easy and still be suitable; judge whether it is worth a learner's minute, not how advanced it is. When it is a close call, say no: the clip stays available outside the feed.

"reason": one short English sentence a reviewer can check against the transcript.
${source}
Length: ${draft.durationSec.toFixed(0)} s
Transcript (Japanese, then its English):
${lines}`;
}

/** One Gemini call over the transcript and its English. */
export async function reviewClipForFeed(
  draft: ClipDraft,
  modelOverride?: string
): Promise<{ model: string; suitable: boolean; reason: string; tokens: GeminiTokenCounts }> {
  const apiKey = getProviderKey("gemini");
  if (!apiKey) throw new ClipPipelineError("Missing Gemini API key.");
  const model =
    modelOverride ?? (process.env.GEMINI_FEED_MODEL?.trim() || GEMINI_FEED_MODEL_DEFAULT);
  const thinkingConfig = geminiThinkingConfig(model, "low");

  const response = await fetch(geminiGenerateContentUrl(model), {
    method: "POST",
    headers: { "x-goog-api-key": apiKey, "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [{ role: "user", parts: [{ text: buildPrompt(draft) }] }],
      generationConfig: {
        ...(thinkingConfig ? { thinkingConfig } : {}),
        responseMimeType: "application/json",
        responseSchema: {
          type: "object",
          properties: { suitable: { type: "boolean" }, reason: { type: "string" } },
          required: ["suitable", "reason"],
        },
      },
    }),
    signal: AbortSignal.timeout(120_000),
  });
  if (!response.ok) {
    const body = await response.text().catch(() => "");
    throw new ClipPipelineError(
      `Gemini feed check failed (HTTP ${response.status}): ${body.slice(0, 500)}`,
      502
    );
  }
  const json = await response.json();
  const tokens = geminiTokenCounts(json);
  const raw = json?.candidates?.[0]?.content?.parts
    ?.map((part: { text?: string }) => part?.text ?? "")
    .join("");
  let parsed;
  try {
    parsed = responseSchema.safeParse(JSON.parse(typeof raw === "string" ? raw : ""));
  } catch {
    throw new ClipPipelineError("Gemini feed check was not JSON.", 502);
  }
  if (!parsed.success) throw new ClipPipelineError("Gemini feed check had no verdict.", 502);
  return { model, suitable: parsed.data.suitable, reason: parsed.data.reason.trim(), tokens };
}
