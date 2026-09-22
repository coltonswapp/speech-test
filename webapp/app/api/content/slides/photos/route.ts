import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { desc } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { slideshowPhoto } from "@/lib/db/schema";
import { photoTooLarge, storeSlideshowPhotoFiles } from "@/lib/slides/photo-encode";
import { serializePhoto } from "@/lib/slides/store";

const ALLOWED_TYPES = new Set([
  "image/jpeg",
  "image/jpg",
  "image/png",
  "image/webp",
  "image/heic",
  "image/heif",
]);

export async function GET() {
  const rows = await db.query.slideshowPhoto.findMany({
    orderBy: [desc(slideshowPhoto.createdAt)],
  });
  return NextResponse.json({ photos: rows.map(serializePhoto) });
}

export async function POST(request: NextRequest) {
  const formData = await request.formData();
  const files = formData.getAll("files").filter((value) => value instanceof File);
  const fallback = formData.get("file");
  if (fallback instanceof File) files.push(fallback);
  const tagRaw = String(formData.get("tags") ?? "").trim();
  const tags = tagRaw
    ? tagRaw
        .split(",")
        .map((tag) => tag.trim().toLowerCase())
        .filter(Boolean)
    : [];

  if (files.length === 0) {
    return NextResponse.json({ error: "Choose one or more photos." }, { status: 400 });
  }

  const photos = [];
  for (const file of files) {
    if (photoTooLarge(file.size)) {
      return NextResponse.json(
        { error: `${file.name} is larger than 12 MB.` },
        { status: 400 }
      );
    }
    const type = (file.type || "").toLowerCase();
    const nameExt = file.name.split(".").pop()?.toLowerCase() ?? "";
    const okType =
      ALLOWED_TYPES.has(type) ||
      ["jpg", "jpeg", "png", "webp", "heic", "heif"].includes(nameExt);
    if (!okType) {
      return NextResponse.json(
        { error: `${file.name} is not a JPEG, PNG, WebP, or HEIC photo.` },
        { status: 400 }
      );
    }
    const id = crypto.randomUUID();
    const bytes = Buffer.from(await file.arrayBuffer());
    let stored;
    try {
      stored = await storeSlideshowPhotoFiles(id, bytes);
    } catch {
      return NextResponse.json(
        { error: `Could not read ${file.name}.` },
        { status: 400 }
      );
    }
    const title = file.name.replace(/\.[^.]+$/, "") || "Untitled";
    const [row] = await db
      .insert(slideshowPhoto)
      .values({
        id,
        title,
        tags,
        objectKey: stored.objectKey,
        thumbObjectKey: stored.thumbObjectKey,
        contentType: "image/webp",
        byteCount: stored.byteCount,
        width: stored.width,
        height: stored.height,
      })
      .returning();
    photos.push(serializePhoto(row));
  }

  return NextResponse.json({ photos });
}
