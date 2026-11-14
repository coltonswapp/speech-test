import "server-only";
import {
  deleteObject,
  getObject,
  getSignedDownloadUrl,
  listChildPrefixes,
  objectExists,
  putObject,
} from "@/lib/storage/r2";
import {
  CLIP_ID_PATTERN,
  clipDraftSchema,
  clipIsAligned,
  clipIsTokenized,
  clipIsTranslated,
  clipHasHighlights,
  type ClipDraft,
  type ClipSummary,
} from "@/lib/experiments/clips/types";

const ROOT = "experiments/clips/";

export function clipAudioKey(id: string): string {
  return `${ROOT}${id}/clip.wav`;
}

function draftKey(id: string): string {
  return `${ROOT}${id}/draft.json`;
}

export function isValidClipId(id: string): boolean {
  return CLIP_ID_PATTERN.test(id) && id.length <= 64;
}

export async function clipExists(id: string): Promise<boolean> {
  return objectExists(draftKey(id));
}

export async function readClipDraft(id: string): Promise<ClipDraft | null> {
  if (!isValidClipId(id)) return null;
  if (!(await objectExists(draftKey(id)))) return null;
  const parsed = clipDraftSchema.safeParse(
    JSON.parse((await getObject(draftKey(id))).toString("utf8"))
  );
  if (!parsed.success) {
    throw new Error(`Clip draft ${id} is malformed: ${parsed.error.message}`);
  }
  return parsed.data;
}

export async function writeClipDraft(draft: ClipDraft): Promise<ClipDraft> {
  const next = { ...draft, updatedAt: new Date().toISOString() };
  await putObject(
    draftKey(draft.id),
    Buffer.from(JSON.stringify(next, null, 2)),
    "application/json"
  );
  return next;
}

export async function writeClipAudio(id: string, wav: Buffer): Promise<void> {
  await putObject(clipAudioKey(id), wav, "audio/wav");
}

/** Removes the draft and audio, freeing the id. Draft first so a half-done delete hides the clip. */
export async function deleteClip(id: string): Promise<void> {
  await deleteObject(draftKey(id));
  await deleteObject(clipAudioKey(id));
}

export async function clipAudioUrl(id: string, expiresInSeconds = 3600): Promise<string> {
  return getSignedDownloadUrl(clipAudioKey(id), expiresInSeconds);
}

/** Every readable draft, newest first. */
export async function listClipDrafts(): Promise<ClipDraft[]> {
  const prefixes = await listChildPrefixes(ROOT);
  const ids = prefixes
    .map((p) => p.slice(ROOT.length).replace(/\/$/, ""))
    .filter(isValidClipId);
  const drafts = await Promise.all(
    ids.map((id) => readClipDraft(id).catch(() => null))
  );
  return drafts
    .filter((d): d is ClipDraft => d !== null)
    .sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
}

export async function listClipSummaries(): Promise<ClipSummary[]> {
  return (await listClipDrafts()).map((d) => ({
    id: d.id,
    videoId: d.videoId,
    videoTitle: d.video?.title ?? null,
    channelName: d.video?.channelName ?? null,
    startSec: d.startSec,
    endSec: d.endSec,
    orientation: d.orientation ?? "landscape",
    sentenceCount: d.sentences.length,
    tokenized: clipIsTokenized(d),
    translated: clipIsTranslated(d),
    highlighted: clipHasHighlights(d),
    aligned: clipIsAligned(d),
    jlptLevel: d.difficulty?.jlptLevel ?? null,
    deprecated: Boolean(d.deprecated),
    updatedAt: d.updatedAt,
  }));
}
