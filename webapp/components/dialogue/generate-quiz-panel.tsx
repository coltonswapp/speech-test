"use client";

import { useState } from "react";
import { Sparkles } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { dialogueApi } from "@/lib/dialogue/client";
import { hasSpokenJapanese, type DialogueLine, type QuizQuestion } from "@/lib/dialogue/types";

const CANDIDATE_COUNT = 6;

export function GenerateQuizPanel({
  lines,
  setting,
  menuTitle,
  existingQuiz,
  onInsert,
}: {
  lines: DialogueLine[];
  setting?: string | null;
  menuTitle?: string;
  existingQuiz: QuizQuestion[];
  onInsert: (questions: QuizQuestion[]) => void;
}) {
  const [candidates, setCandidates] = useState<QuizQuestion[]>([]);
  const [selected, setSelected] = useState<Set<number>>(new Set());
  const [isGenerating, setIsGenerating] = useState(false);

  const canGenerate = hasSpokenJapanese(lines);

  async function generate() {
    setIsGenerating(true);
    try {
      const { generated } = await dialogueApi.generateQuiz({
        lines,
        setting: setting ?? undefined,
        menuTitle,
        existingQuiz: existingQuiz.length > 0 ? existingQuiz : undefined,
        count: CANDIDATE_COUNT,
      });
      setCandidates(generated.questions);
      setSelected(new Set(generated.questions.map((_, index) => index)));
    } catch (error) {
      toast.error(
        error instanceof Error ? error.message : "Quiz generation failed.",
      );
    } finally {
      setIsGenerating(false);
    }
  }

  function toggle(index: number) {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(index)) next.delete(index);
      else next.add(index);
      return next;
    });
  }

  function addSelected() {
    const chosen = candidates.filter((_, index) => selected.has(index));
    if (chosen.length === 0) return;
    onInsert(chosen);
    toast.success(
      `Added ${chosen.length} question(s) to the quiz. Save to persist.`,
    );
    setCandidates([]);
    setSelected(new Set());
  }

  return (
    <div className="flex flex-col gap-3 rounded-md border border-border/60 p-3">
      <div className="flex items-center gap-2">
        <Sparkles className="size-4 text-muted-foreground" />
        <Label>Generate quiz questions with Gemini</Label>
      </div>

      <div className="flex flex-wrap items-center gap-2">
        <Button
          size="sm"
          onClick={() => void generate()}
          disabled={isGenerating || !canGenerate}
        >
          {isGenerating ? "Generating…" : `Generate ${CANDIDATE_COUNT} options`}
        </Button>
        {candidates.length > 0 && (
          <Button
            size="sm"
            variant="ghost"
            onClick={() => {
              setCandidates([]);
              setSelected(new Set());
            }}
            disabled={isGenerating}
          >
            Clear options
          </Button>
        )}
      </div>
      {!canGenerate && (
        <p className="text-xs text-muted-foreground">
          Add dialogue lines first — questions are generated from the
          conversation.
        </p>
      )}

      {candidates.length > 0 && (
        <div className="flex flex-col gap-2">
          {candidates.map((question, index) => (
            <label
              key={index}
              className="flex cursor-pointer items-start gap-2 rounded-md border border-border/60 p-2.5 has-[:checked]:border-foreground/40 has-[:checked]:bg-muted/40"
            >
              <input
                type="checkbox"
                className="mt-1 size-4 accent-primary"
                checked={selected.has(index)}
                onChange={() => toggle(index)}
              />
              <div className="flex flex-col gap-1 text-sm">
                <span className="font-medium">{question.prompt}</span>
                <span className="text-xs text-muted-foreground">
                  {question.choices.join(" · ")}
                </span>
                <span className="text-xs text-muted-foreground">
                  Correct: {question.correctChoice}
                </span>
              </div>
            </label>
          ))}
          <Button
            size="sm"
            className="w-fit"
            onClick={addSelected}
            disabled={selected.size === 0}
          >
            Add {selected.size} selected
          </Button>
        </div>
      )}
    </div>
  );
}
