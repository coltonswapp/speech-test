"use client";

import { useState } from "react";
import { CheckIcon, PlayIcon } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { cn } from "@/lib/utils";
import { formatTimecode } from "@/components/experiments/clips/clip-format";
import { TokenEditMenu } from "@/components/experiments/clips/token-edit-menu";
import type { ClipDraft } from "@/lib/experiments/clips/types";
import type { EditableToken } from "@/lib/experiments/clips/token-edits";

/** Aligner scores below this are worth a listen (they don't predict error well). */
export const LOW_SCORE = 0.3;

/** `${sentence}:${token}` — the key `active` and `data-token-key` use. */
export const tokenKey = (sentence: number, token: number) => `${sentence}:${token}`;

/**
 * A clip's sentences as token chips: reading above, surface, start time below.
 * Click plays from a token (or opens the split / merge / reading menu while
 * `editing`); right-click always opens the menu. Shared by the clip editor's
 * Review section and the whole-video page. Times passed to `onPlay` are
 * clip-relative with the onset shift applied (what clip.wav plays at).
 */
export function ClipTokenLines({
  draft,
  active,
  editing,
  disabled,
  saving,
  onPlay,
  onEditTokens,
  onClearFlags,
  english,
}: {
  draft: ClipDraft;
  /** tokenKey of the token under the playhead, or null. */
  active: string | null;
  editing: boolean;
  disabled: boolean;
  /** A token edit is being saved: blocks further edits. */
  saving: boolean;
  /** Play from `clipSeconds`; with `stopAt`, pause there (one line). */
  onPlay: (clipSeconds: number, stopAt?: number) => void;
  onEditTokens: (sentence: number, tokens: EditableToken[]) => void;
  onClearFlags: (sentence: number, cleared: boolean) => void;
  /** When set, each line's English is an input instead of text. */
  english?: { values: string[]; onChange: (sentence: number, value: string) => void };
}) {
  const [menu, setMenu] = useState<{ sentence: number; token: number; x: number; y: number } | null>(
    null
  );
  const openMenu = (sentence: number, token: number, x: number, y: number) =>
    setMenu({ sentence, token, x, y: y + 8 });

  const toVideo = (clipSeconds: number) =>
    formatTimecode(draft.startSec + clipSeconds + draft.shiftSec);

  return (
    <>
      {menu && draft.sentences[menu.sentence]?.tokens ? (
        <TokenEditMenu
          key={`${menu.sentence}:${menu.token}`}
          x={menu.x}
          y={menu.y}
          sentenceText={draft.sentences[menu.sentence].text}
          tokens={(draft.sentences[menu.sentence].tokens ?? []).map((t) => ({
            text: t.text,
            ...(t.reading ? { reading: t.reading } : {}),
          }))}
          index={menu.token}
          onClose={() => setMenu(null)}
          onApply={(tokens) => {
            const sentence = menu.sentence;
            setMenu(null);
            onEditTokens(sentence, tokens);
          }}
        />
      ) : null}
      <ol className="flex flex-col gap-4">
        {draft.sentences.map((sentence, i) => {
          const first = sentence.tokens?.[0]?.startSec;
          const last = sentence.tokens?.at(-1)?.endSec;
          const flagCount = (sentence.tokens ?? []).filter(
            (t) => t.readingFallback || (t.score !== undefined && t.score < LOW_SCORE)
          ).length;
          return (
            <li key={i} className="flex flex-col gap-1.5">
              <div className="flex items-center gap-2 text-xs text-muted-foreground">
                {first !== undefined && last !== undefined ? (
                  <Button
                    type="button"
                    variant="ghost"
                    size="icon-sm"
                    aria-label={`Play line ${i + 1}`}
                    title="Play this line"
                    onClick={() => onPlay(first + draft.shiftSec, last + draft.shiftSec + 0.15)}
                  >
                    <PlayIcon />
                  </Button>
                ) : null}
                <span>#{i + 1}</span>
                {first !== undefined ? (
                  <button
                    type="button"
                    className="font-mono hover:text-foreground"
                    onClick={() => onPlay(first + draft.shiftSec)}
                  >
                    {toVideo(first)}
                  </button>
                ) : null}
                {sentence.score !== undefined ? (
                  <Badge variant={sentence.score < LOW_SCORE ? "destructive" : "outline"}>
                    line {sentence.score.toFixed(2)}
                  </Badge>
                ) : null}
                {sentence.basicSplit ? (
                  <Badge
                    variant="outline"
                    className="border-amber-500/60 text-amber-700 dark:text-amber-400"
                    title="Gemini couldn't segment this line, so it got a plain word split. Check the tokens (merge, split, readings); editing them clears this."
                  >
                    basic split
                  </Badge>
                ) : null}
              </div>
              <div className="flex flex-wrap gap-1" lang="ja">
                {(sentence.tokens ?? []).map((token, j) => {
                  const key = tokenKey(i, j);
                  const isActive = active === key;
                  const timed = token.startSec !== undefined && token.endSec !== undefined;
                  const weak =
                    !sentence.flagsCleared &&
                    (token.readingFallback || (token.score !== undefined && token.score < LOW_SCORE));
                  return (
                    <button
                      key={key}
                      type="button"
                      data-token-key={key}
                      disabled={editing && (disabled || saving)}
                      onContextMenu={(event) => {
                        if (disabled || saving) return;
                        event.preventDefault();
                        openMenu(i, j, event.clientX, event.clientY);
                      }}
                      onClick={(event) => {
                        if (editing) {
                          openMenu(i, j, event.clientX, event.clientY);
                          return;
                        }
                        if (timed) onPlay(token.startSec! + draft.shiftSec);
                      }}
                      title={
                        timed
                          ? `${toVideo(token.startSec!)} → ${toVideo(token.endSec!)} · score ${token.score?.toFixed(2)}${token.readingFallback ? " · reading fallback" : ""}`
                          : undefined
                      }
                      className={cn(
                        "flex flex-col items-center rounded-md border px-1.5 py-0.5 transition-colors",
                        isActive
                          ? "border-primary bg-primary text-primary-foreground"
                          : weak
                            ? "border-amber-500/60 bg-amber-500/10"
                            : "border-border/60 hover:bg-muted",
                        !timed && !editing && "cursor-default",
                        editing && "border-dashed hover:border-primary"
                      )}
                    >
                      <span
                        className={cn(
                          "text-[10px] leading-tight",
                          isActive ? "text-primary-foreground/80" : "text-muted-foreground"
                        )}
                      >
                        {token.reading ?? " "}
                      </span>
                      <span className="text-base leading-tight">{token.text}</span>
                      {timed ? (
                        <span
                          className={cn(
                            "font-mono text-[10px] leading-tight",
                            isActive ? "text-primary-foreground/80" : "text-muted-foreground"
                          )}
                        >
                          {(token.startSec! + draft.shiftSec).toFixed(2)}
                        </span>
                      ) : null}
                    </button>
                  );
                })}
                {flagCount > 0 ? (
                  <Button
                    type="button"
                    variant="ghost"
                    size="sm"
                    className="self-center text-xs text-muted-foreground"
                    disabled={disabled}
                    title={
                      sentence.flagsCleared
                        ? "Show this line's warnings again"
                        : "Looks right: hide this line's orange warnings"
                    }
                    onClick={() => onClearFlags(i, !sentence.flagsCleared)}
                  >
                    <CheckIcon />
                    {sentence.flagsCleared ? "Reviewed" : `Clear ${flagCount} flag${flagCount === 1 ? "" : "s"}`}
                  </Button>
                ) : null}
              </div>
              {english ? (
                <Input
                  value={english.values[i] ?? ""}
                  placeholder="English"
                  disabled={disabled}
                  onChange={(e) => english.onChange(i, e.target.value)}
                />
              ) : sentence.en ? (
                <p className="text-sm text-muted-foreground">{sentence.en}</p>
              ) : null}
            </li>
          );
        })}
      </ol>
    </>
  );
}
