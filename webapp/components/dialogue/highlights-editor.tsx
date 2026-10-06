"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Plus, Sparkles, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { GrammarPointPicker } from "@/components/content/grammar-point-picker";
import { TeachingPatternPicker } from "@/components/content/teaching-pattern-picker";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { contentApi } from "@/lib/content/client";
import { dialogueApi } from "@/lib/dialogue/client";
import {
  mergeExtractedHighlights,
  syncGrammarPatternsFromLines,
  uniqueGrammarIdsFromLines,
} from "@/lib/dialogue/enrich-highlights";
import {
  hasSpokenJapanese,
  spokenLinesOf,
  type DialogueHighlights,
  type DialogueLine,
  type GrammarPatternRef,
  type SpokenLine,
} from "@/lib/dialogue/types";

const empty: DialogueHighlights = {
  vocabulary: [],
  grammarPatterns: [],
  contextNotes: [],
};

const NONE_VALUE = "__none__";

function spokenLineLabel(line: SpokenLine, spokenIndex: number): string {
  const english = line.english?.trim() ? ` — ${line.english.trim()}` : "";
  const speaker = line.speaker?.trim() ? `${line.speaker}: ` : "";
  return `[${spokenIndex}] ${speaker}${line.japanese}${english}`;
}

function clampSpokenEnd(
  start: number | undefined,
  end: number | undefined,
): number | undefined {
  if (start === undefined || end === undefined) return undefined;
  return end < start ? undefined : end;
}

