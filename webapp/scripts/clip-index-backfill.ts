// Rebuilds the clip index (`clip_index` in lib/db/schema.ts) from the drafts
// in R2, creating the table if it isn't there yet.
//
//   pnpm clip:index-backfill           # dry run: what would change
//   pnpm clip:index-backfill --write   # create the table, upsert every draft, drop rows with no draft
//
// Run it once to fill the index, and again after changing a feed rule
// threshold (lib/experiments/clips/feed.ts): the index stores each clip's
// verdict, so it only picks up a new threshold when the clip is re-saved.
//
// --write also stamps `listedAt` on listed drafts from before the field (their
// alignment time; see clipListedAt), so a later re-align can't move them up
// the app's list. Their updatedAt is left alone.
import { GetObjectCommand, ListObjectsV2Command, PutObjectCommand, S3Client } from "@aws-sdk/client-s3";
import { inArray, sql } from "drizzle-orm";
import { db } from "../lib/db/standalone-client";
import { clipIndex } from "../lib/db/schema";
import { clipDraftSchema, clipListedAt, type ClipDraft } from "../lib/experiments/clips/types";
import { CLIP_INDEX_DDL, clipIndexRow } from "../lib/experiments/clips/summary";

const ROOT = "experiments/clips/";

function env(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing ${name} in .env.local`);
  return value;
}

const s3 = new S3Client({
  region: "auto",
  endpoint: process.env.R2_ENDPOINT?.trim() || `https://${env("R2_ACCOUNT_ID")}.r2.cloudflarestorage.com`,
  credentials: { accessKeyId: env("R2_ACCESS_KEY_ID"), secretAccessKey: env("R2_SECRET_ACCESS_KEY") },
});
const bucket = env("R2_BUCKET_NAME");

async function listDraftIds(): Promise<string[]> {
  const ids: string[] = [];
  let token: string | undefined;
  do {
    const out = await s3.send(
      new ListObjectsV2Command({ Bucket: bucket, Prefix: ROOT, Delimiter: "/", ContinuationToken: token })
    );
    for (const p of out.CommonPrefixes ?? []) {
      const id = p.Prefix?.slice(ROOT.length).replace(/\/$/, "");
      if (id) ids.push(id);
    }
    token = out.IsTruncated ? out.NextContinuationToken : undefined;
  } while (token);
  return ids;
}

async function readDraft(id: string): Promise<ClipDraft | null> {
  try {
    const out = await s3.send(new GetObjectCommand({ Bucket: bucket, Key: `${ROOT}${id}/draft.json` }));
    const parsed = clipDraftSchema.safeParse(JSON.parse(await out.Body!.transformToString("utf8")));
    if (!parsed.success) {
      console.warn(`  ${id}: draft doesn't parse, skipped (${parsed.error.issues[0]?.message})`);
      return null;
    }
    return parsed.data;
  } catch (error) {
    if ((error as { name?: string }).name === "NoSuchKey") return null;
    throw error;
  }
}

async function main() {
  const write = process.argv.includes("--write");
  const ids = await listDraftIds();
  const drafts: ClipDraft[] = [];
  for (let i = 0; i < ids.length; i += 20) {
    const batch = await Promise.all(ids.slice(i, i + 20).map(readDraft));
    drafts.push(...batch.filter((d): d is ClipDraft => d !== null));
  }
  const rows = drafts.map(clipIndexRow);
  const unstamped = drafts.filter((d) => !d.listedAt && clipListedAt(d));
  console.log(
    `${drafts.length} drafts in R2: ${rows.filter((r) => r.listed).length} listed, ${rows.filter((r) => r.inFeed).length} in the feed; ${unstamped.length} listed without listedAt.`
  );
  if (!write) {
    console.log("Dry run. Add --write to create the table and fill it.");
    process.exit(0);
  }

  for (const draft of unstamped) {
    // Added to the stored JSON as is, so nothing the schema would drop is lost.
    const key = `${ROOT}${draft.id}/draft.json`;
    const out = await s3.send(new GetObjectCommand({ Bucket: bucket, Key: key }));
    const stored = JSON.parse(await out.Body!.transformToString("utf8"));
    await s3.send(
      new PutObjectCommand({
        Bucket: bucket,
        Key: key,
        Body: JSON.stringify({ ...stored, listedAt: clipListedAt(draft) }, null, 2),
        ContentType: "application/json",
      })
    );
  }
  if (unstamped.length > 0) console.log(`Stamped listedAt on ${unstamped.length} drafts.`);

  await db.execute(sql.raw(CLIP_INDEX_DDL));
  for (const row of rows) {
    await db
      .insert(clipIndex)
      .values(row)
      .onConflictDoUpdate({ target: clipIndex.id, set: { ...row, id: undefined } });
  }
  const indexed = await db.select({ id: clipIndex.id }).from(clipIndex);
  const live = new Set(rows.map((r) => r.id));
  const stale = indexed.map((r) => r.id).filter((id) => !live.has(id));
  if (stale.length > 0) await db.delete(clipIndex).where(inArray(clipIndex.id, stale));
  console.log(`Upserted ${rows.length}; removed ${stale.length} rows with no draft.`);
  process.exit(0);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
