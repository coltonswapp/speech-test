"use client";

import type { ReactNode } from "react";
import { ChevronRightIcon } from "lucide-react";
import { cn } from "@/lib/utils";
import { usePersistentState } from "@/components/experiments/clips/use-persistent-state";

/**
 * A clip editor section: the title toggles it open/closed (remembered per
 * section), and the header (title, `actions`, `stickyContent` such as a
 * player) sticks under the Studio nav while you scroll through the section.
 */
export function EditorSection({
  id,
  title,
  summary,
  actions,
  stickyContent,
  defaultOpen = true,
  children,
}: {
  /** Storage key suffix for the open/closed state. */
  id: string;
  title: ReactNode;
  /** Shown next to the title when collapsed (e.g. "aligned"). */
  summary?: ReactNode;
  actions?: ReactNode;
  stickyContent?: ReactNode;
  defaultOpen?: boolean;
  children?: ReactNode;
}) {
  const [open, setOpen] = usePersistentState(`experiments.clips.section.${id}`, defaultOpen);

  return (
    <section className="rounded-xl border border-border/60">
      <div
        className={cn(
          // top-14: below the sticky Studio header (h-14).
          "sticky top-14 z-20 flex flex-col gap-2 rounded-xl bg-background/95 px-4 py-3 backdrop-blur",
          open && "rounded-b-none border-b border-border/60"
        )}
      >
        <div className="flex flex-wrap items-center gap-2">
          <button
            type="button"
            onClick={() => setOpen(!open)}
            aria-expanded={open}
            className="mr-auto flex items-center gap-1.5 text-left text-sm font-medium"
          >
            <ChevronRightIcon
              className={cn("size-4 text-muted-foreground transition-transform", open && "rotate-90")}
            />
            {title}
            {!open && summary ? (
              <span className="text-xs font-normal text-muted-foreground">{summary}</span>
            ) : null}
          </button>
          {open ? actions : null}
        </div>
        {open ? stickyContent : null}
      </div>
      {open && children ? <div className="flex flex-col gap-3 p-4">{children}</div> : null}
    </section>
  );
}
