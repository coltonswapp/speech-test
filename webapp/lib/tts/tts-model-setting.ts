import "server-only";
import { eq } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { appSettings } from "@/lib/db/schema";
import {
  GEMINI_TTS_DEFAULT_MODEL,
  isGeminiTtsModel,
  type GeminiTtsModel,
} from "@/lib/gemini/models";

// Studio-wide Gemini TTS model for conversation takes, set from
// Settings → Voices so 3.8 Flash and 3.8 Flash-Lite TTS can be A/B'd.
const TTS_MODEL_SETTING_KEY = "tts.geminiModel";

export async function getGeminiTtsModelSetting(): Promise<GeminiTtsModel> {
  try {
    const row = await db.query.appSettings.findFirst({
      where: eq(appSettings.key, TTS_MODEL_SETTING_KEY),
    });
    return isGeminiTtsModel(row?.value) ? row.value : GEMINI_TTS_DEFAULT_MODEL;
  } catch {
    return GEMINI_TTS_DEFAULT_MODEL;
  }
}

export async function setGeminiTtsModelSetting(model: GeminiTtsModel): Promise<void> {
  await db
    .insert(appSettings)
    .values({ key: TTS_MODEL_SETTING_KEY, value: model })
    .onConflictDoUpdate({ target: appSettings.key, set: { value: model } });
}
