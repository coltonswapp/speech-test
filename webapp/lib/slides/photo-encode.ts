import sharp from "sharp";
import { putObject } from "@/lib/storage/r2";

const MAX_BYTES = 12 * 1024 * 1024;

export async function encodeSlideshowPhoto(bytes: Buffer): Promise<{
  full: Buffer;
  thumb: Buffer;
  width: number;
  height: number;
}> {
  const image = sharp(bytes).rotate();
  const [full, thumb, meta] = await Promise.all([
    image
      .clone()
      .resize({
        width: 1800,
        height: 1800,
        fit: "inside",
        withoutEnlargement: true,
      })
      .webp({ quality: 82 })
      .toBuffer(),
    image
      .clone()
      .resize({
        width: 512,
        height: 512,
        fit: "inside",
        withoutEnlargement: true,
      })
      .webp({ quality: 80 })
      .toBuffer(),
    image.metadata(),
  ]);
  return {
    full,
    thumb,
    width: meta.width ?? 0,
    height: meta.height ?? 0,
  };
}

export function photoTooLarge(byteCount: number): boolean {
  return byteCount > MAX_BYTES;
}

export async function storeSlideshowPhotoFiles(id: string, bytes: Buffer) {
  const encoded = await encodeSlideshowPhoto(bytes);
  const objectKey = `slides/photos/${id}.webp`;
  const thumbObjectKey = `slides/photos/${id}-512.webp`;
  await Promise.all([
    putObject(objectKey, encoded.full, "image/webp"),
    putObject(thumbObjectKey, encoded.thumb, "image/webp"),
  ]);
  return {
    objectKey,
    thumbObjectKey,
    byteCount: encoded.full.length,
    width: encoded.width,
    height: encoded.height,
  };
}
