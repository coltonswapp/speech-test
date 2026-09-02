"use client";

import { useMemo, useRef, useState } from "react";
import {
  ArrowDown,
  ArrowUp,
  CircleHelp,
  Clapperboard,
  CornerDownRight,
  FileJson,
  Plus,
  Sparkles,
  Trash2,
  X,
} from "lucide-react";
import { toast } from "sonner";
import { z } from "zod";
import { GrammarPointPicker } from "@/components/content/grammar-point-picker";
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
import { dialogueApi } from "@/lib/dialogue/client";
import {
  defaultStageVisibility,
  dialogueLineSchema,
  emptyInlineQuestionLine,
  emptySpokenLine,
  emptyStageLine,
  isInlineQuestionLine,
  isSpokenLine,
  isStageLine,
  type DialogueLine,
  type GeneratedLine,
  type InlineQuestionLine,
  type SpokenLine,
  type StageLine,
  type StageVisibility,
} from "@/lib/dialogue/types";
import { LineRevisionDiff } from "@/components/dialogue/line-revision-diff";

// Accepts a bare line array, `{ lines: [...] }` (a scenario body), or a full
// exported scenario file (`{ scenario: { lines: [...] } }`) — the same
// shapes lines already appear in across export/import elsewhere in the app.
function extractLinesArray(parsed: unknown): unknown[] | null {
  if (Array.isArray(parsed)) return parsed;
  if (!parsed || typeof parsed !== "object") return null;
  const obj = parsed as Record<string, unknown>;
  if (Array.isArray(obj.lines)) return obj.lines;
  if (obj.scenario && typeof obj.scenario === "object") {
    const scenario = obj.scenario as Record<string, unknown>;
    if (Array.isArray(scenario.lines)) return scenario.lines;
  }
  return null;
}

export type ReviseContext = {
  setting?: string;
  menuTitle?: string;
  grammarPointIds: string[];
};

