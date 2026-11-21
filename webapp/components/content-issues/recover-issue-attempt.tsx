"use client";

import { useState, type FormEvent } from "react";
import { ChevronRightIcon, Loader2Icon } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

export function RecoverIssueAttempt({ issueId, attemptId, onChange }: {
  issueId: string;
  attemptId: string;
  onChange: () => void;
}) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  async function recover(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = event.currentTarget;
    const reason = String(new FormData(form).get("reason") ?? "").trim();
    if (!reason || busy) return;
    setBusy(true);
    setError("");
    try {
      const response = await fetch("/api/content/issues/" + encodeURIComponent(issueId), {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "recover", attemptId, reason }),
      });
      if (!response.ok) throw new Error((await response.json()).error);
      form.reset();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Unable to recover attempt");
    } finally {
      setBusy(false);
      onChange();
    }
  }

  const inputId = `recover-reason-${attemptId}`;
  return (
    <details className="group rounded-xl border border-border/60">
      <summary className="flex cursor-pointer list-none items-center gap-1.5 px-4 py-3 text-sm font-medium [&::-webkit-details-marker]:hidden">
        <ChevronRightIcon className="size-4 text-muted-foreground transition-transform group-open:rotate-90" />
        Recover a stalled attempt
      </summary>
      <form onSubmit={recover} className="flex flex-col gap-3 border-t border-border/60 p-4">
        <p className="text-xs text-muted-foreground">
          Confirm the dispatch or agent run has stopped before releasing this issue.
        </p>
        <div className="flex flex-col gap-1.5">
          <Label htmlFor={inputId} className="text-xs">Reason</Label>
          <Input id={inputId} name="reason" required maxLength={500} placeholder="e.g. Run crashed, no output" />
        </div>
        <Button type="submit" size="sm" variant="destructive" disabled={busy} className="self-start">
          {busy ? <Loader2Icon className="animate-spin" /> : null}
          Stop attempt and release issue
        </Button>
        {error ? <p role="alert" className="text-sm text-destructive">{error}</p> : null}
      </form>
    </details>
  );
}
