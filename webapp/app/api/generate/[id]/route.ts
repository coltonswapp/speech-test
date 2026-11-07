import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import {
  deleteGeneration,
  publicGeneration,
  renameGeneration,
  requireReadyGeneration,
  saveGeneration,
} from "@/lib/generate/service";
import { generatePatchSchema } from "@/lib/generate/types";
import { studioGenerateService } from "@/lib/generate/runtime";
import { generateErrorResponse, requireGenerateAccess } from "@/lib/generate/http";

type Ctx = RouteContext<"/api/generate/[id]">;

export async function GET(request: NextRequest, ctx: Ctx) {
  const denied = await requireGenerateAccess(request);
  if (denied) return denied;
  try {
    const { id } = await ctx.params;
    const row = await requireReadyGeneration(studioGenerateService(), id);
    return NextResponse.json({ generation: publicGeneration(row) });
  } catch (error) {
    return generateErrorResponse(error);
  }
}

export async function PATCH(request: NextRequest, ctx: Ctx) {
  const denied = await requireGenerateAccess(request);
  if (denied) return denied;
  const parsed = generatePatchSchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  }
  try {
    const { id } = await ctx.params;
    const svc = studioGenerateService();
    let row;
    if (parsed.data.saved === true) {
      row = await saveGeneration(svc, id);
      if (parsed.data.title) {
        row = await renameGeneration(svc, id, parsed.data.title);
      }
    } else {
      row = parsed.data.title
        ? await renameGeneration(svc, id, parsed.data.title)
        : await requireReadyGeneration(svc, id);
    }
    return NextResponse.json({ generation: publicGeneration(row) });
  } catch (error) {
    return generateErrorResponse(error);
  }
}

export async function DELETE(request: NextRequest, ctx: Ctx) {
  const denied = await requireGenerateAccess(request);
  if (denied) return denied;
  try {
    const { id } = await ctx.params;
    await deleteGeneration(studioGenerateService(), id);
    return NextResponse.json({ ok: true });
  } catch (error) {
    return generateErrorResponse(error);
  }
}
