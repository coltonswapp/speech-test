"use client";

import { useEffect, useState, type ReactNode } from "react";
import { PanelLeft, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { DialogueList } from "@/components/dialogue/dialogue-list";

type DialogueShellProps = {
  activeId?: string;
  /**
   * When true (scenario / collection editor routes), hide the w-80 sidebar on
   * small screens by default and offer a Lessons drawer to reopen it.
   * On md+ the side-by-side layout is unchanged.
   */
  collapseSidebarOnMobile?: boolean;
  children?: ReactNode;
};

export function DialogueShell({
  activeId,
  collapseSidebarOnMobile = false,
  children,
}: DialogueShellProps) {
  const [mobileOpen, setMobileOpen] = useState(false);

  // Close the drawer after navigating to another lesson/collection.
  useEffect(() => {
    setMobileOpen(false);
  }, [activeId]);

  useEffect(() => {
    if (!mobileOpen) return;
    const previous = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = previous;
    };
  }, [mobileOpen]);

  return (
    <div className="relative flex min-w-0 flex-1 flex-col gap-4 md:flex-row md:gap-6">
      {/* Desktop / tablet: persistent sidebar */}
      <div className="hidden md:block">
        <DialogueList activeId={activeId} />
      </div>

      {/* Phone index route: full-width list (no editor competing for space) */}
      {!collapseSidebarOnMobile && (
        <div className="md:hidden">
          <DialogueList
            activeId={activeId}
            className="w-full border-r-0 pr-0"
          />
        </div>
      )}

      {/* Phone editor routes: slide-over lessons drawer (mounted only while open) */}
      {collapseSidebarOnMobile && mobileOpen && (
        <>
          <div
            className="fixed inset-0 z-40 bg-black/40 md:hidden"
            onClick={() => setMobileOpen(false)}
            aria-hidden="true"
          />
          <div
            className="fixed inset-y-0 left-0 z-50 flex w-[min(20rem,85vw)] translate-x-0 flex-col bg-background p-4 shadow-xl md:hidden"
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
                className="h-full w-full border-r-0 pr-0"
              />
            </div>
          </div>
        </>
      )}

      <div className="flex min-w-0 flex-1 flex-col gap-3">
        {collapseSidebarOnMobile && (
          <div className="flex md:hidden">
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
