"use client";

import { formatIssueDate } from "@/lib/content-issues/labels";

/** Formats in the viewer's time zone; the server render may differ, so hydration warnings are expected. */
export function LocalTime({ iso, className }: { iso: string | null | undefined; className?: string }) {
  return (
    <time dateTime={iso ?? undefined} className={className} suppressHydrationWarning>
      {formatIssueDate(iso)}
    </time>
  );
}
