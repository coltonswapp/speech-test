"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Plus, Sparkles, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { GrammarPointPicker } from "@/components/content/grammar-point-picker";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { contentApi } from "@/lib/content/client";
import { dialogueApi } from "@/lib/dialogue/client";
import {
  mergeExtractedHighlights,
  syncGrammarPatternsFromLines,
  uniqueGrammarIdsFromLines,
} from "@/lib/dialogue/enrich-highlights";
import { hasSpokenJapanese, type DialogueHighlights, type DialogueLine } from "@/lib/dialogue/types";

const empty: DialogueHighlights = {
  vocabulary: [],
  grammarPatterns: [],
  contextNotes: [],
};

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
  const [isExtracting, setIsExtracting] = useState(false);
  const didAutoSyncGrammar = useRef(false);

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

      <div className="flex flex-col gap-2">
        <Label>Vocabulary (one per line)</Label>
        <Textarea
          rows={6}
          value={vocabulary.join("\n")}
          onChange={(e) =>
            patch({
              vocabulary: e.target.value.split("\n").filter((v) => v.trim()),
            })
          }
        />
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
                value={pattern.label}
                onChange={(e) => {
                  const next = grammarPatterns.slice();
                  next[index] = { ...next[index], label: e.target.value };
                  patch({ grammarPatterns: next });
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
            <GrammarPointPicker
              label="Linked grammar point"
              variant="embedded"
              multiple={false}
              value={pattern.grammarPointID ? [pattern.grammarPointID] : []}
              onChange={(ids) => {
                const next = grammarPatterns.slice();
                next[index] = {
                  ...next[index],
                  grammarPointID: ids[0] ?? undefined,
                };
                patch({ grammarPatterns: next });
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
