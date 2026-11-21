"use client";

import { useState, type FormEvent } from "react";

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

  return <details className="rounded border p-3">
    <summary className="cursor-pointer">Recover a stalled attempt</summary>
    <form onSubmit={recover} className="mt-2 space-y-2">
      <p>Confirm the dispatch or agent run has stopped before releasing this issue.</p>
      <label className="block">Reason <input name="reason" required maxLength={500} className="rounded border p-1" /></label>
      <button type="submit" disabled={busy} className="rounded border px-3 py-1">Stop attempt and release issue</button>
      {error && <p role="alert">{error}</p>}
    </form>
  </details>;
}
