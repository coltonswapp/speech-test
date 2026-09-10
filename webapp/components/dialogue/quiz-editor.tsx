"use client";

import { Plus, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { GenerateQuizPanel } from "@/components/dialogue/generate-quiz-panel";
import {
  isInlineQuestionLine,
  isSpokenLine,
  isStageLine,
  spokenLinesOf,
  type DialogueLine,
  type QuizQuestion,
  type SpokenLine,
} from "@/lib/dialogue/types";

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

export function QuizEditor({
  quiz,
  onChange,
  lines = [],
  setting,
  menuTitle,
}: {
  quiz: QuizQuestion[] | null;
  onChange: (quiz: QuizQuestion[]) => void;
  /** Dialogue lines, shown as a reference panel so quiz questions can be written against the actual text. */
  lines?: DialogueLine[];
  setting?: string | null;
  menuTitle?: string;
}) {
  const questions = quiz ?? [];
  const spokenLines = spokenLinesOf(lines);

  function update(index: number, patch: Partial<QuizQuestion>) {
    const next = questions.slice();
    next[index] = { ...next[index], ...patch };
    onChange(next);
  }

  function setSourceSpokenStart(index: number, raw: string) {
    if (raw === NONE_VALUE) {
      update(index, {
        sourceSpokenStart: undefined,
        sourceSpokenEnd: undefined,
      });
      return;
    }
    const start = Number.parseInt(raw, 10);
    if (!Number.isFinite(start)) return;
    const current = questions[index];
    update(index, {
      sourceSpokenStart: start,
      sourceSpokenEnd: clampSpokenEnd(start, current.sourceSpokenEnd),
    });
  }

  function setSourceSpokenEnd(index: number, raw: string) {
    if (raw === NONE_VALUE) {
      update(index, { sourceSpokenEnd: undefined });
      return;
    }
    const end = Number.parseInt(raw, 10);
    if (!Number.isFinite(end)) return;
    const start = questions[index].sourceSpokenStart;
    if (start === undefined) return;
    update(index, {
      sourceSpokenEnd: end < start ? undefined : end,
    });
  }

  return (
    <div className="flex max-w-2xl flex-col gap-3">
      {lines.length > 0 && (
        <div className="flex flex-col gap-1.5 rounded-md border border-border/60 bg-muted/30 p-3">
          <Label className="text-xs text-muted-foreground">
            Dialogue lines (reference)
          </Label>
          <div className="flex max-h-56 flex-col gap-1.5 overflow-y-auto pr-1">
            {lines.map((line, index) => (
              <p key={index} className="text-sm leading-snug">
                {isStageLine(line) ? (
                  <span className="italic text-muted-foreground">
                    {line.text}
                  </span>
                ) : isInlineQuestionLine(line) ? (
                  <span className="text-muted-foreground">
                    Inline question
                    {line.target?.trim() ? ` · ${line.target.trim()}` : ""}
                    {line.prompt.trim() ? ` — ${line.prompt}` : ""}
                  </span>
                ) : (
                  <>
                    <span className="text-muted-foreground">
                      {line.speaker ? `${line.speaker}: ` : ""}
                    </span>
                    <span>{line.japanese}</span>
                    {isSpokenLine(line) && line.english && (
                      <span className="text-muted-foreground">
                        {" "}
                        — {line.english}
                      </span>
                    )}
                  </>
                )}
              </p>
            ))}
          </div>
        </div>
      )}
      <GenerateQuizPanel
        lines={lines}
        setting={setting}
        menuTitle={menuTitle}
        existingQuiz={questions}
        onInsert={(generated) => onChange([...questions, ...generated])}
      />
      <Label>Quiz questions</Label>
      {questions.length === 0 && (
        <p className="text-sm text-muted-foreground">
          No quiz questions. Scenarios without a quiz are fine — the field is
          omitted on export.
        </p>
      )}
      {questions.map((question, index) => (
        <div
          key={index}
          className="flex flex-col gap-2 rounded-md border border-border/60 p-3"
        >
          <div className="flex items-center gap-2">
            <span className="text-xs text-muted-foreground">#{index + 1}</span>
            <div className="flex-1" />
            <Select
              value={question.layout}
              onValueChange={(value) => {
                if (value) update(index, { layout: value as "grid" | "list" });
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
            <Button
              variant="ghost"
              size="icon-sm"
              onClick={() => onChange(questions.filter((_, i) => i !== index))}
              aria-label="Remove question"
            >
              <Trash2 className="size-3.5" />
            </Button>
          </div>
          <Input
            value={question.prompt}
            onChange={(e) => update(index, { prompt: e.target.value })}
            placeholder="Prompt"
          />
          <Textarea
            rows={3}
            value={question.choices.join("\n")}
            onChange={(e) => {
              const choices = e.target.value.split("\n");
              update(index, {
                choices,
                correctChoice: choices.includes(question.correctChoice)
                  ? question.correctChoice
                  : "",
              });
            }}
            placeholder="Choices (one per line)"
          />
          <Select
            value={question.correctChoice || undefined}
            onValueChange={(value) => {
              if (value) update(index, { correctChoice: value });
            }}
          >
            <SelectTrigger className="w-full">
              <SelectValue placeholder="Correct choice" />
            </SelectTrigger>
            <SelectContent>
              {question.choices
                .filter((choice) => choice.trim())
                .map((choice) => (
                  <SelectItem key={choice} value={choice}>
                    {choice}
                  </SelectItem>
                ))}
            </SelectContent>
          </Select>
          <Textarea
            rows={2}
            value={question.wrongAnswerExplanation}
            onChange={(e) =>
              update(index, { wrongAnswerExplanation: e.target.value })
            }
            placeholder="Wrong answer explanation"
          />
          <div className="flex flex-col gap-2 rounded-md border border-dashed border-border/60 bg-muted/20 p-2.5">
            <Label className="text-xs text-muted-foreground">
              Dialogue evidence (spoken lines)
            </Label>
            <p className="text-xs text-muted-foreground">
              After the learner answers, the app plays this spoken segment and
              shows the Japanese line(s). Indices match TTS / spoken-only order
              (stage and inline-question rows are skipped).
            </p>
            {spokenLines.length === 0 ? (
              <p className="text-xs text-muted-foreground">
                Add spoken dialogue lines to link evidence.
              </p>
            ) : (
              <div className="grid gap-2 sm:grid-cols-2">
                <div className="flex flex-col gap-1.5">
                  <Label className="text-xs">Start</Label>
                  <Select
                    value={
                      question.sourceSpokenStart !== undefined
                        ? String(question.sourceSpokenStart)
                        : NONE_VALUE
                    }
                    onValueChange={(value) => {
                      if (value) setSourceSpokenStart(index, value);
                    }}
                  >
                    <SelectTrigger className="w-full">
                      <SelectValue placeholder="No link" />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value={NONE_VALUE}>No link</SelectItem>
                      {spokenLines.map((line, spokenIndex) => (
                        <SelectItem
                          key={spokenIndex}
                          value={String(spokenIndex)}
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
                      question.sourceSpokenEnd !== undefined
                        ? String(question.sourceSpokenEnd)
                        : NONE_VALUE
                    }
                    onValueChange={(value) => {
                      if (value) setSourceSpokenEnd(index, value);
                    }}
                    disabled={question.sourceSpokenStart === undefined}
                  >
                    <SelectTrigger className="w-full">
                      <SelectValue placeholder="Same as start" />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value={NONE_VALUE}>Same as start</SelectItem>
                      {spokenLines
                        .map((line, spokenIndex) => ({ line, spokenIndex }))
                        .filter(
                          ({ spokenIndex }) =>
                            spokenIndex >= (question.sourceSpokenStart ?? 0),
                        )
                        .map(({ line, spokenIndex }) => (
                          <SelectItem
                            key={spokenIndex}
                            value={String(spokenIndex)}
                          >
                            {spokenLineLabel(line, spokenIndex)}
                          </SelectItem>
                        ))}
                    </SelectContent>
                  </Select>
                </div>
              </div>
            )}
          </div>
        </div>
      ))}
      <Button
        variant="outline"
        size="sm"
        className="w-fit gap-2"
        onClick={() =>
          onChange([
            ...questions,
            {
              prompt: "",
              layout: "grid",
              choices: [],
              correctChoice: "",
              wrongAnswerExplanation: "",
            },
          ])
        }
      >
        <Plus className="size-4" />
        Add question
      </Button>
    </div>
  );
}
