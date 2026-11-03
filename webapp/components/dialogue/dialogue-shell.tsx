"use client";

import { useEffect, useState, type ReactNode } from "react";
import { PanelLeft, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  DialogueList,
  type DialogueListScope,
} from "@/components/dialogue/dialogue-list";

type DialogueShellProps = {
  activeId?: string;
  /**
   * Forwarded to DialogueList. Use `unit` on collection / scenario editors so
   * the sidebar only shows sibling lessons in the current unit.
   */
  scope?: DialogueListScope;
  /**
   * When true (scenario / collection / unit editor routes), hide the w-80
   * lesson outline below `studio-split` (1280px) and offer a Lessons drawer
   * to reopen it. At `studio-split`+ the side-by-side desktop layout is
   * unchanged.
   */
  collapseSidebarOnMobile?: boolean;
  children?: ReactNode;
};

export function DialogueShell({
  activeId,
  scope = "all",
  collapseSidebarOnMobile = false,
  children,
}: DialogueShellProps) {
  const [mobileOpen, setMobileOpen] = useState(false);
  const [drawerForId, setDrawerForId] = useState(activeId);

  // Close the drawer after navigating to another lesson/collection.
  if (drawerForId !== activeId) {
    setDrawerForId(activeId);
    setMobileOpen(false);
  }

  useEffect(() => {
    if (!mobileOpen) return;
    const previous = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = previous;
    };
  }, [mobileOpen]);

  return (
    <div className="relative flex min-w-0 flex-1 flex-col gap-4 studio-split:flex-row studio-split:gap-6">
      {/* Wide desktop: persistent sidebar */}
      <div className="hidden studio-split:block">
        <DialogueList activeId={activeId} scope={scope} />
      </div>

      {/* Narrow / Tesla / tablet index: full-width list (no editor competing) */}
      {!collapseSidebarOnMobile && (
        <div className="studio-split:hidden">
          <DialogueList
            activeId={activeId}
            scope={scope}
            className="w-full border-r-0 pr-0"
          />
        </div>
      )}

      {/* Editor routes: slide-over lessons drawer (mounted only while open) */}
      {collapseSidebarOnMobile && mobileOpen && (
        <>
          <div
            className="fixed inset-0 z-40 bg-black/40 studio-split:hidden"
            onClick={() => setMobileOpen(false)}
            aria-hidden="true"
          />
          <div
            className="fixed inset-y-0 left-0 z-50 flex w-[min(20rem,85vw)] max-w-xs translate-x-0 flex-col bg-background p-4 shadow-xl studio-split:hidden"
            role="dialog"
            aria-modal="true"
            aria-label="Lessons"
          >
            <div className="mb-3 flex items-center justify-between gap-2">
              <span className="text-sm font-semibold">Lessons</span>
              <Button
                type="button"
                variant="ghost"
                size="sm"
                className="shrink-0"
                onClick={() => setMobileOpen(false)}
                aria-label="Close lessons list"
              >
                <X className="size-4" />
              </Button>
            </div>
            <div className="min-h-0 flex-1 overflow-y-auto">
              <DialogueList
                activeId={activeId}
                scope={scope}
                className="h-full w-full border-r-0 pr-0"
              />
            </div>
          </div>
        </>
      )}

      <div className="flex min-w-0 flex-1 flex-col gap-3">
        {collapseSidebarOnMobile && (
          <div className="flex studio-split:hidden">
            <Button
              type="button"
              variant="outline"
              size="sm"
              className="gap-2"
              onClick={() => setMobileOpen(true)}
            >
              <PanelLeft className="size-4" />
              Lessons
            </Button>
          </div>
        )}
        {children}
      </div>
    </div>
  );
}
