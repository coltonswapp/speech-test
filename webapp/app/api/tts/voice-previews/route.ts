import { NextResponse } from "next/server";
import { db } from "@/lib/db/client";

export async function GET() {
  const previews = await db.query.voicePreview.findMany();
  return NextResponse.json({ previews });
}
