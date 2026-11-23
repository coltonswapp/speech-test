"use client";

import Link from "next/link";
import { toast } from "sonner";
import { cn } from "@/lib/utils";

/** First 8 chars, matching clip-feedback's "From …" chip. */
export function shortReporterId(userId: string): string {
  return userId.length <= 8 ? userId : userId.slice(0, 8);
}

export function usageUserHref(userId: string): string {
  return `/usage?uid=${encodeURIComponent(userId)}`;
}

/**
 * Muted short uid; full id on hover. Click copies. On the detail page, pass
 * `href` to Usage so cmd/ctrl-click (or open in new tab) looks the user up.
 */
export function IssueReporter({
  userId,
  href,
  className,
}: {
  userId?: string | null;
  href?: string;
  className?: string;
}) {
  if (!userId) return null;
  const id = userId;
  const short = shortReporterId(id);

  async function copy(event: React.MouseEvent) {
    event.stopPropagation();
    // Unmodified click copies and stays put (the row is itself a link).
    // Cmd/ctrl-click follows `href` to Usage.
    if (!event.metaKey && !event.ctrlKey) event.preventDefault();
    try {
      await navigator.clipboard.writeText(id);
      toast.success("Copied reporter uid");
    } catch {
      toast.error("Couldn’t copy uid.");
    }
  }

  const classes = cn(
    "font-mono text-muted-foreground hover:text-foreground hover:underline",
    className,
  );

  if (href) {
    return (
      <Link href={href} title={userId} onClick={copy} className={classes}>
        {short}
      </Link>
    );
  }

  return (
    <span title={userId} onClick={copy} className={cn(classes, "cursor-copy")}>
      {short}
    </span>
  );
}
