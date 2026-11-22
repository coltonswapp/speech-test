"use client";

import { useState } from "react";
import { CheckIcon, LinkIcon } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { issuePath } from "@/lib/content-issues/subjects";

/** Copies a stable `/content/issues/clip-cfb_…` (or scene) URL for pasting to an agent. */
export function CopyIssueLink({
  issueId,
  label = "Copy link",
  variant = "outline",
  size = "sm",
}: {
  issueId: string;
  label?: string;
  variant?: "outline" | "ghost";
  size?: "sm" | "icon-sm";
}) {
  const [copied, setCopied] = useState(false);

  async function copy(event: React.MouseEvent) {
    event.preventDefault();
    event.stopPropagation();
    const url = `${window.location.origin}${issuePath(issueId)}`;
    try {
      await navigator.clipboard.writeText(url);
      setCopied(true);
      toast.success("Copied link to issue");
      window.setTimeout(() => setCopied(false), 1500);
    } catch {
      toast.error("Couldn’t copy link.");
    }
  }

  const icon = copied ? <CheckIcon /> : <LinkIcon />;
  if (size === "icon-sm") {
    return (
      <Button
        type="button"
        size="icon-sm"
        variant={variant}
        aria-label="Copy link to issue"
        title="Copy link to issue"
        onClick={(event) => void copy(event)}
      >
        {icon}
      </Button>
    );
  }

  return (
    <Button
      type="button"
      size={size}
      variant={variant}
      aria-label="Copy link to issue"
      onClick={(event) => void copy(event)}
    >
      {icon}
      {copied ? "Copied" : label}
    </Button>
  );
}
