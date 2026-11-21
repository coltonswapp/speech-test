"use client";

import { useState, type FormEvent } from "react";
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

  return <details className="rounded-lg border border-border/60 px-4 py-3 text-sm">
    <summary className="cursor-pointer">Recover a stalled attempt</summary>
    <form onSubmit={recover} className="mt-2 space-y-2">
      <p className="text-muted-foreground">Confirm the dispatch or agent run has stopped before releasing this issue.</p>
      <Label>Reason <Input name="reason" required maxLength={500} /></Label>
      <Button type="submit" variant="destructive" size="sm" disabled={busy}>Stop attempt and release issue</Button>
      {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
    </form>
  </details>;
}
