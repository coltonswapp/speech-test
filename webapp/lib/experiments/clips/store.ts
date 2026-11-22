import "server-only";
import {
  deleteObject,
  getObject,
  getSignedDownloadUrl,
  getSignedUploadUrl,
  listChildPrefixes,
  objectExists,
  putObject,
} from "@/lib/storage/r2";
import {
  CLIP_ID_PATTERN,
  clipDraftSchema,
  clipListedAt,
  clipPendingSchema,
  type ClipDraft,
  type ClipPending,
  type ClipSummary,
} from "@/lib/experiments/clips/types";
import { deleteClipIndex, listIndexedClipSummaries, upsertClipIndex } from "@/lib/experiments/clips/clip-index";

const ROOT = "experiments/clips/";
// Pending clips (details entered, audio not uploaded yet) and the audio the
// script uploads for them sit under their own root, so listing clips never
// has to look at them and nothing here can be mistaken for a clip.
const PENDING_ROOT = "experiments/clip-uploads/";

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
  const now = new Date().toISOString();
  const listedAt = clipListedAt({ ...draft, updatedAt: now });
  const next = { ...draft, ...(listedAt ? { listedAt } : {}), updatedAt: now };
  await putObject(
    draftKey(draft.id),
    Buffer.from(JSON.stringify(next, null, 2)),
    "application/json"
  );
  // Lists and token search read the indexes, so a draft saved without them
  // would be invisible there; let the error surface (the draft itself is
  // saved, so retrying is safe). Token rows are rebuilt inside upsertClipIndex.
  await upsertClipIndex(next);
  return next;
}

export async function readClipAudio(id: string): Promise<Buffer | null> {
  if (!isValidClipId(id) || !(await objectExists(clipAudioKey(id)))) return null;
  return getObject(clipAudioKey(id));
}

export async function writeClipAudio(id: string, wav: Buffer): Promise<void> {
  await putObject(clipAudioKey(id), wav, "audio/wav");
}

/** Removes the draft and audio, freeing the id. Draft first so a half-done delete hides the clip. */
export async function deleteClip(id: string): Promise<void> {
  await deleteObject(draftKey(id));
  await deleteClipIndex(id);
  await deleteObject(clipAudioKey(id));
}

function pendingKey(id: string): string {
  return `${PENDING_ROOT}${id}/pending.json`;
}

export async function readClipPending(id: string): Promise<ClipPending | null> {
  if (!isValidClipId(id)) return null;
  if (!(await objectExists(pendingKey(id)))) return null;
  const parsed = clipPendingSchema.safeParse(
    JSON.parse((await getObject(pendingKey(id))).toString("utf8"))
  );
  return parsed.success ? parsed.data : null;
}

export async function writeClipPending(pending: ClipPending): Promise<void> {
  await putObject(
    pendingKey(pending.id),
    Buffer.from(JSON.stringify(pending, null, 2)),
    "application/json"
  );
}

function uploadAudioKey(id: string): string {
  return `${PENDING_ROOT}${id}/source.wav`;
}

/** Removes the pending record and any audio uploaded for it. Clips made from it are untouched. */
export async function discardClipPending(id: string): Promise<void> {
  await deleteObject(pendingKey(id));
  await deleteObject(uploadAudioKey(id));
}

/** Oldest first. */
export async function listClipPendings(): Promise<ClipPending[]> {
  const prefixes = await listChildPrefixes(PENDING_ROOT);
  const ids = prefixes
    .map((p) => p.slice(PENDING_ROOT.length).replace(/\/$/, ""))
    .filter(isValidClipId);
  const found = await Promise.all(ids.map((id) => readClipPending(id).catch(() => null)));
  return found
    .filter((p): p is ClipPending => p !== null)
    .sort((a, b) => a.createdAt.localeCompare(b.createdAt));
}

/** Signed PUT for the WAV the script uploads for a pending clip. */
export async function clipUploadAudioUrl(id: string, expiresInSeconds = 900): Promise<string> {
  return getSignedUploadUrl(uploadAudioKey(id), "audio/wav", expiresInSeconds);
}

/** The WAV the script uploaded, or null when nothing has been uploaded yet. */
export async function readClipUploadAudio(id: string): Promise<Buffer | null> {
  if (!(await objectExists(uploadAudioKey(id)))) return null;
  return getObject(uploadAudioKey(id));
}

export async function deleteClipUploadAudio(id: string): Promise<void> {
  await deleteObject(uploadAudioKey(id));
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

/** Studio's clip list, from the index (one query, not one read per draft). */
export async function listClipSummaries(): Promise<ClipSummary[]> {
  return listIndexedClipSummaries();
}