function applyRevision(
  original: SpokenLine,
  proposed: GeneratedLine
): SpokenLine {
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

function speakerNamesOf(lines: DialogueLine[]): string[] {
  return [
    ...new Set(
      lines.filter(isSpokenLine).map((line) => line.speaker).filter(Boolean),
    ),
  ];
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
  const importInputRef = useRef<HTMLInputElement>(null);
  const [pasteImportOpen, setPasteImportOpen] = useState(false);
  const [pasteImportText, setPasteImportText] = useState("");

  const initialSpeakers = speakerNamesOf(lines);
  const [speaker1, setSpeaker1] = useState(initialSpeakers[0] ?? "");
  const [speaker2, setSpeaker2] = useState(initialSpeakers[1] ?? "");

  // Lines can be replaced wholesale from outside (generation, whole-dialogue
  // revise). If the current top-of-form names no longer cover what's
  // actually on the lines, resync from the data during render (the
  // React-blessed way to adjust state in response to a prop change).
  // Renaming via the fields below keeps every line in sync, so this never
  // fires from an in-app edit.
  const [prevLines, setPrevLines] = useState(lines);
  if (lines !== prevLines) {
    setPrevLines(lines);
    const distinct = speakerNamesOf(lines);
    const covered = new Set([speaker1, speaker2].filter(Boolean));
    const uncovered = distinct.some((name) => !covered.has(name));
    if (uncovered) {
      setSpeaker1(distinct[0] ?? "");
      setSpeaker2(distinct[1] ?? "");
    }
  }

  const speakerOptions = useMemo(() => {
    const names = new Set<string>();
    if (speaker1) names.add(speaker1);
    if (speaker2) names.add(speaker2);
    for (const line of lines) {
      if (isSpokenLine(line) && line.speaker) names.add(line.speaker);
    }
    return [...names];
  }, [speaker1, speaker2, lines]);

  function renameSpeaker(oldName: string, newName: string) {
    if (!oldName || oldName === newName) return;
    onChange(
      lines.map((line) =>
        isSpokenLine(line) && line.speaker === oldName
          ? { ...line, speaker: newName }
          : line
      )
    );
  }

  function handleSpeaker1Change(value: string) {
    renameSpeaker(speaker1, value);
    setSpeaker1(value);
  }

  function handleSpeaker2Change(value: string) {
    renameSpeaker(speaker2, value);
    setSpeaker2(value);
  }

  function otherSpeakerFor(current?: string) {
    return (
      [speaker1, speaker2].find((name) => name && name !== current) ??
      current ??
      speaker1 ??
      ""
    );
  }

  function lastSpokenSpeaker(beforeIndex?: number) {
    const slice =
      beforeIndex === undefined ? lines : lines.slice(0, beforeIndex + 1);
    for (let i = slice.length - 1; i >= 0; i--) {
      const line = slice[i];
      if (isSpokenLine(line) && line.speaker) return line.speaker;
    }
    return speaker1;
  }

  function updateSpoken(index: number, patch: Partial<SpokenLine>) {
    const line = lines[index];
    if (!isSpokenLine(line)) return;
    const next = lines.slice();
    next[index] = { ...line, ...patch };
    onChange(next);
  }

  function updateStage(index: number, patch: Partial<StageLine>) {
    const line = lines[index];
    if (!isStageLine(line)) return;
    const next = lines.slice();
    next[index] = { ...line, ...patch };
    onChange(next);
  }

  function updateInlineQuestion(
    index: number,
    patch: Partial<InlineQuestionLine>
  ) {
    const line = lines[index];
    if (!isInlineQuestionLine(line)) return;
    const next = lines.slice();
    next[index] = { ...line, ...patch };
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
    onChange([
      ...lines,
      emptySpokenLine(otherSpeakerFor(lastSpokenSpeaker())),
    ]);
  }

  function insertStageAt(index: number) {
    const next = lines.slice();
    next.splice(index, 0, emptyStageLine(defaultStageVisibility(lines, index)));
    onChange(next);
    clearRevisionState();
  }

  function insertInlineQuestionAt(index: number) {
    const next = lines.slice();
    next.splice(index, 0, emptyInlineQuestionLine());
    onChange(next);
    clearRevisionState();
  }

  // Shared by both the file-upload and paste-JSON import paths.
  function importParsedLines(parsed: unknown): boolean {
    const rawLines = extractLinesArray(parsed);
    if (!rawLines) {
      toast.error(
        "Couldn't find a lines array — expected a JSON array of lines, or an object with a `lines` field."
      );
      return false;
    }
    const result = z.array(dialogueLineSchema).safeParse(rawLines);
    if (!result.success) {
      toast.error(`Invalid line data: ${result.error.issues[0]?.message ?? "validation failed"}`);
      return false;
    }
    if (result.data.length === 0) {
      toast.error("No lines found in that JSON.");
      return false;
    }
    const next = result.data;
    onChange(next);
    onLinesCommitted?.(next);
    clearRevisionState();
    toast.success(`Replaced with ${result.data.length} line(s). Save to persist.`);
    return true;
  }

  async function importLinesFromFile(file: File) {
    let parsed: unknown;
    try {
      parsed = JSON.parse(await file.text());
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Invalid JSON.");
      return;
    }
    importParsedLines(parsed);
  }

  function importLinesFromPastedText() {
    let parsed: unknown;
    try {
      parsed = JSON.parse(pasteImportText);
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Invalid JSON.");
      return;
    }
    if (importParsedLines(parsed)) {
      setPasteImportText("");
      setPasteImportOpen(false);
    }
  }

  function insertAfter(index: number) {
    const next = lines.slice();
    next.splice(
      index + 1,
      0,
      emptySpokenLine(otherSpeakerFor(lastSpokenSpeaker(index))),
    );
    onChange(next);
    clearRevisionState();
  }

  // Pending revisions and selections are keyed by index, so any structural
  // change (add/remove/reorder) invalidates them.
  function clearRevisionState() {
    setSelected(new Set());
    setPendingRevisions(new Map());
  }

  function toggleSelected(index: number) {
    const line = lines[index];
    if (!isSpokenLine(line)) return;
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

    const spokenIndices = indices?.filter((i) => isSpokenLine(lines[i])) ?? null;
    if (indices && spokenIndices && spokenIndices.length === 0) {
      toast.error("Select spoken lines to revise. Stage and inline-question rows are skipped.");
      return;
    }

    const scope = spokenIndices ? "selection" : "all";
    setIsRevising(true);
    if (spokenIndices?.length === 1) setRevisingLine(spokenIndices[0]);
    try {
      const { result } = await dialogueApi.reviseLines({
        lines,
        scope,
        selectedIndices: spokenIndices ?? undefined,
        instructions: effectiveInstructions,
        setting: reviseContext.setting,
        menuTitle: reviseContext.menuTitle,
        grammarPointIds: reviseContext.grammarPointIds,
      });
      if (result.scope === "selection") {
        setPendingRevisions((prev) => {
          const next = new Map(prev);
          for (const revision of result.revisions) {
            if (!isSpokenLine(lines[revision.index])) continue;
            next.set(revision.index, revision.line);
          }
          return next;
        });
        toast.success(
          `Proposed ${result.revisions.length} revision(s) — accept or reject each below.`
        );
      } else {
        // Whole-dialogue rewrite may add/remove spoken lines. Keep a leading
        // opener stage line if one was already there.
        const leadingStage: DialogueLine[] = [];
        for (const line of lines) {
          if (isStageLine(line)) leadingStage.push(line);
          else break;
        }
        const nextLines: DialogueLine[] = [
          ...leadingStage,
          ...result.generated.lines.map((line) =>
            applyRevision(emptySpokenLine(line.speaker), line),
          ),
        ];
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
    const current = lines[index];
    if (!proposed || !isSpokenLine(current)) return;
    const next = lines.slice();
    next[index] = applyRevision(current, proposed);
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
      return proposed && isSpokenLine(line)
        ? applyRevision(line, proposed)
        : line;
    });
    onChange(next);
    onLinesCommitted?.(next);
    setPendingRevisions(new Map());
  }

  const reviseEnabled = !!reviseContext && lines.some(isSpokenLine);
  const spokenCount = lines.filter(isSpokenLine).length;

  // A grammar point commonly ends up tagged on multiple lines (e.g. a
  // scenario-wide fallback applied when generating). Only display it on the
  // first line it appears on so it isn't shown as "for this line" everywhere.
  const firstLineForGrammarPoint = new Map<string, number>();
  lines.forEach((line, index) => {
    if (!isSpokenLine(line)) return;
    for (const id of line.grammarPointIDs ?? []) {
      if (!firstLineForGrammarPoint.has(id)) {
        firstLineForGrammarPoint.set(id, index);
      }
    }
  });

  function rowControls(index: number) {
    return (
      <>
        <div className="flex-1" />
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
          onClick={() => insertAfter(index)}
          aria-label="Insert spoken line below"
          title="Insert a spoken line below this one"
        >
          <CornerDownRight className="size-3.5" />
        </Button>
        <Button
          variant="ghost"
          size="icon-sm"
          onClick={() => insertStageAt(index + 1)}
          aria-label="Insert stage below"
          title="Insert a stage line below this one"
        >
          <Clapperboard className="size-3.5" />
        </Button>
        <Button
          variant="ghost"
          size="icon-sm"
          onClick={() => insertInlineQuestionAt(index + 1)}
          aria-label="Insert inline question below"
          title="Insert an inline question below this one"
        >
          <CircleHelp className="size-3.5" />
        </Button>
        <Button
          variant="ghost"
          size="icon-sm"
          onClick={() => remove(index)}
          aria-label="Remove line"
        >
          <Trash2 className="size-3.5" />
        </Button>
      </>
    );
  }

  return (
    <div className="flex flex-col gap-3">
      <Label>Lines</Label>

      <div className="flex flex-col gap-2 rounded-md border border-border/60 p-3 sm:flex-row sm:items-end sm:gap-4">
        <div className="flex flex-1 flex-col gap-1.5">
          <Label className="text-xs">Speaker 1</Label>
          <Input
            value={speaker1}
            onChange={(e) => handleSpeaker1Change(e.target.value)}
            placeholder="e.g. Aiko"
          />
        </div>
        <div className="flex flex-1 flex-col gap-1.5">
          <Label className="text-xs">Speaker 2</Label>
          <Input
            value={speaker2}
            onChange={(e) => handleSpeaker2Change(e.target.value)}
            placeholder="e.g. Ren"
          />
        </div>
      </div>
      <p className="-mt-1 text-xs text-muted-foreground">
        Renaming a speaker here updates every line using that name. Assign
        each line&apos;s speaker from the dropdown below. Stage lines and
        inline questions sit between spoken lines, skip TTS, and do not
        consume a line-switch beat.
      </p>

      {lines.length === 0 && (
        <p className="text-sm text-muted-foreground">
          No lines yet. Add them by hand or generate below. An opener stage line
          can sit before line 1.
        </p>
      )}

      {lines.length > 0 && !isStageLine(lines[0]) && (
        <Button
          variant="outline"
          size="sm"
          className="w-fit gap-2"
          onClick={() => insertStageAt(0)}
        >
          <Clapperboard className="size-4" />
          Insert opener stage line
        </Button>
      )}

      {lines.map((line, index) => {
        if (isInlineQuestionLine(line)) {
          const trimmedChoices = line.choices.filter((choice) => choice.trim());
          return (
            <div
              key={index}
              className="flex flex-col gap-2 rounded-md border border-dashed border-amber-500/40 bg-amber-500/5 p-3"
            >
              <div className="flex items-center gap-2">
                <span className="text-xs font-medium text-amber-800 dark:text-amber-200">
                  Inline question
                </span>
                <Select
                  value={line.layout}
                  onValueChange={(value) => {
                    if (value)
                      updateInlineQuestion(index, {
                        layout: value as "grid" | "list",
                      });
                  }}
                >
                  <SelectTrigger className="w-28">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="grid">Grid</SelectItem>
                    <SelectItem value="list">List</SelectItem>
                  </SelectContent>
                </Select>
                {rowControls(index)}
              </div>
              <Input
                value={line.prompt}
                onChange={(e) =>
                  updateInlineQuestion(index, { prompt: e.target.value })
                }
                placeholder='Prompt — e.g. "Do you know what 家賃 means?"'
              />
              <Input
                value={line.target ?? ""}
                onChange={(e) =>
                  updateInlineQuestion(index, {
                    target: e.target.value || undefined,
                  })
                }
                placeholder="Target word or phrase (optional) — e.g. 家賃"
              />
              <Textarea
                rows={3}
                value={line.choices.join("\n")}
                onChange={(e) => {
                  const choices = e.target.value.split("\n");
                  updateInlineQuestion(index, {
                    choices,
                    correctChoice: choices.includes(line.correctChoice)
                      ? line.correctChoice
                      : "",
                  });
                }}
                placeholder="Choices (one per line)"
              />
              <Select
                value={line.correctChoice || undefined}
                onValueChange={(value) => {
                  if (value)
                    updateInlineQuestion(index, { correctChoice: value });
                }}
              >
                <SelectTrigger className="w-full">
                  <SelectValue placeholder="Correct choice" />
                </SelectTrigger>
                <SelectContent>
                  {trimmedChoices.map((choice) => (
                    <SelectItem key={choice} value={choice}>
                      {choice}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              <Textarea
                rows={2}
                value={line.wrongAnswerExplanation}
                onChange={(e) =>
                  updateInlineQuestion(index, {
                    wrongAnswerExplanation: e.target.value,
                  })
                }
                placeholder="Wrong answer explanation"
              />
              <p className="text-xs text-muted-foreground">
                Playback pauses after the spoken line above this row. A correct
                answer continues the dialogue; a miss shows the explanation
                first.
              </p>
            </div>
          );
        }

        if (isStageLine(line)) {
          return (
            <div
              key={index}
              className="flex flex-col gap-2 rounded-md border border-dashed border-border/80 bg-muted/20 p-3"
            >
              <div className="flex items-center gap-2">
                <span className="text-xs italic text-muted-foreground">
                  Stage
                </span>
                <Select
                  value={line.visibility}
                  onValueChange={(value) =>
                    updateStage(index, {
                      visibility: (value ?? "practice") as StageVisibility,
                    })
                  }
                >
                  <SelectTrigger className="w-44">
                    <SelectValue placeholder="Visibility" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="cold">Cold listen (opener)</SelectItem>
                    <SelectItem value="practice">Practice only</SelectItem>
                  </SelectContent>
                </Select>
                {rowControls(index)}
              </div>
              <Textarea
                rows={2}
                value={line.text}
                onChange={(e) => updateStage(index, { text: e.target.value })}
                placeholder="Kaito knocks at his neighbor's door."
                className="italic"
              />
              <p className="text-xs text-muted-foreground">
                Italic in the transcript. Skipped by TTS. Mid-scene rows use
                Practice only (shadow / speak-as-B); an opener before line 1
                may use Cold listen.
              </p>
            </div>
          );
        }

        return (
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
              <Select
                value={line.speaker || undefined}
                onValueChange={(value) =>
                  updateSpoken(index, { speaker: value ?? "" })
                }
              >
                <SelectTrigger className="w-40">
                  <SelectValue placeholder="Speaker" />
                </SelectTrigger>
                <SelectContent>
                  {speakerOptions.map((name) => (
                    <SelectItem key={name} value={name}>
                      {name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
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
              {rowControls(index)}
            </div>
            <div className="flex flex-col gap-4 sm:flex-row sm:items-start">
              <div className="flex min-w-0 flex-1 flex-col gap-2">
                <Input
                  value={line.japanese}
                  onChange={(e) => updateSpoken(index, { japanese: e.target.value })}
                  placeholder="Japanese"
                />
                <Input
                  value={line.romaji ?? ""}
                  onChange={(e) => updateSpoken(index, { romaji: e.target.value })}
                  placeholder="Romaji"
                />
                <Input
                  value={line.english ?? ""}
                  onChange={(e) => updateSpoken(index, { english: e.target.value })}
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
                          if (!isSpokenLine(l)) return l;
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
                    updateSpoken(index, {
                      grammarPointIDs:
                        grammarPointIDs.length > 0 ? grammarPointIDs : undefined,
                    });
                  }}
                />
              </div>
            </div>
            {pendingRevisions.has(index) && isSpokenLine(line) && (
              <LineRevisionDiff
                original={line}
                proposed={pendingRevisions.get(index)!}
                onAccept={() => acceptRevision(index)}
                onReject={() => rejectRevision(index)}
              />
            )}
          </div>
        );
      })}
      <div className="flex flex-wrap gap-2">
        <Button variant="outline" size="sm" className="gap-2" onClick={add}>
          <Plus className="size-4" />
          Add line
        </Button>
        <Button
          variant="outline"
          size="sm"
          className="gap-2"
          onClick={() => insertStageAt(lines.length)}
        >
          <Clapperboard className="size-4" />
          Add stage line
        </Button>
        <Button
          variant="outline"
          size="sm"
          className="gap-2"
          onClick={() => insertInlineQuestionAt(lines.length)}
        >
          <CircleHelp className="size-4" />
          Add inline question
        </Button>
        <Button
          variant="outline"
          size="sm"
          className="gap-2"
          onClick={() => importInputRef.current?.click()}
        >
          <FileJson className="size-4" />
          Import lines from JSON
        </Button>
        <Button
          variant="outline"
          size="sm"
          className="gap-2"
          onClick={() => setPasteImportOpen((open) => !open)}
        >
          <FileJson className="size-4" />
          Paste JSON
        </Button>
        <input
          ref={importInputRef}
          type="file"
          accept=".json,application/json"
          className="hidden"
          onChange={(e) => {
            const file = e.target.files?.[0];
            if (file) void importLinesFromFile(file);
            e.target.value = "";
          }}
        />
      </div>

      {pasteImportOpen && (
        <div className="flex flex-col gap-2 rounded-md border border-border/60 p-3">
          <Label className="text-xs">Paste lines JSON</Label>
          <Textarea
            rows={8}
            value={pasteImportText}
            onChange={(e) => setPasteImportText(e.target.value)}
            className="font-mono text-xs"
            spellCheck={false}
            placeholder='[{ "speaker": "Aiko", "japanese": "...", "romaji": "...", "english": "..." }]'
          />
          <div className="flex gap-2">
            <Button
              size="sm"
              onClick={importLinesFromPastedText}
              disabled={!pasteImportText.trim()}
            >
              Import
            </Button>
            <Button
              size="sm"
              variant="ghost"
              onClick={() => {
                setPasteImportOpen(false);
                setPasteImportText("");
              }}
            >
              Cancel
            </Button>
          </div>
        </div>
      )}

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
                  selected.size === spokenCount
                    ? new Set()
                    : new Set(
                        lines.flatMap((line, i) =>
                          isSpokenLine(line) ? [i] : [],
                        ),
                      )
                )
              }
            >
              {selected.size === spokenCount ? "Clear selection" : "Select all"}
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
            used as context. Stage lines and inline questions are skipped.
            Proposals appear inline for accept/reject and nothing persists
            until you Save.
          </p>
        </div>
      )}
    </div>
  );
}
