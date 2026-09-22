import { desc, eq } from "drizzle-orm";
import { db } from "@/lib/db/client";
import { appSettings, slideshowDeck, slideshowPhoto } from "@/lib/db/schema";
import { SLIDE_CATALOG } from "./catalog";
import { makeDecompositionPayload, makeSpotlightPayload } from "./payload";
import { defaultRecipeId } from "./recipes";
import { newPhotoSeed } from "./scatter";
import type {
  DeckKind,
  DeckPayload,
  SlideshowDeck,
  SlideshowPhoto,
} from "./types";
import {
  DECK_KINDS,
  DECK_STATUSES,
  EXPORT_SIZE_IDS,
  RECIPE_IDS,
} from "./types";

const LAST_PART_KEY = "slideshow-decomp-last-part";

function iso(value: Date | string): string {
  return value instanceof Date ? value.toISOString() : value;
}

function asKind(value: string): DeckKind {
  return DECK_KINDS.includes(value as DeckKind) ? (value as DeckKind) : "spotlight";
}

export function serializePhoto(row: typeof slideshowPhoto.$inferSelect): SlideshowPhoto {
  return {
    id: row.id,
    createdAt: iso(row.createdAt),
    updatedAt: iso(row.updatedAt),
    title: row.title,
    tags: row.tags ?? [],
    objectKey: row.objectKey,
    thumbObjectKey: row.thumbObjectKey,
    contentType: row.contentType,
    byteCount: row.byteCount,
    width: row.width,
    height: row.height,
  };
}

export function serializeDeck(row: typeof slideshowDeck.$inferSelect): SlideshowDeck {
  const kind = asKind(row.kind);
  return {
    id: row.id,
    createdAt: iso(row.createdAt),
    updatedAt: iso(row.updatedAt),
    kind,
    status: DECK_STATUSES.includes(row.status as SlideshowDeck["status"])
      ? (row.status as SlideshowDeck["status"])
      : "draft",
    usedSubject: row.usedSubject,
    recipeId: RECIPE_IDS.includes(row.recipeId as SlideshowDeck["recipeId"])
      ? (row.recipeId as SlideshowDeck["recipeId"])
      : "studio-light",
    exportSize: EXPORT_SIZE_IDS.includes(row.exportSize as SlideshowDeck["exportSize"])
      ? (row.exportSize as SlideshowDeck["exportSize"])
      : "story",
    photoSet: row.photoSet,
    photoSeed: row.photoSeed,
    payload: row.payload as DeckPayload,
  };
}

export async function countPhotos(): Promise<number> {
  const rows = await db.query.slideshowPhoto.findMany({
    columns: { id: true },
  });
  return rows.length;
}

export async function getLastDecompositionPart(): Promise<number> {
  const row = await db.query.appSettings.findFirst({
    where: eq(appSettings.key, LAST_PART_KEY),
  });
  const value = row?.value;
  if (typeof value === "number") return value;
  if (value && typeof value === "object" && "part" in value) {
    const part = Number((value as { part?: unknown }).part);
    return Number.isFinite(part) ? part : 0;
  }
  return 0;
}

export async function setLastDecompositionPart(part: number): Promise<void> {
  await db
    .insert(appSettings)
    .values({ key: LAST_PART_KEY, value: { part } })
    .onConflictDoUpdate({
      target: appSettings.key,
      set: { value: { part } },
    });
}

export async function usedSubjects(kind: DeckKind): Promise<Set<string>> {
  const rows = await db.query.slideshowDeck.findMany({
    columns: { usedSubject: true, kind: true },
  });
  return new Set(
    rows.filter((row) => row.kind === kind).map((row) => row.usedSubject)
  );
}

export function nextUnusedKanji(used: Set<string>): string | null {
  return SLIDE_CATALOG.kanji.find((row) => !used.has(row.character))?.character ?? null;
}

export function nextUnusedWord(used: Set<string>): string | null {
  return SLIDE_CATALOG.words.find((row) => !used.has(row.expression))?.expression ?? null;
}

export async function createDeckFromSubject(params: {
  kind: DeckKind;
  subject: string;
  recipeId?: SlideshowDeck["recipeId"];
  exportSize?: SlideshowDeck["exportSize"];
  photoSet?: string;
}): Promise<SlideshowDeck> {
  const photoCount = await countPhotos();
  const recipeId = params.recipeId ?? defaultRecipeId(photoCount);
  let payload: DeckPayload | null = null;
  if (params.kind === "spotlight") {
    payload = makeSpotlightPayload(params.subject);
  } else {
    payload = makeDecompositionPayload(
      params.subject,
      await getLastDecompositionPart()
    );
  }
  if (!payload) {
    throw new Error(
      params.kind === "spotlight"
        ? `Unknown kanji “${params.subject}”.`
        : `Unknown word “${params.subject}”.`
    );
  }

  const [row] = await db
    .insert(slideshowDeck)
    .values({
      kind: params.kind,
      status: "draft",
      usedSubject: params.subject,
      recipeId,
      exportSize: params.exportSize ?? "story",
      photoSet: params.photoSet ?? "all",
      photoSeed: newPhotoSeed(),
      payload,
    })
    .returning();
  return serializeDeck(row);
}

export async function generateNextDraft(
  kind: DeckKind
): Promise<{ deck: SlideshowDeck } | { skipped: true; reason: string }> {
  const used = await usedSubjects(kind);
  const subject =
    kind === "spotlight" ? nextUnusedKanji(used) : nextUnusedWord(used);
  if (!subject) {
    return {
      skipped: true,
      reason:
        kind === "spotlight"
          ? "Every catalog kanji already has a deck."
          : "Every catalog word already has a deck.",
    };
  }
  const deck = await createDeckFromSubject({ kind, subject });
  return { deck };
}

export async function listDecksNewestFirst() {
  const rows = await db.query.slideshowDeck.findMany({
    orderBy: [desc(slideshowDeck.createdAt)],
  });
  return rows.map(serializeDeck);
}
