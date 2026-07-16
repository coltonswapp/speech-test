"use client";

import { useState } from "react";
import { ArrowDown, ArrowUp, Plus, Sparkles, Trash2, X } from "lucide-react";
import { toast } from "sonner";
import { GrammarPointPicker } from "@/components/content/grammar-point-picker";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { dialogueApi } from "@/lib/dialogue/client";
import type { DialogueLine, GeneratedLine } from "@/lib/dialogue/types";
import { LineRevisionDiff } from "@/components/dialogue/line-revision-diff";

export type ReviseContext = {
  setting?: string;
  menuTitle?: string;
  grammarPointIds: string[];
};

function applyRevision(
  original: DialogueLine,
  proposed: GeneratedLine
): DialogueLine {
  return {
    ...original,
    speaker: proposed.speaker,
    japanese: proposed.japanese,
    romaji: proposed.romaji,
    english: proposed.english,
    grammarPointIDs:
      proposed.grammarPointIDs && proposed.grammarPointIDs.length > 0
        ? proposed.grammarPointIDs
        : undefined,
  };
}

export function LineEditor({
  lines,
  onChange,
  reviseContext,
  onLinesCommitted,
}: {
  lines: DialogueLine[];
  onChange: (lines: DialogueLine[]) => void;
  /** When provided, enables LLM revise-in-place and per-line regeneration. */
  reviseContext?: ReviseContext;
  /** Called after Gemini revisions are accepted or a whole-dialogue rewrite lands. */
  onLinesCommitted?: (lines: DialogueLine[]) => void;
}) {
  const [selected, setSelected] = useState<Set<number>>(new Set());
  const [instructions, setInstructions] = useState("");
  const [pendingRevisions, setPendingRevisions] = useState<
    Map<number, GeneratedLine>
  >(new Map());
  const [revisingLine, setRevisingLine] = useState<number | null>(null);
  const [isRevising, setIsRevising] = useState(false);

  function update(index: number, patch: Partial<DialogueLine>) {
    const next = lines.slice();
    next[index] = { ...next[index], ...patch };
    onChange(next);
  }

  function remove(index: number) {
    onChange(lines.filter((_, i) => i !== index));
    clearRevisionState();
  }

  function move(index: number, delta: number) {
    const target = index + delta;
    if (target < 0 || target >= lines.length) return;
    const next = lines.slice();
    [next[index], next[target]] = [next[target], next[index]];
    onChange(next);
    clearRevisionState();
  }

  function add() {
    const lastSpeaker = lines[lines.length - 1]?.speaker;
    const otherSpeaker = lines.find((l) => l.speaker !== lastSpeaker)?.speaker;
    onChange([
      ...lines,
      {
        speaker: otherSpeaker ?? lastSpeaker ?? "",
        japanese: "",
        romaji: "",
        english: "",
      },
    ]);
  }

  // Pending revisions and selections are keyed by index, so any structural
  // change (add/remove/reorder) invalidates them.
  function clearRevisionState() {
    setSelected(new Set());
    setPendingRevisions(new Map());
  }

  function toggleSelected(index: number) {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(index)) next.delete(index);
      else next.add(index);
      return next;
    });
  }

  async function revise(indices: number[] | null, promptOverride?: string) {
    if (!reviseContext) return;
    const effectiveInstructions =
      promptOverride ?? instructions.trim();
    if (!effectiveInstructions) {
      toast.error("Describe how the lines should change.");
      return;
    }

    const scope = indices ? "selection" : "all";
    setIsRevising(true);
    if (indices?.length === 1) setRevisingLine(indices[0]);
    try {
      const { result } = await dialogueApi.reviseLines({
        lines,
        scope,
        selectedIndices: indices ?? undefined,
        instructions: effectiveInstructions,
        setting: reviseContext.setting,
        menuTitle: reviseContext.menuTitle,
        grammarPointIds: reviseContext.grammarPointIds,
      });
      if (result.scope === "selection") {
        setPendingRevisions((prev) => {
          const next = new Map(prev);
          for (const revision of result.revisions) {
            next.set(revision.index, revision.line);
          }
          return next;
        });
        toast.success(
          `Proposed ${result.revisions.length} revision(s) — accept or reject each below.`
        );
      } else {
        // Whole-dialogue rewrite may add/remove lines, so per-index diffs
        // don't apply — replace the draft directly (persisted only on Save).
        const nextLines = result.generated.lines.map((line, index) =>
          applyRevision(lines[index] ?? { speaker: "", japanese: "" }, line)
        );
        onChange(nextLines);
        onLinesCommitted?.(nextLines);
        clearRevisionState();
        toast.success("Dialogue rewritten. Review and Save to persist.");
      }
    } catch (error) {
      toast.error(error instanceof Error ? error.message : "Revision failed.");
    } finally {
      setIsRevising(false);
      setRevisingLine(null);
    }
  }

  function acceptRevision(index: number) {
    const proposed = pendingRevisions.get(index);
    if (!proposed) return;
    const next = lines.slice();
    next[index] = applyRevision(lines[index], proposed);
    onChange(next);
    setPendingRevisions((prev) => {
      const nextPending = new Map(prev);
      nextPending.delete(index);
      if (nextPending.size === 0) {
        onLinesCommitted?.(next);
      }
      return nextPending;
    });
  }

  function rejectRevision(index: number) {
    setPendingRevisions((prev) => {
      const next = new Map(prev);
      next.delete(index);
      return next;
    });
  }

  function acceptAllRevisions() {
    const next = lines.map((line, index) => {
      const proposed = pendingRevisions.get(index);
      return proposed ? applyRevision(line, proposed) : line;
    });
    onChange(next);
    onLinesCommitted?.(next);
    setPendingRevisions(new Map());
  }

  const reviseEnabled = !!reviseContext && lines.length > 0;

  // A grammar point commonly ends up tagged on multiple lines (e.g. a
  // scenario-wide fallback applied when generating). Only display it on the
  // first line it appears on so it isn't shown as "for this line" everywhere.
  const firstLineForGrammarPoint = new Map<string, number>();
  lines.forEach((line, index) => {
    for (const id of line.grammarPointIDs ?? []) {
      if (!firstLineForGrammarPoint.has(id)) {
        firstLineForGrammarPoint.set(id, index);
      }
    }
  });

  return (
    <div className="flex flex-col gap-3">
      <Label>Lines</Label>
      {lines.length === 0 && (
        <p className="text-sm text-muted-foreground">
          No lines yet. Add them by hand or generate below.
        </p>
      )}
      {lines.map((line, index) => (
        <div
          key={index}
          className="flex flex-col gap-2 rounded-md border border-border/60 p-3"
        >
          <div className="flex items-center gap-2">
            {reviseEnabled && (
              <input
                type="checkbox"
                className="size-4 accent-primary"
                checked={selected.has(index)}
                onChange={() => toggleSelected(index)}
                aria-label={`Select line ${index + 1} for revision`}
              />
            )}
            <span className="text-xs text-muted-foreground">#{index + 1}</span>
            <Input
              className="w-40"
              value={line.speaker}
              onChange={(e) => update(index, { speaker: e.target.value })}
              placeholder="Speaker"
            />
            <div className="flex-1" />
            {reviseEnabled && (
              <Button
                variant="ghost"
                size="icon-sm"
                onClick={() =>
                  void revise(
                    [index],
                    instructions.trim() ||
                      "Rewrite this line so it flows naturally in context, keeping the same meaning."
                  )
                }
                disabled={isRevising || !line.japanese.trim()}
                aria-label="Regenerate this line"
                title="Regenerate this line in context"
              >
                <Sparkles
                  className={`size-3.5 ${revisingLine === index ? "animate-pulse" : ""}`}
                />
              </Button>
            )}
            <Button
              variant="ghost"
              size="icon-sm"
              onClick={() => move(index, -1)}
              disabled={index === 0}
              aria-label="Move line up"
            >
              <ArrowUp className="size-3.5" />
            </Button>
            <Button
              variant="ghost"
              size="icon-sm"
              onClick={() => move(index, 1)}
              disabled={index === lines.length - 1}
              aria-label="Move line down"
            >
              <ArrowDown className="size-3.5" />
            </Button>
            <Button
              variant="ghost"
              size="icon-sm"
              onClick={() => remove(index)}
              aria-label="Remove line"
            >
              <Trash2 className="size-3.5" />
            </Button>
          </div>
          <div className="flex flex-col gap-4 sm:flex-row sm:items-start">
            <div className="flex min-w-0 flex-1 flex-col gap-2">
              <Input
                value={line.japanese}
                onChange={(e) => update(index, { japanese: e.target.value })}
                placeholder="Japanese"
              />
              <Input
                value={line.romaji ?? ""}
                onChange={(e) => update(index, { romaji: e.target.value })}
                placeholder="Romaji"
              />
              <Input
                value={line.english ?? ""}
                onChange={(e) => update(index, { english: e.target.value })}
                placeholder="English"
              />
            </div>
            <div className="w-full shrink-0 sm:w-72 sm:border-l sm:border-border/50 sm:pl-4">
              <GrammarPointPicker
                label="Grammar for this line"
                variant="embedded"
                value={(line.grammarPointIDs ?? []).filter(
                  (id) => firstLineForGrammarPoint.get(id) === index
                )}
                onChange={(displayedIds) => {
                  const previousDisplayed = (line.grammarPointIDs ?? []).filter(
                    (id) => firstLineForGrammarPoint.get(id) === index
                  );
                  const removedIds = new Set(
                    previousDisplayed.filter((id) => !displayedIds.includes(id))
                  );

                  // Removals must strip the id from every line. Generation often
                  // stamps the same id on all lines, and we only show it on the
                  // first — clearing only this line makes the chip reappear on
                  // the next one.
                  if (removedIds.size > 0) {
                    onChange(
                      lines.map((l, i) => {
                        let ids = (l.grammarPointIDs ?? []).filter(
                          (id) => !removedIds.has(id)
                        );
                        if (i === index) {
                          const hiddenIds = ids.filter(
                            (id) => firstLineForGrammarPoint.get(id) !== index
                          );
                          ids = [...hiddenIds, ...displayedIds];
                        }
                        return {
                          ...l,
                          grammarPointIDs:
                            ids.length > 0 ? ids : undefined,
                        };
                      })
                    );
                    return;
                  }

                  // Adds (or reorder of displayed set): update this line only,
                  // preserving ids that are displayed on an earlier line.
                  const hiddenIds = (line.grammarPointIDs ?? []).filter(
                    (id) => firstLineForGrammarPoint.get(id) !== index
                  );
                  const grammarPointIDs = [...hiddenIds, ...displayedIds];
                  update(index, {
                    grammarPointIDs:
                      grammarPointIDs.length > 0 ? grammarPointIDs : undefined,
                  });
                }}
              />
            </div>
          </div>
          {pendingRevisions.has(index) && (
            <LineRevisionDiff
              original={line}
              proposed={pendingRevisions.get(index)!}
              onAccept={() => acceptRevision(index)}
              onReject={() => rejectRevision(index)}
            />
          )}
        </div>
      ))}
      <Button variant="outline" size="sm" className="w-fit gap-2" onClick={add}>
        <Plus className="size-4" />
        Add line
      </Button>

      {reviseEnabled && (
        <div className="flex flex-col gap-3 rounded-md border border-border/60 p-4">
          <div className="flex items-center gap-2">
            <Sparkles className="size-4 text-muted-foreground" />
            <Label>Revise with Gemini</Label>
          </div>
          <Textarea
            rows={2}
            value={instructions}
            onChange={(e) => setInstructions(e.target.value)}
            placeholder='e.g. "Make the customer more casual" or "Shorten the replies"'
          />
          <div className="flex flex-wrap items-center gap-2">
            <Button
              size="sm"
              onClick={() => void revise([...selected].sort((a, b) => a - b))}
              disabled={
                isRevising || selected.size === 0 || !instructions.trim()
              }
            >
              {isRevising
                ? "Revising…"
                : `Revise ${selected.size} selected line(s)`}
            </Button>
            <Button
              size="sm"
              variant="outline"
              onClick={() => void revise(null)}
              disabled={isRevising || !instructions.trim()}
            >
              Revise whole dialogue
            </Button>
            <Button
              size="sm"
              variant="ghost"
              onClick={() =>
                setSelected(
                  selected.size === lines.length
                    ? new Set()
                    : new Set(lines.map((_, i) => i))
                )
              }
            >
              {selected.size === lines.length ? "Clear selection" : "Select all"}
            </Button>
            {pendingRevisions.size > 1 && (
              <>
                <Button size="sm" variant="outline" onClick={acceptAllRevisions}>
                  Accept all ({pendingRevisions.size})
                </Button>
                <Button
                  size="sm"
                  variant="ghost"
                  className="gap-1"
                  onClick={() => setPendingRevisions(new Map())}
                >
                  <X className="size-3.5" />
                  Reject all
                </Button>
              </>
            )}
          </div>
          <p className="text-xs text-muted-foreground">
            Selected lines are revised in place; the rest of the dialogue is
            used as context. Proposals appear inline for accept/reject and
            nothing persists until you Save.
          </p>
        </div>
      )}
    </div>
  );
}
