import "server-only";
import { PutObjectCommand, S3Client } from "@aws-sdk/client-s3";

function requiredEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`${name} is not set`);
  }
  return value;
}

let client: S3Client | undefined;

function getClient(): S3Client {
  if (client) return client;
  client = new S3Client({
    region: "auto",
    endpoint: requiredEnv("R2_ENDPOINT"),
    credentials: {
      accessKeyId: requiredEnv("R2_ACCESS_KEY_ID"),
      secretAccessKey: requiredEnv("R2_SECRET_ACCESS_KEY"),
    },
  });
  return client;
}

function getPublishedBucket(): string {
  return requiredEnv("R2_PUBLISHED_BUCKET_NAME");
}

/** Base URL for the public custom domain (no trailing slash). */
export function getPublishedPublicBaseUrl(): string {
  return requiredEnv("R2_PUBLISHED_PUBLIC_BASE_URL").replace(/\/+$/, "");
}

export function publishedObjectPublicUrl(objectKey: string): string {
  const encodedKey = objectKey
    .split("/")
    .map((segment) => encodeURIComponent(segment))
    .join("/");
  return `${getPublishedPublicBaseUrl()}/${encodedKey}`;
}

export function isPublishedR2Configured(): boolean {
  return !!(
    process.env.R2_PUBLISHED_BUCKET_NAME?.trim() &&
    process.env.R2_PUBLISHED_PUBLIC_BASE_URL?.trim() &&
    process.env.R2_ENDPOINT?.trim() &&
    process.env.R2_ACCESS_KEY_ID?.trim() &&
    process.env.R2_SECRET_ACCESS_KEY?.trim()
  );
}

/** Uploads a published learner asset to the public R2 bucket. */
export async function putPublishedObject(
  key: string,
  body: Buffer | Uint8Array,
  contentType: string
): Promise<void> {
  await getClient().send(
    new PutObjectCommand({
      Bucket: getPublishedBucket(),
      Key: key,
      Body: body,
      ContentType: contentType,
      CacheControl: "public, max-age=31536000, immutable",
    })
  );
}
