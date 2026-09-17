import { createHash, randomBytes } from "crypto";
import sharp from "sharp";
import {
  publishedObjectPublicUrl,
  putPublishedObject,
} from "@/lib/storage/published-r2-core";

export async function makeThumbnailVariants(bytes: Buffer): Promise<{
  full: { buffer: Buffer; keySuffix: string };
  small: { buffer: Buffer; keySuffix: string };
}> {
  const image = sharp(bytes).rotate();
  const [full, small] = await Promise.all([
    image
      .clone()
      .resize({
        width: 1600,
        height: 1600,
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
      .webp({ quality: 82 })
      .toBuffer(),
  ]);
  return {
    full: { buffer: full, keySuffix: ".webp" },
    small: { buffer: small, keySuffix: "-512.webp" },
  };
}

export async function publishThumbnail(
  objectKeyBase: string,
  bytes: Buffer
): Promise<{
  thumbnailUrl: string;
  thumbnailSmallUrl: string;
  objectKey: string;
}> {
  const variants = await makeThumbnailVariants(bytes);
  const hash = createHash("sha256")
    .update(bytes)
    .update(randomBytes(4))
    .digest("hex")
    .slice(0, 12);
  const objectKey = `${objectKeyBase}-${hash}${variants.full.keySuffix}`;
  const smallObjectKey = `${objectKeyBase}-${hash}${variants.small.keySuffix}`;
  await Promise.all([
    putPublishedObject(objectKey, variants.full.buffer, "image/webp"),
    putPublishedObject(smallObjectKey, variants.small.buffer, "image/webp"),
  ]);
  return {
    thumbnailUrl: publishedObjectPublicUrl(objectKey),
    thumbnailSmallUrl: publishedObjectPublicUrl(smallObjectKey),
    objectKey,
  };
}
