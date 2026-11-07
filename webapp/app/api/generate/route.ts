import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { isProviderConfigured } from "@/lib/secrets";
import { getGeminiTtsModelSetting } from "@/lib/tts/tts-model-setting";
import {
  createTtsGeneration,
  listGenerations,
  publicGeneration,
} from "@/lib/generate/service";
import { generateRequestSchema } from "@/lib/generate/types";
import { studioGenerateService } from "@/lib/generate/runtime";
import { forbidContentQaOnly, generateErrorResponse } from "@/lib/generate/http";

export const maxDuration = 300;

export async function GET() {
  try {
    return NextResponse.json(await listGenerations(studioGenerateService()));
  } catch (error) {
    return generateErrorResponse(error);
  }
}

export async function POST(request: NextRequest) {
  const forbidden = forbidContentQaOnly(request);
  if (forbidden) return forbidden;
  if (!isProviderConfigured("gemini")) {
    return NextResponse.json({ error: "Missing Gemini API key." }, { status: 400 });
  }
  const parsed = generateRequestSchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  }
  try {
    const model = await getGeminiTtsModelSetting();
    const result = await createTtsGeneration(studioGenerateService(), {
      title: parsed.data.title,
      lines: parsed.data.lines,
      requestId: parsed.data.requestId,
      model,
    });
    return NextResponse.json({
      generation: publicGeneration(result.generation),
      reused: result.reused,
      model,
    });
  } catch (error) {
    return generateErrorResponse(error);
  }
}
