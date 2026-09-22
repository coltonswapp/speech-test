import { formatApiError } from "@/lib/api-error";
import type {
  CatalogKanji,
  CatalogWord,
  DeckKind,
  SlideshowDeck,
  SlideshowPhoto,
} from "./types";
import type { patchDeckSchema } from "./schemas";
import type { z } from "zod";

type PatchDeck = z.infer<typeof patchDeckSchema>;

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(path, init);
  if (!response.ok) {
    const body = await response.json().catch(() => null);
    throw new Error(formatApiError(body, response.status));
  }
  return response.json() as Promise<T>;
}

export const slidesApi = {
  listDecks: () => request<{ decks: SlideshowDeck[] }>("/api/content/slides"),
  getDeck: (id: string) =>
    request<{ deck: SlideshowDeck }>(`/api/content/slides/${id}`),
  createDeck: (body: {
    kind: DeckKind;
    subject: string;
    recipeId?: SlideshowDeck["recipeId"];
    exportSize?: SlideshowDeck["exportSize"];
    photoSet?: string;
  }) =>
    request<{ deck: SlideshowDeck }>("/api/content/slides", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    }),
  patchDeck: (id: string, body: PatchDeck) =>
    request<{ deck: SlideshowDeck }>(`/api/content/slides/${id}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    }),
  deleteDeck: (id: string) =>
    request<{ ok: true }>(`/api/content/slides/${id}`, { method: "DELETE" }),
  generateNext: (kind?: DeckKind) =>
    request<{ deck: SlideshowDeck }>("/api/content/slides/generate", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ kind }),
    }),
  catalog: (q = "") =>
    request<{ kanji: CatalogKanji[]; words: CatalogWord[] }>(
      `/api/content/slides/catalog?q=${encodeURIComponent(q)}`
    ),
  listPhotos: () =>
    request<{ photos: SlideshowPhoto[] }>("/api/content/slides/photos"),
  uploadPhotos: (files: File[], tags = "") => {
    const form = new FormData();
    for (const file of files) form.append("files", file);
    if (tags) form.append("tags", tags);
    return request<{ photos: SlideshowPhoto[] }>("/api/content/slides/photos", {
      method: "POST",
      body: form,
    });
  },
  patchPhoto: (id: string, body: { title?: string; tags?: string[] }) =>
    request<{ photo: SlideshowPhoto }>(`/api/content/slides/photos/${id}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    }),
  deletePhoto: (id: string) =>
    request<{ ok: true }>(`/api/content/slides/photos/${id}`, {
      method: "DELETE",
    }),
};
