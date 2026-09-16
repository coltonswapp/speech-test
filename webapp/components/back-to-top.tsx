"use client";

import { useEffect, useState } from "react";
import { ArrowUpIcon } from "lucide-react";

import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";

const SHOW_AFTER_PX = 400;

export function BackToTop() {
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    const onScroll = () => {
      setVisible(window.scrollY > SHOW_AFTER_PX);
    };
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  return (
    <Button
      type="button"
      variant="outline"
      size="icon"
      aria-label="Back to top"
      tabIndex={visible ? 0 : -1}
      aria-hidden={!visible}
      className={cn(
        "fixed right-6 bottom-20 z-50 border-border/80 bg-background/95 shadow-md backdrop-blur",
        "transition-opacity motion-reduce:transition-none",
        visible
          ? "pointer-events-auto opacity-100"
          : "pointer-events-none opacity-0"
      )}
      onClick={() => window.scrollTo({ top: 0, left: 0, behavior: "auto" })}
    >
      <ArrowUpIcon className="size-4" />
    </Button>
  );
}
