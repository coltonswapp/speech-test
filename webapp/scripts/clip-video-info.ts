// Refreshes clips' video info (title, channel, English title) through Studio's
// Refresh route, so drafts and the clip index update exactly as the button does.
//
//   pnpm clip:video-info            # dry run: which clips would be refreshed
//   pnpm clip:video-info --write    # refresh clips with a Japanese title and no English one
//   pnpm clip:video-info --write --all       # every clip (re-checks titles and channels)
//   pnpm clip:video-info --write --ids a,b
//
// Studio is CLIP_STUDIO_URL or --studio (default http://localhost:3000). A
// failure naming a 404/422 means YouTube no longer has the video (deleted,
// private or not embeddable): consider deprecating those clips.
import { GetObjectCommand, ListObjectsV2Command, S3Client } from "@aws-sdk/client-s3";
import { clipDraftSchema, type ClipDraft } from "../lib/experiments/clips/types";
import { titleNeedsTranslation } from "../lib/experiments/clips/video-title";

const ROOT = "experiments/clips/";
const CONCURRENCY = 4;

const args = process.argv.slice(2);
const flag = (name: string) => args.includes(name);
const option = (name: string) => {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : undefined;
};

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

const STUDIO = (option("--studio") ?? process.env.CLIP_STUDIO_URL ?? "http://localhost:3000").replace(/\/$/, "");
const studioHeaders: Record<string, string> = { "Content-Type": "application/json" };
const agentToken = process.env.STUDIO_AGENT_TOKEN?.trim();
if (agentToken) studioHeaders.Authorization = `Bearer ${agentToken}`;

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
    return parsed.success ? parsed.data : null;
  } catch (error) {
    if ((error as { name?: string }).name === "NoSuchKey") return null;
    throw error;
  }
}

async function main() {
  const write = flag("--write");
  const only = option("--ids")?.split(",").map((s) => s.trim()).filter(Boolean);
  const ids = only ?? (await listDraftIds());
  const drafts: ClipDraft[] = [];
  for (let i = 0; i < ids.length; i += 20) {
    const batch = await Promise.all(ids.slice(i, i + 20).map(readDraft));
    drafts.push(...batch.filter((d): d is ClipDraft => d !== null));
  }
  const picked = drafts.filter(
    (d) => only || flag("--all") || !d.video || (!d.video.titleEn && titleNeedsTranslation(d.video.title))
  );
  console.log(
    `${drafts.length} drafts; ${picked.length} to refresh${write ? ` through ${STUDIO}` : " (dry run; add --write)"}.`
  );
  if (!write) {
    for (const d of picked) console.log(`  ${d.id}: ${d.video?.title ?? "(no video info)"}`);
    process.exit(0);
  }

  let next = 0;
  let failed = 0;
  await Promise.all(
    Array.from({ length: CONCURRENCY }, async () => {
      while (next < picked.length) {
        const draft = picked[next++];
        try {
          const response = await fetch(`${STUDIO}/api/experiments/clips/${draft.id}/video-info`, {
            method: "POST",
            headers: studioHeaders,
            signal: AbortSignal.timeout(60_000),
          });
          const body = await response.json().catch(() => null);
          if (!response.ok) throw new Error(`HTTP ${response.status}: ${body?.error ?? ""}`);
          const video = (body.draft as ClipDraft).video;
          console.log(`  ${draft.id}: ${video?.title}\n    → ${video?.titleEn?.text ?? "(no English title)"}`);
        } catch (error) {
          failed++;
          console.log(`  ✗ ${draft.id}: ${(error as Error).message}`);
        }
      }
    })
  );
  console.log(`\nRefreshed ${picked.length - failed}/${picked.length}.`);
  process.exit(failed > 0 ? 1 : 0);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
