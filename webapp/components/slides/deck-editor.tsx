"use client";

import { useMemo, useRef, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import Link from "next/link";
import {
  ChevronLeft,
  ChevronRight,
  Copy,
  Download,
  Images,
  Shuffle,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { slidesApi } from "@/lib/slides/client";
import { findKanji } from "@/lib/slides/catalog";
import { formatHashtagLine, INTRO_TITLE_PRESETS, RECOMMENDED_HASHTAGS } from "@/lib/slides/hashtags";
import { HIGHLIGHT_COLORS } from "@/lib/slides/highlights";
import { RECIPE_LIST } from "@/lib/slides/recipes";
import { slidesForDeck, slideFileName } from "@/lib/slides/render-slides";
import { newPhotoSeed } from "@/lib/slides/scatter";
import { EXPORT_SIZE_LIST, EXPORT_SIZES } from "@/lib/slides/sizes";
import {
  MAX_BADGE_MEANINGS,
  MAX_COMPOUNDS,
  MAX_HASHTAGS,
  MAX_VERBS,
  photoImageUrl,
  type DecompositionPayload,
  type ExportSizeId,
  type RecipeId,
  type SlideshowDeck,
  type SpotlightItem,
  type SpotlightPayload,
} from "@/lib/slides/types";
import { writeInSpotlightItem } from "@/lib/slides/payload";
import { readingLine } from "@/lib/slides/romaji";
import {
  CurriculumDragHandle,
  SortableItem,
  SortableList,
} from "@/components/content/curriculum-sortable";
import { SlideFrame, SlideViewfinder } from "./slide-frame";
import { captureSlidePng, downloadBlob, zipPngs } from "./export-slides";
import { cn } from "@/lib/utils";

export function DeckEditor({ deckId }: { deckId: string }) {
  const queryClient = useQueryClient();
  const { data, isLoading, isError, error } = useQuery({
    queryKey: ["slide-deck", deckId],
    queryFn: () => slidesApi.getDeck(deckId),
  });
  const photosQuery = useQuery({
    queryKey: ["slide-photos"],
    queryFn: () => slidesApi.listPhotos(),
  });

  const save = useMutation({
    mutationFn: (body: Parameters<typeof slidesApi.patchDeck>[1]) =>
      slidesApi.patchDeck(deckId, body),
    onSuccess: (result) => {
      queryClient.setQueryData(["slide-deck", deckId], result);
    },
    onError: (err) => toast.error(err.message),
  });

  if (isLoading) {
    return <p className="text-sm text-muted-foreground">Loading deck…</p>;
  }
  if (isError || !data) {
    return (
      <p className="text-sm text-destructive">
        {error instanceof Error ? error.message : "Could not load deck."}
      </p>
    );
  }

  return (
    <DeckEditorLoaded
      deck={data.deck}
      photos={photosQuery.data?.photos ?? []}
      saving={save.isPending}
      onSave={(body) => save.mutate(body)}
    />
  );
}

function DeckEditorLoaded({
  deck,
  photos,
  saving,
  onSave,
}: {
  deck: SlideshowDeck;
  photos: Awaited<ReturnType<typeof slidesApi.listPhotos>>["photos"];
  saving: boolean;
  onSave: (body: Parameters<typeof slidesApi.patchDeck>[1]) => void;
}) {
  const [index, setIndex] = useState(0);
  const [exporting, setExporting] = useState(false);
  const captureNodes = useRef<Map<number, HTMLDivElement>>(new Map());

  const slides = useMemo(
    () => slidesForDeck(deck.kind, deck.payload),
    [deck.kind, deck.payload]
  );
  const canvas = EXPORT_SIZES[deck.exportSize];
  const current = slides[Math.min(index, Math.max(0, slides.length - 1))] ?? slides[0];
  const pool = photos
    .filter((photo) => deck.photoSet === "all" || photo.tags.includes(deck.photoSet))
    .map((photo) => ({ id: photo.id, url: photoImageUrl(photo.id) }));
  const tags = Array.from(new Set(photos.flatMap((photo) => photo.tags))).sort();

  async function exportSlides(all: boolean) {
    if (!current) return;
    setExporting(true);
    try {
      const targets = all ? slides : [current];
      const files: Array<{ name: string; blob: Blob }> = [];
      for (let i = 0; i < targets.length; i += 1) {
        const slide = targets[i];
        const slideIndex = all ? i : index;
        const node = captureNodes.current.get(slideIndex);
        if (!node) continue;
        const blob = await captureSlidePng(node);
        files.push({
          name: slideFileName(slideIndex, slide, deck.payload),
          blob,
        });
      }
      if (files.length === 0) throw new Error("Nothing to export.");
      if (files.length === 1) {
        downloadBlob(files[0].blob, files[0].name);
      } else {
        const zip = await zipPngs(files);
        downloadBlob(zip, `${deck.usedSubject}-slides.zip`);
      }
      onSave({ status: "exported" });
      toast.success(all ? "Downloaded all slides." : "Downloaded this slide.");
    } catch (error) {
      toast.error(error instanceof Error ? error.message : "Export failed.");
    } finally {
      setExporting(false);
    }
  }

  return (
    <div className="flex flex-col gap-4 lg:flex-row lg:items-start">
      <div className="min-w-0 flex-1 space-y-3">
        <div className="flex flex-wrap items-center gap-2">
          <Link href="/slides" className="text-sm text-muted-foreground hover:text-foreground">
            ← Slides
          </Link>
          <h1 className="text-xl font-semibold tracking-tight">{deck.usedSubject}</h1>
          <span className="text-xs text-muted-foreground capitalize">{deck.kind}</span>
          {saving ? (
            <span className="text-xs text-muted-foreground">Saving…</span>
          ) : null}
        </div>
        {current ? (
          <SlideViewfinder canvasWidth={canvas.width} canvasHeight={canvas.height}>
            <SlideFrame
              kind={deck.kind}
              payload={deck.payload}
              slide={current}
              recipeId={deck.recipeId}
              exportSize={deck.exportSize}
              photos={pool}
              seed={deck.photoSeed}
              slideIndex={index}
            />
          </SlideViewfinder>
        ) : (
          <p className="text-sm text-muted-foreground">
            Add at least one compound to preview slides.
          </p>
        )}
        <div className="flex flex-wrap items-center justify-center gap-2">
          <Button
            variant="outline"
            size="icon"
            disabled={index <= 0}
            onClick={() => setIndex((value) => Math.max(0, value - 1))}
          >
            <ChevronLeft />
          </Button>
          <span className="text-sm tabular-nums text-muted-foreground">
            {slides.length === 0 ? "0 / 0" : `${index + 1} / ${slides.length}`}
          </span>
          <Button
            variant="outline"
            size="icon"
            disabled={index >= slides.length - 1}
            onClick={() => setIndex((value) => Math.min(slides.length - 1, value + 1))}
          >
            <ChevronRight />
          </Button>
        </div>
        <div className="flex flex-wrap gap-2">
          <Button onClick={() => exportSlides(true)} disabled={exporting || slides.length === 0}>
            <Download />
            {exporting ? "Exporting…" : "Download all"}
          </Button>
          <Button
            variant="outline"
            onClick={() => exportSlides(false)}
            disabled={exporting || slides.length === 0}
          >
            Download this slide
          </Button>
        </div>
        <div
          aria-hidden
          className="pointer-events-none absolute -left-[200vw] top-0"
        >
          {slides.map((slide, slideIndex) => (
            <SlideFrame
              key={slide.id}
              kind={deck.kind}
              payload={deck.payload}
              slide={slide}
              recipeId={deck.recipeId}
              exportSize={deck.exportSize}
              photos={pool}
              seed={deck.photoSeed}
              slideIndex={slideIndex}
              captureRef={(node) => {
                if (node) captureNodes.current.set(slideIndex, node);
                else captureNodes.current.delete(slideIndex);
              }}
            />
          ))}
        </div>
      </div>

      <aside className="w-full shrink-0 space-y-5 lg:w-[22rem]">
        <section className="space-y-2">
          <h2 className="text-sm font-medium">Look</h2>
          <Label>Recipe</Label>
          <select
            className={selectClass}
            value={deck.recipeId}
            onChange={(event) =>
              onSave({ recipeId: event.target.value as RecipeId })
            }
          >
            {RECIPE_LIST.map((recipe) => (
              <option key={recipe.id} value={recipe.id}>
                {recipe.name}
              </option>
            ))}
          </select>
          <Label>Size</Label>
          <div className="flex gap-1">
            {EXPORT_SIZE_LIST.map((size) => (
              <Button
                key={size.id}
                size="sm"
                variant={deck.exportSize === size.id ? "default" : "outline"}
                onClick={() => onSave({ exportSize: size.id as ExportSizeId })}
              >
                {size.shortTitle}
              </Button>
            ))}
          </div>
          <Label>Photo set</Label>
          <select
            className={selectClass}
            value={deck.photoSet}
            onChange={(event) => onSave({ photoSet: event.target.value })}
          >
            <option value="all">All photos</option>
            {tags.map((tag) => (
              <option key={tag} value={tag}>
                {tag}
              </option>
            ))}
          </select>
          <div className="flex items-center gap-2">
            <Button
              variant="outline"
              size="sm"
              onClick={() => onSave({ photoSeed: newPhotoSeed() })}
            >
              <Shuffle />
              Reshuffle
            </Button>
            <Link
              href="/slides/photos"
              className="text-xs text-muted-foreground hover:text-foreground"
            >
              <span className="inline-flex items-center gap-1">
                <Images className="size-3.5" /> Photo library
              </span>
            </Link>
          </div>
        </section>

        {deck.kind === "spotlight" ? (
          <SpotlightInspector
            payload={deck.payload as SpotlightPayload}
            onChange={(payload) => onSave({ payload })}
          />
        ) : (
          <DecompositionInspector
            payload={deck.payload as DecompositionPayload}
            onChange={(payload) => onSave({ payload })}
          />
        )}

        <HashtagPicker
          selected={
            deck.kind === "spotlight"
              ? (deck.payload as SpotlightPayload).hashtags
              : (deck.payload as DecompositionPayload).hashtags
          }
          onChange={(hashtags) => {
            if (deck.kind === "spotlight") {
              onSave({ payload: { ...(deck.payload as SpotlightPayload), hashtags } });
            } else {
              onSave({
                payload: { ...(deck.payload as DecompositionPayload), hashtags },
              });
            }
          }}
        />
      </aside>
    </div>
  );
}

const selectClass =
  "h-8 w-full rounded-lg border border-input bg-transparent px-2.5 text-sm";

function SpotlightInspector({
  payload,
  onChange,
}: {
  payload: SpotlightPayload;
  onChange: (payload: SpotlightPayload) => void;
}) {
  const kanji = findKanji(payload.character);
  const [writeIn, setWriteIn] = useState({ expression: "", gloss: "", reading: "" });
  const selectedKeys = new Set(
    payload.items.map((item) => `${item.kind}:${item.expression}:${item.reading}`)
  );

  function toggleCandidate(item: SpotlightItem) {
    const exists = payload.items.find(
      (row) =>
        row.expression === item.expression &&
        row.kind === item.kind &&
        row.reading === item.reading
    );
    if (exists) {
      onChange({
        ...payload,
        items: payload.items.filter((row) => row.id !== exists.id),
      });
      return;
    }
    const cap = item.kind === "compound" ? MAX_COMPOUNDS : MAX_VERBS;
    const count = payload.items.filter((row) => row.kind === item.kind).length;
    if (count >= cap) {
      toast.error(
        item.kind === "compound"
          ? `At most ${MAX_COMPOUNDS} compounds.`
          : `At most ${MAX_VERBS} verbs.`
      );
      return;
    }
    onChange({ ...payload, items: [...payload.items, item] });
  }

  return (
    <section className="space-y-3">
      <h2 className="text-sm font-medium">Spotlight</h2>
      <Label>Intro title</Label>
      <select
        className={selectClass}
        value={INTRO_TITLE_PRESETS.includes(payload.introTitle) ? payload.introTitle : "__custom"}
        onChange={(event) => {
          if (event.target.value === "__custom") return;
          onChange({ ...payload, introTitle: event.target.value });
        }}
      >
        {INTRO_TITLE_PRESETS.map((title) => (
          <option key={title} value={title}>
            {title}
          </option>
        ))}
        <option value="__custom">Custom…</option>
      </select>
      <Input
        value={payload.introTitle}
        onChange={(event) => onChange({ ...payload, introTitle: event.target.value })}
      />
      <Label>Badge meaning</Label>
      <MeaningPicker
        meanings={payload.meanings}
        selected={payload.badgeMeanings}
        onChange={(badgeMeanings) => onChange({ ...payload, badgeMeanings })}
      />
      <Label>Highlight color</Label>
      <div className="flex flex-wrap gap-1">
        {HIGHLIGHT_COLORS.map((color) => (
          <button
            key={color.id}
            type="button"
            title={color.title}
            className={cn(
              "size-6 rounded-full border",
              payload.highlightColor === color.id
                ? "ring-2 ring-ring"
                : "border-border"
            )}
            style={{ background: color.css.replace("0.55", "1") }}
            onClick={() => onChange({ ...payload, highlightColor: color.id })}
          />
        ))}
      </div>

      <div>
        <Label>Selected · drag to reorder</Label>
        <SortableList
          items={payload.items.map((item) => item.id)}
          onReorder={(ids) => {
            const map = new Map(payload.items.map((item) => [item.id, item]));
            onChange({
              ...payload,
              items: ids.map((id) => map.get(id)).filter(Boolean) as SpotlightItem[],
            });
          }}
          className="mt-2 space-y-1"
        >
          {payload.items.map((item, exampleNumber) => (
            <SortableItem key={item.id} id={item.id}>
              {({ setNodeRef, style, attributes, listeners }) => (
                <div
                  ref={setNodeRef}
                  style={style}
                  className="flex items-start gap-1 rounded-md border border-border/60 bg-muted/30 p-1.5"
                >
                  <CurriculumDragHandle attributes={attributes} listeners={listeners} />
                  <div className="min-w-0 flex-1">
                    <div className="text-sm font-medium">
                      {exampleNumber + 1}. {item.expression}
                    </div>
                    <Input
                      className="mt-1 h-7"
                      value={item.gloss}
                      onChange={(event) =>
                        onChange({
                          ...payload,
                          items: payload.items.map((row) =>
                            row.id === item.id
                              ? { ...row, gloss: event.target.value }
                              : row
                          ),
                        })
                      }
                    />
                  </div>
                  <Button
                    variant="ghost"
                    size="xs"
                    onClick={() =>
                      onChange({
                        ...payload,
                        items: payload.items.filter((row) => row.id !== item.id),
                      })
                    }
                  >
                    Remove
                  </Button>
                </div>
              )}
            </SortableItem>
          ))}
        </SortableList>
      </div>

      <div>
        <Label>Compounds · {payload.items.filter((i) => i.kind === "compound").length}/{MAX_COMPOUNDS}</Label>
        <div className="mt-1 max-h-48 space-y-1 overflow-auto">
          {(kanji?.compounds ?? []).map((row) => {
            const key = `compound:${row.expression}:${row.reading}`;
            const selected = selectedKeys.has(key);
            return (
              <button
                key={key}
                type="button"
                className={cn(
                  "flex w-full flex-col rounded-md px-2 py-1.5 text-left text-sm hover:bg-muted",
                  selected && "bg-accent"
                )}
                onClick={() =>
                  toggleCandidate({
                    id: crypto.randomUUID(),
                    expression: row.expression,
                    reading: row.reading,
                    gloss: row.gloss,
                    kind: "compound",
                    source: "catalog",
                  })
                }
              >
                <span className="font-medium">
                  {row.expression}{" "}
                  <span className="font-normal text-muted-foreground">
                    {readingLine(row.reading)}
                  </span>
                </span>
                <span className="text-xs text-muted-foreground">{row.gloss}</span>
              </button>
            );
          })}
        </div>
      </div>

      {(kanji?.verbs.length ?? 0) > 0 ? (
        <div>
          <Label>Verbs · {payload.items.filter((i) => i.kind === "verb").length}/{MAX_VERBS}</Label>
          <div className="mt-1 max-h-32 space-y-1 overflow-auto">
            {(kanji?.verbs ?? []).map((row) => {
              const key = `verb:${row.expression}:${row.reading}`;
              const selected = selectedKeys.has(key);
              return (
                <button
                  key={key}
                  type="button"
                  className={cn(
                    "flex w-full flex-col rounded-md px-2 py-1.5 text-left text-sm hover:bg-muted",
                    selected && "bg-accent"
                  )}
                  onClick={() =>
                    toggleCandidate({
                      id: crypto.randomUUID(),
                      expression: row.expression,
                      reading: row.reading,
                      gloss: row.gloss,
                      kind: "verb",
                      source: "catalog",
                    })
                  }
                >
                  <span className="font-medium">
                    {row.expression}{" "}
                    <span className="font-normal text-muted-foreground">
                      {readingLine(row.reading)}
                    </span>
                  </span>
                  <span className="text-xs text-muted-foreground">{row.gloss}</span>
                </button>
              );
            })}
          </div>
        </div>
      ) : null}

      <div className="space-y-1.5">
        <Label>Write in compound</Label>
        <Input
          placeholder="漢字"
          value={writeIn.expression}
          onChange={(event) =>
            setWriteIn((current) => ({ ...current, expression: event.target.value }))
          }
        />
        <Input
          placeholder="definition"
          value={writeIn.gloss}
          onChange={(event) =>
            setWriteIn((current) => ({ ...current, gloss: event.target.value }))
          }
        />
        <Input
          placeholder="reading (optional)"
          value={writeIn.reading}
          onChange={(event) =>
            setWriteIn((current) => ({ ...current, reading: event.target.value }))
          }
        />
        <Button
          variant="outline"
          size="sm"
          onClick={() => {
            if (!writeIn.expression.trim() || !writeIn.gloss.trim()) {
              toast.error("Need kanji and a definition.");
              return;
            }
            const count = payload.items.filter((row) => row.kind === "compound").length;
            if (count >= MAX_COMPOUNDS) {
              toast.error(`At most ${MAX_COMPOUNDS} compounds.`);
              return;
            }
            onChange({
              ...payload,
              items: [...payload.items, writeInSpotlightItem(writeIn)],
            });
            setWriteIn({ expression: "", gloss: "", reading: "" });
          }}
        >
          Add write-in
        </Button>
      </div>
    </section>
  );
}

function DecompositionInspector({
  payload,
  onChange,
}: {
  payload: DecompositionPayload;
  onChange: (payload: DecompositionPayload) => void;
}) {
  const [customGloss, setCustomGloss] = useState("");
  return (
    <section className="space-y-3">
      <h2 className="text-sm font-medium">Decomposition</h2>
      <Label>Part label</Label>
      <Input
        value={payload.partLabel}
        onChange={(event) => onChange({ ...payload, partLabel: event.target.value })}
      />
      {payload.characters.map((character, index) => (
        <div key={`${character.character}-${index}`} className="space-y-1">
          <Label>Badge · {character.character}</Label>
          <MeaningPicker
            meanings={character.meanings}
            selected={character.badgeMeanings}
            onChange={(badgeMeanings) =>
              onChange({
                ...payload,
                characters: payload.characters.map((row, rowIndex) =>
                  rowIndex === index ? { ...row, badgeMeanings } : row
                ),
              })
            }
          />
        </div>
      ))}
      <Label>Final definition</Label>
      <div className="space-y-1">
        {payload.glossOptions.map((option) => (
          <button
            key={option}
            type="button"
            className={cn(
              "block w-full rounded-md px-2 py-1.5 text-left text-sm hover:bg-muted",
              (payload.definitionOverride ?? payload.gloss) === option && "bg-accent"
            )}
            onClick={() =>
              onChange({
                ...payload,
                definitionOverride: option === payload.gloss ? null : option,
              })
            }
          >
            {option}
          </button>
        ))}
        <div className="flex gap-1">
          <Input
            placeholder="Write in…"
            value={customGloss}
            onChange={(event) => setCustomGloss(event.target.value)}
          />
          <Button
            variant="outline"
            size="sm"
            onClick={() => {
              const trimmed = customGloss.trim();
              if (!trimmed) return;
              onChange({ ...payload, definitionOverride: trimmed });
              setCustomGloss("");
            }}
          >
            Use
          </Button>
        </div>
      </div>
    </section>
  );
}

function MeaningPicker({
  meanings,
  selected,
  onChange,
}: {
  meanings: string[];
  selected: string[];
  onChange: (next: string[]) => void;
}) {
  return (
    <div className="flex flex-wrap gap-1">
      {meanings.map((meaning) => {
        const on = selected.includes(meaning);
        return (
          <button
            key={meaning}
            type="button"
            className={cn(
              "rounded-full border px-2 py-0.5 text-xs",
              on ? "border-transparent bg-accent" : "border-border text-muted-foreground"
            )}
            onClick={() => {
              if (on) {
                onChange(selected.filter((row) => row !== meaning));
                return;
              }
              if (selected.length >= MAX_BADGE_MEANINGS) {
                onChange([...selected.slice(1), meaning]);
                return;
              }
              onChange([...selected, meaning]);
            }}
          >
            {meaning}
          </button>
        );
      })}
    </div>
  );
}

function HashtagPicker({
  selected,
  onChange,
}: {
  selected: string[];
  onChange: (next: string[]) => void;
}) {
  const line = formatHashtagLine(selected);
  return (
    <section className="space-y-2">
      <h2 className="text-sm font-medium">Hashtags</h2>
      <div className="flex flex-wrap gap-1">
        {RECOMMENDED_HASHTAGS.map((tag) => {
          const on = selected.includes(tag);
          return (
            <button
              key={tag}
              type="button"
              className={cn(
                "rounded-full border px-2 py-0.5 text-xs",
                on ? "border-transparent bg-accent" : "border-border text-muted-foreground"
              )}
              onClick={() => {
                if (on) {
                  onChange(selected.filter((row) => row !== tag));
                  return;
                }
                if (selected.length >= MAX_HASHTAGS) {
                  toast.error(`Pick up to ${MAX_HASHTAGS}.`);
                  return;
                }
                onChange([...selected, tag]);
              }}
            >
              {tag}
            </button>
          );
        })}
      </div>
      <div className="flex items-center gap-2">
        <code className="min-w-0 flex-1 truncate text-xs text-muted-foreground">
          {line || "None selected"}
        </code>
        <Button
          variant="outline"
          size="xs"
          disabled={!line}
          onClick={async () => {
            await navigator.clipboard.writeText(line);
            toast.success("Copied hashtags.");
          }}
        >
          <Copy />
          Copy
        </Button>
      </div>
    </section>
  );
}
