import "server-only";
import { getProviderKey } from "@/lib/secrets";
import { GEMINI_TAG_MODEL_DEFAULT } from "@/lib/gemini/models";
import { geminiGenerateContentUrl, geminiThinkingConfig } from "@/lib/gemini/text-model";
import { ClipPipelineError } from "@/lib/experiments/clips/asr";
import {
  buildClipTagPrompt,
  CLIP_TAGS_GEMINI_SCHEMA,
  clipTagInput,
  parseClipTagAnswer,
  type ClipTagPick,
} from "@/lib/experiments/clips/tags";
import type { ClipDraft, GeminiTokenCounts } from "@/lib/experiments/clips/types";
import { geminiTokenCounts } from "@/lib/experiments/clips/usage";

/** Tag step: one Gemini call over title, channel and transcript (no audio). */
export async function tagClip(
  draft: ClipDraft,
  modelOverride?: string
): Promise<{
  model: string;
  pick: ClipTagPick;
  reason: string;
  suggested: string[];
  tokens: GeminiTokenCounts;
}> {
  if (draft.sentences.length === 0) {
    throw new ClipPipelineError("Transcribe or enter the transcript first.", 400);
  }
  const apiKey = getProviderKey("gemini");
  if (!apiKey) throw new ClipPipelineError("Missing Gemini API key.");
  const model = modelOverride ?? (process.env.GEMINI_TAG_MODEL?.trim() || GEMINI_TAG_MODEL_DEFAULT);
  const thinkingConfig = geminiThinkingConfig(model, "low");

  const response = await fetch(geminiGenerateContentUrl(model), {
    method: "POST",
    headers: { "x-goog-api-key": apiKey, "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [{ role: "user", parts: [{ text: buildClipTagPrompt(clipTagInput(draft)) }] }],
      generationConfig: {
        ...(thinkingConfig ? { thinkingConfig } : {}),
        responseMimeType: "application/json",
        responseSchema: CLIP_TAGS_GEMINI_SCHEMA,
      },
    }),
    signal: AbortSignal.timeout(120_000),
  });
  if (!response.ok) {
    const body = await response.text().catch(() => "");
    throw new ClipPipelineError(`Gemini tagging failed (HTTP ${response.status}): ${body.slice(0, 500)}`, 502);
  }
  const json = await response.json();
  const tokens = geminiTokenCounts(json);
  const raw = json?.candidates?.[0]?.content?.parts
    ?.map((part: { text?: string }) => part?.text ?? "")
    .join("");
  let answer;
  try {
    answer = parseClipTagAnswer(JSON.parse(typeof raw === "string" ? raw : ""));
  } catch {
    throw new ClipPipelineError("Gemini tags were not JSON.", 502);
  }
  if (!answer) throw new ClipPipelineError("Gemini tags didn't fit the tag vocabulary.", 502);
  return { model, ...answer, tokens };
}