export function HighlightsEditor({
  highlights,
  onChange,
  lines,
  grammarPointIds = [],
  setting,
  menuTitle,
}: {
  highlights: DialogueHighlights | null;
  onChange: (highlights: DialogueHighlights) => void;
  lines: DialogueLine[];
  grammarPointIds?: string[];
  setting?: string | null;
  menuTitle?: string;
}) {
  const value = highlights ?? empty;
  const vocabulary = value.vocabulary ?? [];
  const grammarPatterns = value.grammarPatterns ?? [];
  const contextNotes = value.contextNotes ?? [];
  const spokenLines = spokenLinesOf(lines);
  const [isExtracting, setIsExtracting] = useState(false);
  const didAutoSyncGrammar = useRef(false);
  const vocabFocusIndex = useRef<number | null>(null);
  const vocabInputRefs = useRef<Array<HTMLInputElement | null>>([]);
  const skipVocabBlur = useRef(false);

  const taggedGrammarIds = useMemo(
    () => uniqueGrammarIdsFromLines(lines, grammarPointIds),
    [lines, grammarPointIds]
  );

  const { data: pointsData } = useQuery({
    queryKey: ["content-points", "all-labels"],
    queryFn: () => contentApi.listPoints(),
    staleTime: 5 * 60 * 1000,
  });

  const pointMap = useMemo(
    () =>
      new Map(
        (pointsData?.points ?? []).map((point) => [
          point.id,
          { title: point.title, pattern: point.pattern },
        ])
      ),
    [pointsData?.points]
  );

  function patch(next: Partial<DialogueHighlights>) {
    onChange({ vocabulary, grammarPatterns, contextNotes, ...next });
  }

  function updateGrammar(index: number, nextPattern: GrammarPatternRef) {
    const next = grammarPatterns.slice();
    next[index] = nextPattern;
    patch({ grammarPatterns: next });
  }

  function setVocabulary(next: string[]) {
    patch({ vocabulary: next });
  }

  function setVocabularyAt(index: number, word: string) {
    const next = vocabulary.slice();
    next[index] = word;
    setVocabulary(next);
  }

  /** Trim whitespace on blur; blank draft rows stay until Save filters them. */
  function commitVocabularyAt(index: number) {
    if (skipVocabBlur.current) {
      skipVocabBlur.current = false;
      return;
    }
    const current = vocabulary[index] ?? "";
    const trimmed = current.trim();
    if (trimmed === current) return;
    const next = vocabulary.slice();
    next[index] = trimmed;
    setVocabulary(next);
  }

  function addVocabularyRow() {
    vocabFocusIndex.current = vocabulary.length;
    setVocabulary([...vocabulary, ""]);
  }

  useEffect(() => {
    const index = vocabFocusIndex.current;
    if (index === null) return;
    vocabFocusIndex.current = null;
    vocabInputRefs.current[index]?.focus();
  }, [vocabulary]);

  function syncGrammarFromLines() {
    if (taggedGrammarIds.length === 0) {
      toast.error("No grammar points tagged on the scenario or lines yet.");
      return;
    }

    onChange(
      syncGrammarPatternsFromLines(highlights, taggedGrammarIds, pointMap)
    );
    toast.success(`Synced ${taggedGrammarIds.length} grammar pattern(s).`);
  }

  // Fallback when lines were added without auto-enrich (manual entry, import).
  useEffect(() => {
    if (didAutoSyncGrammar.current) return;
    if (grammarPatterns.length > 0) {
      didAutoSyncGrammar.current = true;
      return;
    }
    if (taggedGrammarIds.length === 0) return;
    if (pointsData === undefined) return;

    didAutoSyncGrammar.current = true;
    onChange(
      syncGrammarPatternsFromLines(highlights, taggedGrammarIds, pointMap)
    );
  }, [
    grammarPatterns.length,
    taggedGrammarIds,
    pointsData,
    pointMap,
    highlights,
    onChange,
  ]);

  async function extractWithAi() {
    if (lines.length === 0 || !hasSpokenJapanese(lines)) {
      toast.error("Add Japanese lines before extracting highlights.");
      return;
    }

    setIsExtracting(true);
    try {
      const { extracted } = await dialogueApi.extractHighlights({
        lines,
        setting: setting ?? undefined,
        menuTitle,
        grammarPointIds: taggedGrammarIds,
      });

      onChange(
        mergeExtractedHighlights(
          highlights,
          extracted,
          taggedGrammarIds,
          pointMap,
          "refresh"
        )
      );
      toast.success(
        `Extracted ${extracted.vocabulary.length} vocabulary item(s). Review and Save.`
      );
    } catch (error) {
      toast.error(
        error instanceof Error ? error.message : "Highlight extraction failed."
      );
    } finally {
      setIsExtracting(false);
    }
  }

  const missingGrammarCount = taggedGrammarIds.filter(
    (id) => !grammarPatterns.some((p) => p.grammarPointID === id)
  ).length;

  return (
    <div className="flex max-w-2xl flex-col gap-6">
      <div className="flex flex-wrap items-center gap-2 rounded-md border border-border/60 p-3">
        <Sparkles className="size-4 text-muted-foreground" />
        <div className="min-w-0 flex-1">
          <p className="text-sm font-medium">Extract from dialogue</p>
          <p className="text-xs text-muted-foreground">
            Pull vocabulary (and grammar labels) from the current lines with
            Gemini. Nothing persists until you Save.
          </p>
        </div>
        <Button
          size="sm"
          onClick={() => void extractWithAi()}
          disabled={isExtracting || lines.length === 0}
        >
          {isExtracting ? "Extracting…" : "Extract with AI"}
        </Button>
      </div>

      <div className="flex flex-col gap-3">
        <Label>Vocabulary</Label>
        {vocabulary.length === 0 && (
          <p className="text-xs text-muted-foreground">
            No vocabulary yet. Add words manually or extract with AI.
          </p>
        )}
        {vocabulary.map((word, index) => (
          <div key={index} className="flex items-center gap-2">
            <Input
              ref={(el) => {
                vocabInputRefs.current[index] = el;
              }}
              value={word}
              onChange={(e) => setVocabularyAt(index, e.target.value)}
              onBlur={() => commitVocabularyAt(index)}
              onKeyDown={(e) => {
                if (e.key !== "Enter") return;
                e.preventDefault();
                const trimmed = word.trim();
                if (!trimmed) return;
                skipVocabBlur.current = true;
                const next = vocabulary.slice();
                next[index] = trimmed;
                next.splice(index + 1, 0, "");
                vocabFocusIndex.current = index + 1;
                setVocabulary(next);
              }}
              placeholder="単語"
              aria-label={`Vocabulary word ${index + 1}`}
            />
            <Button
              variant="ghost"
              size="icon-sm"
              onClick={() =>
                setVocabulary(vocabulary.filter((_, i) => i !== index))
              }
              aria-label="Remove vocabulary word"
            >
              <Trash2 className="size-3.5" />
            </Button>
          </div>
        ))}
        <Button
          variant="outline"
          size="sm"
          className="w-fit gap-2"
          onClick={() => addVocabularyRow()}
        >
          <Plus className="size-4" />
          Add word
        </Button>
      </div>

      <div className="flex flex-col gap-3">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <Label>Grammar patterns</Label>
          <Button
            variant="outline"
            size="sm"
            className="w-fit"
            onClick={() => syncGrammarFromLines()}
            disabled={taggedGrammarIds.length === 0}
          >
            Sync from lines
            {missingGrammarCount > 0 ? ` (${missingGrammarCount} missing)` : ""}
          </Button>
        </div>
        <p className="text-xs text-muted-foreground">
          Inspect cards: link one Pattern library entry and the spoken line(s)
          where the learner hears it. Meaning lives on the Pattern — not on the
          scene.
        </p>
        {grammarPatterns.length === 0 && taggedGrammarIds.length > 0 && (
          <p className="text-xs text-muted-foreground">
            Lines are tagged with grammar points, but none are listed here yet.
            Sync from lines or extract with AI.
          </p>
        )}
        {grammarPatterns.map((pattern, index) => (
          <div
            key={index}
            className="flex flex-col gap-3 rounded-md border border-border/60 p-3"
          >
            <div className="flex items-center gap-2">
              <Input
                value={pattern.label ?? ""}
                onChange={(e) => {
                  updateGrammar(index, {
                    ...pattern,
                    label: e.target.value,
                  });
                }}
                placeholder="Label, e.g. 〜たいんですけど。。。"
              />
              <Button
                variant="ghost"
                size="icon-sm"
                onClick={() =>
                  patch({
                    grammarPatterns: grammarPatterns.filter((_, i) => i !== index),
                  })
                }
                aria-label="Remove pattern"
              >
                <Trash2 className="size-3.5" />
              </Button>
            </div>
            <TeachingPatternPicker
              label="Pattern library"
              description="One catalog pattern per highlight."
              variant="embedded"
              value={pattern.patternId ?? null}
              onChange={(picked) => {
                if (!picked) {
                  updateGrammar(index, {
                    ...pattern,
                    patternId: undefined,
                  });
                  return;
                }
                updateGrammar(index, {
                  ...pattern,
                  patternId: picked.id,
                  // Keep a readable label for old clients until backfill lands.
                  label: pattern.label?.trim() || picked.form,
                });
              }}
            />
            <div className="flex flex-col gap-2 rounded-md border border-dashed border-border/60 bg-muted/20 p-2.5">
              <Label className="text-xs text-muted-foreground">
                Spoken evidence (spoken lines)
              </Label>
              <p className="text-xs text-muted-foreground">
                Inclusive spoken-only indices (stage and inline-question rows
                skipped) — same space as quiz evidence.
              </p>
              {spokenLines.length === 0 ? (
                <p className="text-xs text-muted-foreground">
                  Add spoken dialogue lines to link evidence.
                </p>
              ) : (
                <>
                  <div className="grid gap-2 sm:grid-cols-2">
                    <div className="flex flex-col gap-1.5">
                      <Label className="text-xs">Start</Label>
                      <Select
                        value={
                          pattern.sourceSpokenStart !== undefined
                            ? String(pattern.sourceSpokenStart)
                            : NONE_VALUE
                        }
                        onValueChange={(raw) => {
                          if (!raw || raw === NONE_VALUE) {
                            updateGrammar(index, {
                              ...pattern,
                              sourceSpokenStart: undefined,
                              sourceSpokenEnd: undefined,
                            });
                            return;
                          }
                          const start = Number(raw);
                          updateGrammar(index, {
                            ...pattern,
                            sourceSpokenStart: start,
                            sourceSpokenEnd: clampSpokenEnd(
                              start,
                              pattern.sourceSpokenEnd,
                            ),
                          });
                        }}
                      >
                        <SelectTrigger className="w-full">
                          <SelectValue placeholder="No link">
                            {pattern.sourceSpokenStart !== undefined &&
                            spokenLines[pattern.sourceSpokenStart]
                              ? spokenLineLabel(
                                  spokenLines[pattern.sourceSpokenStart],
                                  pattern.sourceSpokenStart,
                                )
                              : "No link"}
                          </SelectValue>
                        </SelectTrigger>
                        <SelectContent className="max-w-[min(100vw-2rem,36rem)]">
                          <SelectItem value={NONE_VALUE}>No link</SelectItem>
                          {spokenLines.map((line, spokenIndex) => (
                            <SelectItem
                              key={spokenIndex}
                              value={String(spokenIndex)}
                              className="whitespace-normal text-left"
                            >
                              {spokenLineLabel(line, spokenIndex)}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </div>
                    <div className="flex flex-col gap-1.5">
                      <Label className="text-xs">End (optional, inclusive)</Label>
                      <Select
                        value={
                          pattern.sourceSpokenEnd !== undefined
                            ? String(pattern.sourceSpokenEnd)
                            : NONE_VALUE
                        }
                        onValueChange={(raw) => {
                          if (!raw || raw === NONE_VALUE) {
                            updateGrammar(index, {
                              ...pattern,
                              sourceSpokenEnd: undefined,
                            });
                            return;
                          }
                          const end = Number(raw);
                          const start = pattern.sourceSpokenStart;
                          updateGrammar(index, {
                            ...pattern,
                            sourceSpokenEnd:
                              start === undefined || end < start
                                ? undefined
                                : end,
                          });
                        }}
                        disabled={pattern.sourceSpokenStart === undefined}
                      >
                        <SelectTrigger className="w-full">
                          <SelectValue placeholder="Same as start">
                            {pattern.sourceSpokenEnd !== undefined &&
                            spokenLines[pattern.sourceSpokenEnd]
                              ? spokenLineLabel(
                                  spokenLines[pattern.sourceSpokenEnd],
                                  pattern.sourceSpokenEnd,
                                )
                              : "Same as start"}
                          </SelectValue>
                        </SelectTrigger>
                        <SelectContent className="max-w-[min(100vw-2rem,36rem)]">
                          <SelectItem value={NONE_VALUE}>Same as start</SelectItem>
                          {spokenLines
                            .map((line, spokenIndex) => ({ line, spokenIndex }))
                            .filter(
                              ({ spokenIndex }) =>
                                spokenIndex >= (pattern.sourceSpokenStart ?? 0),
                            )
                            .map(({ line, spokenIndex }) => (
                              <SelectItem
                                key={spokenIndex}
                                value={String(spokenIndex)}
                                className="whitespace-normal text-left"
                              >
                                {spokenLineLabel(line, spokenIndex)}
                              </SelectItem>
                            ))}
                        </SelectContent>
                      </Select>
                    </div>
                  </div>
                  {pattern.sourceSpokenStart !== undefined &&
                    spokenLines[pattern.sourceSpokenStart] && (
                      <div className="rounded-md border border-border/50 bg-background/60 px-2.5 py-2">
                        <p className="mb-1 text-[10px] font-medium uppercase tracking-wide text-muted-foreground">
                          Linked evidence preview
                        </p>
                        <ul className="flex flex-col gap-1.5">
                          {spokenLines
                            .slice(
                              pattern.sourceSpokenStart,
                              (pattern.sourceSpokenEnd ??
                                pattern.sourceSpokenStart) + 1,
                            )
                            .map((line, offset) => {
                              const spokenIndex =
                                pattern.sourceSpokenStart! + offset;
                              return (
                                <li
                                  key={spokenIndex}
                                  className="text-sm leading-snug"
                                >
                                  <span className="text-muted-foreground">
                                    [{spokenIndex}]{" "}
                                    {line.speaker?.trim()
                                      ? `${line.speaker.trim()}: `
                                      : ""}
                                  </span>
                                  <span>{line.japanese}</span>
                                  {line.english?.trim() ? (
                                    <span className="text-muted-foreground">
                                      {" "}
                                      — {line.english.trim()}
                                    </span>
                                  ) : null}
                                </li>
                              );
                            })}
                        </ul>
                      </div>
                    )}
                </>
              )}
            </div>
            <GrammarPointPicker
              label="Linked curriculum point (legacy)"
              variant="embedded"
              multiple={false}
              value={pattern.grammarPointID ? [pattern.grammarPointID] : []}
              onChange={(ids) => {
                updateGrammar(index, {
                  ...pattern,
                  grammarPointID: ids[0] ?? undefined,
                });
              }}
            />
          </div>
        ))}
        <Button
          variant="outline"
          size="sm"
          className="w-fit gap-2"
          onClick={() =>
            patch({ grammarPatterns: [...grammarPatterns, { label: "" }] })
          }
        >
          <Plus className="size-4" />
          Add pattern
        </Button>
      </div>

      <div className="flex flex-col gap-2">
        <Label>Context notes (one per line)</Label>
        <Textarea
          rows={5}
          value={contextNotes.join("\n")}
          onChange={(e) =>
            patch({
              contextNotes: e.target.value.split("\n").filter((v) => v.trim()),
            })
          }
        />
      </div>
    </div>
  );
}
