"use client";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";
import type { sceneDetail } from "@/lib/content-issues/scenes";

export function SceneIssue({report,configured}:{report:Awaited<ReturnType<typeof sceneDetail>>,configured:boolean}) {
  const router = useRouter();
  const [busy,setBusy] = useState(false);
  const [error,setError] = useState("");
  async function dispatch() {
    setBusy(true);
    try {
      const response = await fetch("/api/content/issues/scene-"+report.id,{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({action:"dispatch",agent:"hana"})});
      if (!response.ok) throw new Error((await response.json()).error);
      setError("");
    } catch(e) { setError(e instanceof Error ? e.message : "Dispatch failed"); }
    finally {setBusy(false);router.refresh();}
  }
  const history = report.attempts;
  return <section className="space-y-4">
    <h2 className="font-semibold">{report.collectionId} / {report.scenarioId}</h2>
    <p>{report.status} · {report.categories.join(", ")} · {report.createdAt}</p>
    {report.note && <blockquote className="whitespace-pre-wrap border-l-2 pl-3">{report.note}</blockquote>}
    <p>{[report.page, report.quizQuestionNumber != null && "Question "+report.quizQuestionNumber,report.focusTitle,report.sessionMode].filter(Boolean).join(" · ")}</p>
    {report.focusDetails.map((text,i)=><p key={i}>{text}</p>)}
    {report.pickedWord && <p>Picked word · <span lang="ja">{report.pickedWord}</span></p>}
    {report.playbackSeconds != null && <p>Playback position · {report.playbackSeconds.toFixed(2)} s</p>}
    {report.publishedVariantId && <p>Reported take · {report.publishedVariantId}</p>}
    {report.reportedContentHash && <p className="break-all">Reported revision · {report.reportedContentHash}</p>}
    <p><Link className="underline" href={`/content/dialogues/${encodeURIComponent(report.collectionId)}/${encodeURIComponent(report.scenarioId)}`}>Open scene editor</Link></p>
    <Link className="underline" href={"/api/content/issues/scene-"+report.id+"?published=1"}>Inspect learner-visible scene and revision</Link>
    {report.status === "open" && <div>{configured ? <button className="rounded border px-3 py-2" disabled={busy || history.some(a=>["dispatched","working"].includes(a.status))} onClick={dispatch}>Send to Hana</button> : <Link className="underline" href="/settings/agents">Configure Hana</Link>}</div>}
    {error && <p role="alert">{error}</p>}
    <h2 className="font-semibold">Attempts</h2>{history.length === 0 && <p>No attempts yet.</p>}
    {history.map(a=><article className="rounded border p-3" key={a.id}><p>{a.agent} · {a.status} · {a.createdAt}</p><strong>{a.outcome}</strong><p className="whitespace-pre-wrap">{a.summary}</p>{a.revision && <code className="break-all">{a.revision}</code>}</article>)}
  </section>;
}
