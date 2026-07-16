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
import type { QuizQuestion } from "@/lib/dialogue/types";

export function QuizEditor({
  quiz,
  onChange,
}: {
  quiz: QuizQuestion[] | null;
  onChange: (quiz: QuizQuestion[]) => void;
}) {
  const questions = quiz ?? [];

  function update(index: number, patch: Partial<QuizQuestion>) {
    const next = questions.slice();
    next[index] = { ...next[index], ...patch };
    onChange(next);
  }

  return (
    <div className="flex max-w-2xl flex-col gap-3">
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
