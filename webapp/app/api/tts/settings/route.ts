import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { z } from "zod";
import { GEMINI_TTS_MODELS } from "@/lib/gemini/models";
import {
  getGeminiTtsModelSetting,
  setGeminiTtsModelSetting,
} from "@/lib/tts/tts-model-setting";

const modelIds = GEMINI_TTS_MODELS.map((model) => model.id) as [
  (typeof GEMINI_TTS_MODELS)[number]["id"],
  ...(typeof GEMINI_TTS_MODELS)[number]["id"][],
];

const putSchema = z.object({ geminiTtsModel: z.enum(modelIds) });

export async function GET() {
  return NextResponse.json({ geminiTtsModel: await getGeminiTtsModelSetting() });
}

export async function PUT(request: NextRequest) {
  const parsed = putSchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  }
  await setGeminiTtsModelSetting(parsed.data.geminiTtsModel);
  return NextResponse.json({ geminiTtsModel: parsed.data.geminiTtsModel });
}
