import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { parseDialogueCollection } from "@/lib/tts/dialogue-import";
import { importDialogueScripts } from "@/lib/tts/import-dialogue-scripts";

export async function POST(request: NextRequest) {
  const formData = await request.formData();
  const file = formData.get("file");
  if (!(file instanceof File)) {
    return NextResponse.json({ error: "No file provided" }, { status: 400 });
  }

  const raw = await file.text();
  const collection = parseDialogueCollection(raw);
  if (collection.scripts.length === 0) {
    return NextResponse.json(
      { error: "No dialogue scenarios found in this file." },
      { status: 400 }
    );
  }

  try {
    const result = await importDialogueScripts(collection);
    return NextResponse.json(result, { status: 201 });
  } catch (error) {
    return NextResponse.json(
      {
        error:
          error instanceof Error ? error.message : "Failed to import dialogue.",
      },
      { status: 500 }
    );
  }
}
