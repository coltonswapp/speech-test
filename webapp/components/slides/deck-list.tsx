"use client";

import { useState } from "react";
import Link from "next/link";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { Images, Plus, Sparkles, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { slidesApi } from "@/lib/slides/client";
import type { CatalogKanji, CatalogWord, DeckKind } from "@/lib/slides/types";
import { cn } from "@/lib/utils";

export function DeckList() {
  const queryClient = useQueryClient();
  const decksQuery = useQuery({
    queryKey: ["slide-decks"],
    queryFn: () => slidesApi.listDecks(),
  });
  const generate = useMutation({
    mutationFn: (kind: DeckKind) => slidesApi.generateNext(kind),
    onSuccess: (result) => {
      queryClient.invalidateQueries({ queryKey: ["slide-decks"] });
      toast.success(`Drafted ${result.deck.usedSubject}.`);
    },
    onError: (error) => toast.error(error.message),
  });
  const remove = useMutation({
    mutationFn: (id: string) => slidesApi.deleteDeck(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["slide-decks"] });
      toast.success("Deck deleted.");
    },
    onError: (error) => toast.error(error.message),
  });

  const decks = decksQuery.data?.decks ?? [];

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Slides</h1>
          <p className="text-sm text-muted-foreground">
            Kanji spotlight and decomposition decks, recipes, Japan photo
            backgrounds, and PNG export.
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Button
            variant="outline"
            onClick={() => generate.mutate("spotlight")}
            disabled={generate.isPending}
          >
            <Sparkles />
            Generate spotlight
          </Button>
          <Button
            variant="outline"
            onClick={() => generate.mutate("decomposition")}
            disabled={generate.isPending}
          >
            <Sparkles />
            Generate decomposition
          </Button>
          <Link href="/slides/photos">
            <Button variant="outline">
              <Images />
              Photos
            </Button>
          </Link>
        </div>
      </div>

      <NewDeckForm
        onCreated={() => queryClient.invalidateQueries({ queryKey: ["slide-decks"] })}
      />

      {decksQuery.isLoading ? (
        <p className="text-sm text-muted-foreground">Loading decks…</p>
      ) : decks.length === 0 ? (
        <p className="text-sm text-muted-foreground">
          No decks yet. Generate the next catalog subject, or pick one below.
        </p>
      ) : (
        <ul className="divide-y divide-border/60 rounded-xl border border-border/60">
          {decks.map((deck) => (
            <li
              key={deck.id}
              className="flex items-center gap-3 px-3 py-2.5"
            >
              <Link
                href={`/slides/${deck.id}`}
                className="min-w-0 flex-1 hover:underline"
              >
                <div className="font-medium">{deck.usedSubject}</div>
                <div className="text-xs text-muted-foreground">
                  {deck.kind} · {deck.status} · {deck.recipeId} · {deck.exportSize}
                </div>
              </Link>
              <Button
                variant="ghost"
                size="icon"
                aria-label="Delete deck"
                onClick={() => remove.mutate(deck.id)}
              >
                <Trash2 className="size-4" />
              </Button>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

function NewDeckForm({ onCreated }: { onCreated: () => void }) {
  const [kind, setKind] = useState<DeckKind>("spotlight");
  const [query, setQuery] = useState("");
  const catalogQuery = useQuery({
    queryKey: ["slide-catalog", query],
    queryFn: () => slidesApi.catalog(query),
  });
  const create = useMutation({
    mutationFn: (subject: string) => slidesApi.createDeck({ kind, subject }),
    onSuccess: (result) => {
      toast.success(`Created ${result.deck.usedSubject}.`);
      onCreated();
    },
    onError: (error) => toast.error(error.message),
  });

  const kanji = catalogQuery.data?.kanji ?? [];
  const words = catalogQuery.data?.words ?? [];

  return (
    <div className="rounded-xl border border-border/60 p-4">
      <div className="mb-3 flex gap-2">
        <Button
          size="sm"
          variant={kind === "spotlight" ? "default" : "outline"}
          onClick={() => setKind("spotlight")}
        >
          Spotlight
        </Button>
        <Button
          size="sm"
          variant={kind === "decomposition" ? "default" : "outline"}
          onClick={() => setKind("decomposition")}
        >
          Decomposition
        </Button>
      </div>
      <Label htmlFor="catalog-search">Pick a {kind === "spotlight" ? "kanji" : "word"}</Label>
      <Input
        id="catalog-search"
        className="mt-1 max-w-md"
        placeholder={kind === "spotlight" ? "Search kanji, meaning, reading…" : "Search compounds…"}
        value={query}
        onChange={(event) => setQuery(event.target.value)}
      />
      <div className="mt-3 grid max-h-64 gap-1 overflow-auto sm:grid-cols-2">
        {kind === "spotlight"
          ? kanji.slice(0, 24).map((entry) => (
              <CatalogKanjiRow
                key={entry.character}
                entry={entry}
                disabled={create.isPending}
                onPick={() => create.mutate(entry.character)}
              />
            ))
          : words.slice(0, 24).map((entry) => (
              <CatalogWordRow
                key={entry.expression}
                entry={entry}
                disabled={create.isPending}
                onPick={() => create.mutate(entry.expression)}
              />
            ))}
      </div>
    </div>
  );
}

function CatalogKanjiRow({
  entry,
  disabled,
  onPick,
}: {
  entry: CatalogKanji;
  disabled: boolean;
  onPick: () => void;
}) {
  return (
    <button
      type="button"
      disabled={disabled}
      onClick={onPick}
      className={cn(
        "flex items-center gap-2 rounded-md px-2 py-1.5 text-left text-sm hover:bg-muted disabled:opacity-50"
      )}
    >
      <span className="text-lg font-medium">{entry.character}</span>
      <span className="min-w-0 truncate text-muted-foreground">
        {entry.meanings.slice(0, 3).join(", ")}
      </span>
      <Plus className="ml-auto size-3.5 shrink-0 text-muted-foreground" />
    </button>
  );
}

function CatalogWordRow({
  entry,
  disabled,
  onPick,
}: {
  entry: CatalogWord;
  disabled: boolean;
  onPick: () => void;
}) {
  return (
    <button
      type="button"
      disabled={disabled}
      onClick={onPick}
      className="flex items-center gap-2 rounded-md px-2 py-1.5 text-left text-sm hover:bg-muted disabled:opacity-50"
    >
      <span className="font-medium">{entry.expression}</span>
      <span className="min-w-0 truncate text-muted-foreground">{entry.gloss}</span>
      <Plus className="ml-auto size-3.5 shrink-0 text-muted-foreground" />
    </button>
  );
}
