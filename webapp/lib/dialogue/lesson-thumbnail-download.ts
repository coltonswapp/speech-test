import "server-only";
import JSZip from "jszip";
import type { LessonThumbnailItem } from "@/lib/dialogue/lesson-thumbnails";

const MAX_BYTES = 8 * 1024 * 1024;

export function contentDispositionAttachment(filename: string): string {
  const ascii = filename.replace(/[^\x20-\x7E]/g, "_").replace(/"/g, "");
  return `attachment; filename="${ascii}"; filename*=UTF-8''${encodeURIComponent(filename)}`;
}

export function extensionForThumbnail(
  contentType: string,
  fallbackUrl?: string | null
): string {
  const type = contentType.split(";")[0]?.trim().toLowerCase();
  switch (type) {
    case "image/jpeg":
    case "image/jpg":
      return "jpg";
    case "image/png":
      return "png";
    case "image/gif":
      return "gif";
    case "image/webp":
      return "webp";
    default: {
      const match = fallbackUrl?.match(/\.([a-zA-Z0-9]{2,5})(?:\?|$)/);
      return match?.[1]?.toLowerCase() ?? "webp";
    }
  }
}

export async function fetchRemoteThumbnail(url: string): Promise<{
  bytes: Buffer;
  contentType: string;
}> {
  if (!/^https?:\/\//i.test(url)) {
    throw new Error("Thumbnail URL must be http(s).");
  }
  const res = await fetch(url, { redirect: "follow" });
  if (!res.ok) {
    throw new Error(`Thumbnail fetch failed (${res.status})`);
  }
  const contentType =
    res.headers.get("content-type") || "application/octet-stream";
  const bytes = Buffer.from(await res.arrayBuffer());
  if (bytes.length > MAX_BYTES) {
    throw new Error("Thumbnail is larger than 8 MB");
  }
  return { bytes, contentType };
}

export async function zipLessonThumbnails(
  items: LessonThumbnailItem[]
): Promise<{ buffer: Buffer; count: number } | null> {
  const downloadable = items.filter((item) => item.thumbnailUrl);
  if (downloadable.length === 0) return null;

  const zip = new JSZip();
  const cache = new Map<string, { bytes: Buffer; contentType: string }>();
  let count = 0;

  for (const item of downloadable) {
    const url = item.thumbnailUrl;
    if (!url) continue;
    let fetched = cache.get(url);
    if (!fetched) {
      try {
        fetched = await fetchRemoteThumbnail(url);
        cache.set(url, fetched);
      } catch {
        continue;
      }
    }
    const ext = extensionForThumbnail(fetched.contentType, url);
    zip.file(`${item.filenameBase}.${ext}`, fetched.bytes);
    count += 1;
  }

  if (count === 0) return null;
  const buffer = await zip.generateAsync({ type: "nodebuffer" });
  return { buffer, count };
}
