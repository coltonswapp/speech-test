"use client";

import { useEffect, useRef, useState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  mergeWithNext,
  setReading,
  splitOffsets,
  splitToken,
  type EditableToken,
} from "@/lib/experiments/clips/token-edits";

/**
 * Pop-up for one token in the clip Review panel: split (in half or at a
 * chosen point), merge with the next token, or set its reading. Calls
 * `onApply` with the sentence's new token list.
 */
export function TokenEditMenu({
  x,
  y,
  sentenceText,
  tokens,
  index,
  onApply,
  onClose,
}: {
  x: number;
  y: number;
  sentenceText: string;
  tokens: EditableToken[];
  index: number;
  onApply: (tokens: EditableToken[]) => void;
  onClose: () => void;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const token = tokens[index];
  const [mode, setMode] = useState<"menu" | "split" | "reading">("menu");
  const [reading, setReadingText] = useState(token?.reading ?? "");

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") onClose();
    };
    const onPointer = (event: PointerEvent) => {
      if (!ref.current?.contains(event.target as Node)) onClose();
    };
    window.addEventListener("keydown", onKey);
    window.addEventListener("pointerdown", onPointer, true);
    return () => {
      window.removeEventListener("keydown", onKey);
      window.removeEventListener("pointerdown", onPointer, true);
    };
  }, [onClose]);

  if (!token) return null;
  const offsets = splitOffsets(token.text);
  const half = offsets.length > 0 ? offsets[Math.floor((offsets.length - 1) / 2)] : null;
  const merged = mergeWithNext(sentenceText, tokens, index);
  const apply = (next: EditableToken[] | null) => {
    if (next) onApply(next);
  };

  const left = Math.min(x, typeof window !== "undefined" ? window.innerWidth - 240 : x);
  const top = Math.min(y, typeof window !== "undefined" ? window.innerHeight - 180 : y);
  const item =
    "flex w-full rounded-sm px-2 py-1.5 text-left text-sm hover:bg-accent disabled:pointer-events-none disabled:opacity-50";

  return (
    <div
      ref={ref}
      role="menu"
      className="fixed z-50 min-w-[13rem] rounded-md border bg-popover p-1 text-popover-foreground shadow-md"
      style={{ left, top }}
    >
      <p className="px-2 pt-1 pb-1.5 text-xs text-muted-foreground" lang="ja">
        {token.text}
        {token.reading ? ` · ${token.reading}` : " · no reading"}
      </p>
      {mode === "menu" ? (
        <>
          <button
            type="button"
            role="menuitem"
            className={item}
            disabled={half === null}
            onClick={() => half !== null && apply(splitToken(tokens, index, half))}
          >
            Split in half
          </button>
          <button
            type="button"
            role="menuitem"
            className={item}
            disabled={offsets.length === 0}
            onClick={() => setMode("split")}
          >
            Split at…
          </button>
          <button
            type="button"
            role="menuitem"
            className={item}
            disabled={!merged}
            title={merged ? undefined : "Last token, or punctuation separates them"}
            onClick={() => apply(merged)}
          >
            Merge with next
          </button>
          <button type="button" role="menuitem" className={item} onClick={() => setMode("reading")}>
            Edit reading…
          </button>
        </>
      ) : mode === "split" ? (
        <div className="flex flex-col gap-1.5 p-1">
          <p className="text-[11px] text-muted-foreground">Click between characters to split</p>
          <div className="flex flex-wrap items-center text-base" lang="ja">
            {[0, ...offsets].map((start, i, all) => {
              const end = all[i + 1] ?? token.text.length;
              const isLast = i === all.length - 1;
              return (
                <span key={start} className="inline-flex items-center">
                  <span className="px-0.5">{token.text.slice(start, end)}</span>
                  {!isLast ? (
                    <button
                      type="button"
                      title={`Split after “${token.text.slice(0, end)}”`}
                      className="mx-px h-6 w-2 rounded-sm bg-border hover:bg-primary"
                      onClick={() => apply(splitToken(tokens, index, end))}
                    />
                  ) : null}
                </span>
              );
            })}
          </div>
          <BackButton onClick={() => setMode("menu")} />
        </div>
      ) : (
        <form
          className="flex flex-col gap-1.5 p-1"
          onSubmit={(event) => {
            event.preventDefault();
            apply(setReading(tokens, index, reading));
          }}
        >
          <p className="text-[11px] text-muted-foreground">Kana reading (empty to clear)</p>
          <Input
            autoFocus
            lang="ja"
            value={reading}
            onChange={(event) => setReadingText(event.target.value)}
            placeholder="ゆうめい"
          />
          <div className="flex gap-1">
            <Button type="submit" size="sm">
              Save
            </Button>
            <BackButton onClick={() => setMode("menu")} />
          </div>
        </form>
      )}
    </div>
  );
}

function BackButton({ onClick }: { onClick: () => void }) {
  return (
    <button
      type="button"
      className="self-start rounded-sm px-2 py-1 text-xs text-muted-foreground hover:bg-accent hover:text-foreground"
      onClick={onClick}
    >
      Back
    </button>
  );
}
