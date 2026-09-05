"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import {
  Sparkles,
  Trash2,
  ClipboardCheck,
  ShieldCheck,
  ChevronRight,
} from "lucide-react";
import { GrammarPointPicker } from "@/components/content/grammar-point-picker";
import { Badge } from "@/components/ui/badge";
import { Button, buttonVariants } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Skeleton } from "@/components/ui/skeleton";
import { Textarea } from "@/components/ui/textarea";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { contentApi } from "@/lib/content/client";
import { dialogueApi, type DialogueScenario } from "@/lib/dialogue/client";
import { enrichDialogueHighlights } from "@/lib/dialogue/enrich-dialogue-highlights";
import { scrollToId } from "@/lib/scroll-to-id";
import { cn } from "@/lib/utils";
import { LineEditor } from "@/components/dialogue/line-editor";
import { GenerateLinesPanel } from "@/components/dialogue/generate-lines-panel";
import { HighlightsEditor } from "@/components/dialogue/highlights-editor";
import { QuizEditor } from "@/components/dialogue/quiz-editor";
import { ScenarioAudioPanel } from "@/components/dialogue/scenario-audio-panel";
import { ScenarioAuditPanel } from "@/components/dialogue/scenario-audit-panel";
import { ScenarioMinimap } from "@/components/dialogue/scenario-minimap";
import {
  hasSpokenJapanese,
  type AuditScenarioResult,
  type DialogueHighlights,
  type DialogueLine,
} from "@/lib/dialogue/types";

// Sections within the "editor" view; "raw" is a separate top-level view, not
// a scrollable section, since editing raw JSON alongside the rest doesn't
// make sense.
const SECTIONS = [
  { id: "overview", label: "Overview" },
  { id: "lines", label: "Lines" },
  { id: "audio", label: "Audio" },
  { id: "highlights", label: "Highlights" },
  { id: "quiz", label: "Quiz" },
];
const SECTION_IDS = SECTIONS.map((section) => section.id);

// Which sections the user has folded away. Remembered across scenarios so
// e.g. "Lines collapsed, Audio open" survives moving to the next scene.
const COLLAPSED_SECTIONS_KEY = "studio:scenario-editor:collapsed-sections";

function readCollapsedSections(): Set<string> {
  if (typeof window === "undefined") return new Set();
  try {
    const raw = window.localStorage.getItem(COLLAPSED_SECTIONS_KEY);
    const parsed: unknown = raw ? JSON.parse(raw) : [];
    if (!Array.isArray(parsed)) return new Set();
    return new Set(
      parsed.filter(
        (id): id is string => typeof id === "string" && SECTION_IDS.includes(id),
      ),
    );
  } catch {
    return new Set();
  }
}

function writeCollapsedSections(collapsed: Set<string>) {
  try {
    window.localStorage.setItem(
      COLLAPSED_SECTIONS_KEY,
      JSON.stringify([...collapsed]),
    );
  } catch {
    // localStorage unavailable (private mode, etc.) — keep the in-memory state.
  }
}

export function ScenarioEditor({
  collectionId,
  scenarioSlug,
}: {
  collectionId: string;
  scenarioSlug: string;
}) {
  const router = useRouter();
  const searchParams = useSearchParams();
  const queryClient = useQueryClient();

  const { data, isLoading } = useQuery({
    queryKey: ["dialogue-scenario", collectionId, scenarioSlug],
    queryFn: () => dialogueApi.getScenario(collectionId, scenarioSlug),
  });

  // Only needed to preview the inherited lesson thumbnail; the scenario
  // itself is loaded above.
  const { data: collectionData } = useQuery({
    queryKey: ["dialogue-collection", collectionId],
    queryFn: () => dialogueApi.getCollection(collectionId),
  });
  const collectionThumbnailUrl =
    collectionData?.collection.thumbnailUrl ?? null;

  const [draft, setDraft] = useState<DialogueScenario | null>(null);
  const [rawText, setRawText] = useState("");
  const [rawError, setRawError] = useState<string | null>(null);
  const [view, setView] = useState("editor");
  const [generateNonce, setGenerateNonce] = useState(0);
  const [auditResult, setAuditResult] = useState<AuditScenarioResult | null>(
    null,
  );
  const [isAuditing, setIsAuditing] = useState(false);
  const [isSanitizing, setIsSanitizing] = useState(false);
  const [isEnrichingHighlights, setIsEnrichingHighlights] = useState(false);
  const [collapsedSections, setCollapsedSections] = useState<Set<string>>(
    readCollapsedSections,
  );

  function setSectionsCollapsed(ids: string[], collapsed: boolean) {
    const next = new Set(collapsedSections);
    for (const id of ids) {
      if (collapsed) next.add(id);
      else next.delete(id);
    }
    writeCollapsedSections(next);
    setCollapsedSections(next);
  }

  function toggleSection(id: string) {
    setSectionsCollapsed([id], !collapsedSections.has(id));
  }

  const { data: pointsData } = useQuery({
    queryKey: ["content-points", "all-labels"],
    queryFn: () => contentApi.listPoints(),
    staleTime: 5 * 60 * 1000,
  });

  const pointMap = useMemo(
    () =>
      new Map(
        (pointsData?.points ?? []).map((point) => [
          point.id,
          { title: point.title, pattern: point.pattern },
        ]),
      ),
    [pointsData?.points],
  );

  useEffect(() => {
    if (data?.scenario) {
      setDraft(data.scenario);
      setRawText(JSON.stringify(data.scenario, null, 2));
      setRawError(null);
    }
  }, [data?.scenario]);

  useEffect(() => {
    const tab = searchParams.get("tab");
    if (!tab) return;
    if (tab === "raw") {
      setView("raw");
      return;
    }
    if (SECTION_IDS.includes(tab)) {
      setView("editor");
      // Deep link into a folded section: unfold it so there's something to land on.
      setCollapsedSections((current) => {
        if (!current.has(tab)) return current;
        const next = new Set(current);
        next.delete(tab);
        return next;
      });
      requestAnimationFrame(() => scrollToId(tab));
    }
  }, [searchParams]);

  // Set when the scenario was created via the "write lines manually" path,
  // so a setting/grammar points filled in for context don't silently trigger
  // AI generation the first time this scenario is opened.
  const autoGenerateDisabled = searchParams.get("autogen") === "0";

  function scrollToSection(id: string) {
    setView("editor");
    if (collapsedSections.has(id)) setSectionsCollapsed([id], false);
    requestAnimationFrame(() => scrollToId(id));
  }

  const saveMutation = useMutation({
    mutationFn: () => {
      if (!draft) throw new Error("Nothing to save");
      const current = draft;
      return dialogueApi.updateScenario(collectionId, scenarioSlug, {
        menuTitle: current.menuTitle,
        menuSubtitle: current.menuSubtitle,
        japanese: current.japanese,
        romaji: current.romaji,
        english: current.english,
        targetSubstring: current.targetSubstring,
        audioKey: current.audioKey,
        grammarPointIds: current.grammarPointIds,
        setting: current.setting,
        thumbnailUrl: current.thumbnailUrl,
        lines: current.lines,
        highlights: current.highlights,
        quiz: current.quiz,
      });
    },
    onSuccess: ({ scenario }) => {
      setDraft(scenario);
      queryClient.invalidateQueries({
        queryKey: ["dialogue-scenario", collectionId, scenarioSlug],
      });
      queryClient.invalidateQueries({
        queryKey: ["dialogue-collection", collectionId],
      });
      queryClient.invalidateQueries({ queryKey: ["dialogue-collections"] });
      queryClient.invalidateQueries({
        queryKey: ["scenario-audio", `${collectionId}/${scenarioSlug}`],
      });
      toast.success("Scenario saved.");
    },
    onError: (error) => toast.error(error.message),
  });

  // Thumbnail changes hit the CDN immediately (not part of the draft), so
  // only the thumbnailUrl is copied back into the draft — other unsaved
  // edits are preserved.
  function applyThumbnailFromServer(scenario: DialogueScenario) {
    setDraft((prev) =>
      prev ? { ...prev, thumbnailUrl: scenario.thumbnailUrl } : prev,
    );
    queryClient.invalidateQueries({
      queryKey: ["dialogue-scenario", collectionId, scenarioSlug],
    });
    queryClient.invalidateQueries({
      queryKey: ["dialogue-collection", collectionId],
    });
  }

  const uploadThumbnailMutation = useMutation({
    mutationFn: (file: File) =>
      dialogueApi.uploadScenarioThumbnail(collectionId, scenarioSlug, file),
    onSuccess: ({ scenario }) => {
      applyThumbnailFromServer(scenario);
      toast.success("Scenario thumbnail uploaded to CDN.");
    },
    onError: (error) => toast.error(error.message),
  });

  const clearThumbnailMutation = useMutation({
    mutationFn: () =>
      dialogueApi.clearScenarioThumbnail(collectionId, scenarioSlug),
    onSuccess: ({ scenario }) => {
      applyThumbnailFromServer(scenario);
      toast.success("Scenario thumbnail removed — lesson thumbnail applies.");
    },
    onError: (error) => toast.error(error.message),
  });

  const deleteMutation = useMutation({
    mutationFn: () => dialogueApi.deleteScenario(collectionId, scenarioSlug),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["dialogue-collections"] });
      queryClient.invalidateQueries({
        queryKey: ["dialogue-collection", collectionId],
      });
      toast.success("Scenario deleted.");
      router.push(`/content/dialogues/${collectionId}`);
    },
    onError: (error) => toast.error(error.message),
  });

  if (isLoading || !draft) {
    return (
      <div className="flex flex-1 flex-col gap-4">
        <Skeleton className="h-8 w-64" />
        <Skeleton className="h-48 w-full" />
      </div>
    );
  }

  function update<K extends keyof DialogueScenario>(
    key: K,
    value: DialogueScenario[K],
  ) {
    setDraft((prev) => (prev ? { ...prev, [key]: value } : prev));
  }

  async function enrichHighlightsForLines(
    lines: DialogueLine[],
    grammarPointIds: string[],
    existingHighlights: DialogueHighlights | null,
    options?: { switchTab?: boolean; replaceHighlights?: boolean },
  ) {
    if (
      !draft ||
      lines.length === 0 ||
      !hasSpokenJapanese(lines) ||
      isEnrichingHighlights
    ) {
      return;
    }
    const current = draft;

    setIsEnrichingHighlights(true);
    const toastId = toast.loading("Extracting highlights…");
    try {
      const highlights = await enrichDialogueHighlights({
        lines,
        existing: options?.replaceHighlights ? null : existingHighlights,
        grammarPointIds,
        setting: current.setting ?? undefined,
        menuTitle: current.menuTitle,
        pointMap,
        mode: "refresh",
      });
      update("highlights", highlights);
      if (options?.switchTab) {
        scrollToSection("highlights");
      }
      toast.success("Highlights extracted — review and Save.", { id: toastId });
    } catch (error) {
      toast.error(
        error instanceof Error ? error.message : "Highlight extraction failed.",
        { id: toastId },
      );
    } finally {
      setIsEnrichingHighlights(false);
    }
  }

  const targetMissing =
    !!draft.targetSubstring &&
    !!draft.japanese &&
    !draft.japanese.includes(draft.targetSubstring);

  function applyRawJson() {
    try {
      const parsed = JSON.parse(rawText);
      if (typeof parsed !== "object" || parsed === null) {
        setRawError("Must be a JSON object.");
        return;
      }
      if (!Array.isArray(parsed.lines)) {
        setRawError("Missing required field: lines (array).");
        return;
      }
      setRawError(null);
      setDraft({
        ...parsed,
        id: draft!.id,
        collectionId: draft!.collectionId,
      } as DialogueScenario);
      toast.success("Redecoded into editor. Save to persist.");
    } catch (e) {
      setRawError(e instanceof Error ? e.message : "Invalid JSON.");
    }
  }

  async function runAudit() {
    if (!draft || draft.lines.length === 0) {
      toast.error("Add dialogue lines before auditing.");
      return;
    }
    const current = draft;
    setIsAuditing(true);
    setAuditResult(null);
    try {
      const { result } = await dialogueApi.auditScenario({
        lines: current.lines,
        highlights: current.highlights,
        grammarPointIds: current.grammarPointIds,
        setting: current.setting ?? undefined,
        menuTitle: current.menuTitle,
      });
      setAuditResult(result);
      const fixable =
        result.proposed.lines !== undefined ||
        result.proposed.highlights !== undefined;
      if (result.issues.length === 0) {
        toast.success("Audit complete — no issues found.");
      } else if (fixable) {
        toast.message(
          `Audit found ${result.issues.length} issue(s). Review and apply fixes.`,
        );
      } else {
        toast.message(
          `Audit found ${result.issues.length} issue(s) with no auto-fix.`,
        );
      }
    } catch (error) {
      toast.error(error instanceof Error ? error.message : "Audit failed.");
    } finally {
      setIsAuditing(false);
    }
  }

  function applyAuditFixes() {
    if (!auditResult) return;
    const { proposed } = auditResult;
    setDraft((prev) => {
      if (!prev) return prev;
      return {
        ...prev,
        ...(proposed.lines ? { lines: proposed.lines } : {}),
        ...(proposed.highlights !== undefined
          ? { highlights: proposed.highlights ?? null }
          : {}),
        ...(proposed.grammarPointIds
          ? { grammarPointIds: proposed.grammarPointIds }
          : {}),
      };
    });
    setAuditResult(null);
    toast.success("Proposed fixes applied to draft. Save to persist.");
  }

  async function sanitizeGrammarTags() {
    if (!draft || draft.lines.length === 0) {
      toast.error("Add dialogue lines before sanitizing.");
      return;
    }
    const current = draft;

    setIsSanitizing(true);
    try {
      const { result } = await dialogueApi.sanitizeGrammarTags({
        lines: current.lines,
        highlights: current.highlights,
        grammarPointIds: current.grammarPointIds,
      });

      if (result.removedCount === 0) {
        toast.success("All grammar IDs are already in the catalog.");
        return;
      }

      setDraft((prev) => {
        if (!prev) return prev;
        return {
          ...prev,
          lines: result.lines,
          highlights: result.highlights,
          grammarPointIds: result.grammarPointIds,
        };
      });
      toast.success(
        `Removed ${result.removedCount} invalid grammar ID(s) from draft. Save to persist.`,
      );
    } catch (error) {
      toast.error(
        error instanceof Error ? error.message : "Sanitization failed.",
      );
    } finally {
      setIsSanitizing(false);
    }
  }

  return (
    <div className="flex flex-1 flex-col gap-6">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">
            {draft.menuTitle}
          </h1>
          <p className="text-sm text-muted-foreground">{draft.id}</p>
        </div>
        <div className="flex gap-2">
          <Button
            variant="outline"
            className="gap-2"
            onClick={() => void sanitizeGrammarTags()}
            disabled={isSanitizing || draft.lines.length === 0}
            title="Strip grammar IDs that are not in the grammar point catalog"
          >
            <ShieldCheck className="size-4" />
            {isSanitizing ? "Sanitizing…" : "Sanitize IDs"}
          </Button>
          <Button
            variant="outline"
            className="gap-2"
            onClick={() => void runAudit()}
            disabled={isAuditing || draft.lines.length === 0}
          >
            <ClipboardCheck className="size-4" />
            {isAuditing ? "Auditing…" : "Audit"}
          </Button>
          <Button
            variant="ghost"
            onClick={() => {
              if (window.confirm(`Delete scenario "${draft.menuTitle}"?`)) {
                deleteMutation.mutate();
              }
            }}
            disabled={deleteMutation.isPending}
            aria-label="Delete scenario"
          >
            <Trash2 className="size-4" />
          </Button>
          <Button
            variant="outline"
            onClick={() => saveMutation.mutate()}
            disabled={saveMutation.isPending}
          >
            Save
          </Button>
        </div>
      </div>

      <ScenarioAuditPanel
        result={auditResult}
        isAuditing={isAuditing}
        onApply={applyAuditFixes}
        onDismiss={() => setAuditResult(null)}
      />

      <Tabs value={view} onValueChange={(value) => value && setView(value)}>
        <div className="flex flex-wrap items-center justify-between gap-2">
          <TabsList>
            <TabsTrigger value="editor">Editor</TabsTrigger>
            <TabsTrigger value="raw">Raw JSON</TabsTrigger>
          </TabsList>
          {view === "editor" && (
            <div className="flex items-center gap-1">
              <Button
                type="button"
                variant="ghost"
                size="sm"
                className="h-7 px-2 text-xs"
                disabled={collapsedSections.size === SECTION_IDS.length}
                onClick={() => setSectionsCollapsed(SECTION_IDS, true)}
              >
                Collapse all
              </Button>
              <Button
                type="button"
                variant="ghost"
                size="sm"
                className="h-7 px-2 text-xs"
                disabled={collapsedSections.size === 0}
                onClick={() => setSectionsCollapsed(SECTION_IDS, false)}
              >
                Expand all
              </Button>
            </div>
          )}
        </div>

        <TabsContent value="editor" className="flex gap-8 pt-4">
          <div className="flex min-w-0 flex-1 flex-col gap-6">
            <CollapsibleSection
              id="overview"
              title="Overview"
              summary={draft.menuSubtitle ?? draft.setting ?? undefined}
              collapsed={collapsedSections.has("overview")}
              onToggle={() => toggleSection("overview")}
              className="max-w-2xl"
              bodyClassName="gap-4"
            >
              <div className="grid grid-cols-2 gap-4">
                <div className="flex flex-col gap-2">
                  <Label>Menu title</Label>
                  <Input
                    value={draft.menuTitle}
                    onChange={(e) => update("menuTitle", e.target.value)}
                  />
                </div>
                <div className="flex flex-col gap-2">
                  <Label>Menu subtitle</Label>
                  <Input
                    value={draft.menuSubtitle ?? ""}
                    onChange={(e) =>
                      update("menuSubtitle", e.target.value || null)
                    }
                  />
                </div>
              </div>

              <div className="flex flex-col gap-2">
                <Label>Headline — Japanese</Label>
                <Input
                  value={draft.japanese}
                  onChange={(e) => update("japanese", e.target.value)}
                />
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div className="flex flex-col gap-2">
                  <Label>Headline — Romaji</Label>
                  <Input
                    value={draft.romaji}
                    onChange={(e) => update("romaji", e.target.value)}
                  />
                </div>
                <div className="flex flex-col gap-2">
                  <Label>Headline — English</Label>
                  <Input
                    value={draft.english}
                    onChange={(e) => update("english", e.target.value)}
                  />
                </div>
              </div>

              <div className="flex flex-col gap-2">
                <Label>Target substring (highlighted in headline)</Label>
                <Input
                  value={draft.targetSubstring ?? ""}
                  onChange={(e) =>
                    update("targetSubstring", e.target.value || null)
                  }
                />
                {targetMissing && (
                  <p className="text-sm text-destructive">
                    Target substring does not appear verbatim in the Japanese
                    headline.
                  </p>
                )}
              </div>

              <div className="flex flex-col gap-2">
                <Label>Audio key</Label>
                <Input
                  value={draft.audioKey ?? ""}
                  onChange={(e) => update("audioKey", e.target.value || null)}
                  placeholder={draft.id}
                />
                <p className="text-xs text-muted-foreground">
                  Resolves to Dialogue/Audio/&lt;key&gt;.m4a in the app bundle.
                  Leave empty for on-device TTS.
                </p>
              </div>

              <GrammarPointPicker
                label="Grammar points"
                description="Points practiced in this scenario. Used when generating dialogue lines."
                value={draft.grammarPointIds}
                onChange={(grammarPointIds) =>
                  update("grammarPointIds", grammarPointIds)
                }
              />

              <div className="flex flex-col gap-2">
                <Label>Setting</Label>
                <Textarea
                  rows={2}
                  value={draft.setting ?? ""}
                  onChange={(e) => update("setting", e.target.value || null)}
                  placeholder="At the library — a student asks the librarian where to find quiet study desks."
                />
              </div>

              <div className="flex flex-col gap-3 rounded-md border p-4">
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <div>
                    <Label>Scenario thumbnail</Label>
                    <p className="text-xs text-muted-foreground">
                      Optional. Overrides the lesson thumbnail for this
                      scenario only; exported as{" "}
                      <code className="text-xs">thumbnailUrl</code> on the
                      scenario. Leave empty to inherit the lesson&apos;s.
                    </p>
                  </div>
                  <Badge variant={draft.thumbnailUrl ? "default" : "secondary"}>
                    {draft.thumbnailUrl ? "own thumbnail" : "inherits lesson"}
                  </Badge>
                </div>
                {draft.thumbnailUrl ? (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img
                    src={draft.thumbnailUrl}
                    alt={`${draft.menuTitle} thumbnail`}
                    className="h-40 w-full max-w-sm rounded-md border object-cover"
                  />
                ) : collectionThumbnailUrl ? (
                  <div className="flex max-w-sm flex-col gap-1">
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img
                      src={collectionThumbnailUrl}
                      alt="Inherited lesson thumbnail"
                      className="h-40 w-full rounded-md border object-cover opacity-70"
                    />
                    <p className="text-xs text-muted-foreground">
                      Showing the lesson thumbnail the app will use.
                    </p>
                  </div>
                ) : (
                  <div className="flex h-40 max-w-sm items-center justify-center rounded-md border border-dashed text-sm text-muted-foreground">
                    No thumbnail — the lesson has none either
                  </div>
                )}
                <div className="flex flex-wrap items-center gap-2">
                  <label
                    className={buttonVariants({
                      variant: "outline",
                      className: "cursor-pointer",
                    })}
                  >
                    {uploadThumbnailMutation.isPending
                      ? "Uploading…"
                      : draft.thumbnailUrl
                        ? "Replace image"
                        : "Upload image"}
                    <input
                      type="file"
                      accept="image/jpeg,image/png,image/webp,image/gif"
                      className="hidden"
                      disabled={uploadThumbnailMutation.isPending}
                      onChange={(event) => {
                        const file = event.target.files?.[0];
                        event.target.value = "";
                        if (file) uploadThumbnailMutation.mutate(file);
                      }}
                    />
                  </label>
                  {draft.thumbnailUrl && (
                    <>
                      <a
                        href={draft.thumbnailUrl}
                        target="_blank"
                        rel="noreferrer"
                        className={buttonVariants({ variant: "ghost" })}
                      >
                        Open CDN URL
                      </a>
                      <Button
                        variant="outline"
                        onClick={() => clearThumbnailMutation.mutate()}
                        disabled={clearThumbnailMutation.isPending}
                      >
                        {clearThumbnailMutation.isPending
                          ? "Removing…"
                          : "Remove (use lesson thumbnail)"}
                      </Button>
                    </>
                  )}
                </div>
              </div>

              <Button
                className="w-fit gap-2"
                onClick={() => {
                  if (!draft.setting?.trim()) {
                    toast.error("Add a setting first.");
                    return;
                  }
                  setGenerateNonce((count) => count + 1);
                  requestAnimationFrame(() =>
                    scrollToId("generate-dialogue-panel"),
                  );
                }}
              >
                <Sparkles className="size-4" />
                {draft.lines.length > 0
                  ? "Regenerate dialogue"
                  : "Generate dialogue from setting"}
              </Button>
            </CollapsibleSection>

            <CollapsibleSection
              id="lines"
              title="Lines"
              summary={`${draft.lines.length} line${draft.lines.length === 1 ? "" : "s"}`}
              collapsed={collapsedSections.has("lines")}
              onToggle={() => toggleSection("lines")}
              className="max-w-5xl"
              bodyClassName="gap-6"
            >
              <LineEditor
                lines={draft.lines}
                onChange={(lines) => update("lines", lines)}
                reviseContext={{
                  setting: draft.setting ?? undefined,
                  menuTitle: draft.menuTitle,
                  grammarPointIds: draft.grammarPointIds,
                }}
                onLinesCommitted={(lines) => {
                  void enrichHighlightsForLines(
                    lines,
                    draft.grammarPointIds,
                    draft.highlights,
                    { switchTab: true },
                  );
                }}
              />
              <GenerateLinesPanel
                existingLines={draft.lines}
                collectionId={collectionId}
                setting={draft.setting ?? ""}
                menuTitle={draft.menuTitle}
                grammarPointIds={draft.grammarPointIds}
                autoGenerateOnMount={
                  !autoGenerateDisabled &&
                  draft.lines.length === 0 &&
                  !!draft.setting?.trim()
                }
                triggerGenerateCount={generateNonce}
                onInsert={(lines, mode, options) => {
                  const nextLines =
                    mode === "replace" ? lines : [...draft.lines, ...lines];
                  const nextGrammarPointIds =
                    options?.grammarPointIds ?? draft.grammarPointIds;

                  setDraft((prev) => {
                    if (!prev) return prev;
                    return {
                      ...prev,
                      lines: nextLines,
                      setting: prev.setting ?? options?.setting ?? null,
                      grammarPointIds: nextGrammarPointIds,
                    };
                  });

                  void enrichHighlightsForLines(
                    nextLines,
                    nextGrammarPointIds,
                    mode === "replace" ? null : draft.highlights,
                    { switchTab: true, replaceHighlights: mode === "replace" },
                  );
                }}
              />
            </CollapsibleSection>

            <CollapsibleSection
              id="audio"
              title="Audio"
              collapsed={collapsedSections.has("audio")}
              onToggle={() => toggleSection("audio")}
            >
              <ScenarioAudioPanel
                collectionId={collectionId}
                scenarioSlug={scenarioSlug}
                lines={draft.lines}
                hasUnsavedChanges={
                  JSON.stringify(draft.lines) !==
                  JSON.stringify(data?.scenario.lines ?? [])
                }
                onSaveScenario={() => saveMutation.mutateAsync()}
              />
            </CollapsibleSection>

            <CollapsibleSection
              id="highlights"
              title={`Highlights${isEnrichingHighlights ? "…" : ""}`}
              collapsed={collapsedSections.has("highlights")}
              onToggle={() => toggleSection("highlights")}
            >
              <HighlightsEditor
                key={draft.id}
                highlights={draft.highlights}
                onChange={(highlights) => update("highlights", highlights)}
                lines={draft.lines}
                grammarPointIds={draft.grammarPointIds}
                setting={draft.setting}
                menuTitle={draft.menuTitle}
              />
            </CollapsibleSection>

            <CollapsibleSection
              id="quiz"
              title="Quiz"
              collapsed={collapsedSections.has("quiz")}
              onToggle={() => toggleSection("quiz")}
            >
              <QuizEditor
                quiz={draft.quiz}
                onChange={(quiz) => update("quiz", quiz)}
                lines={draft.lines}
                setting={draft.setting}
                menuTitle={draft.menuTitle}
              />
            </CollapsibleSection>
          </div>

          <ScenarioMinimap sections={SECTIONS} onSelect={scrollToSection} />
        </TabsContent>

        <TabsContent value="raw" className="flex flex-col gap-3 pt-4">
          <Textarea
            rows={24}
            value={rawText}
            onChange={(e) => setRawText(e.target.value)}
            className="font-mono text-xs"
            spellCheck={false}
          />
          {rawError && <p className="text-sm text-destructive">{rawError}</p>}
          <div className="flex gap-2">
            <Button
              variant="outline"
              size="sm"
              onClick={() => setRawText(JSON.stringify(draft, null, 2))}
            >
              Load current draft
            </Button>
            <Button size="sm" onClick={applyRawJson}>
              Redecode into editor
            </Button>
          </div>
        </TabsContent>
      </Tabs>
    </div>
  );
}

/**
 * One editor section with a fold-away body. The body stays mounted (just
 * hidden) so panels keep their in-progress state — e.g. GenerateLinesPanel's
 * auto-generate-on-mount guard and the audio waveform instance survive a
 * collapse/expand round trip.
 */
function CollapsibleSection({
  id,
  title,
  summary,
  collapsed,
  onToggle,
  className,
  bodyClassName,
  children,
}: {
  id: string;
  title: string;
  summary?: string;
  collapsed: boolean;
  onToggle: () => void;
  className?: string;
  bodyClassName?: string;
  children: React.ReactNode;
}) {
  const bodyId = `${id}-body`;
  return (
    <section id={id} className={cn("flex scroll-mt-20 flex-col gap-4", className)}>
      <button
        type="button"
        aria-expanded={!collapsed}
        aria-controls={bodyId}
        onClick={onToggle}
        className="group flex min-h-10 w-full items-center gap-2 rounded-md text-left touch-manipulation"
      >
        <ChevronRight
          className={cn(
            "size-4 shrink-0 text-muted-foreground transition-transform group-hover:text-foreground",
            !collapsed && "rotate-90",
          )}
        />
        <h2 className="text-lg font-semibold tracking-tight">{title}</h2>
        {collapsed && summary ? (
          <span className="min-w-0 truncate text-sm text-muted-foreground">
            {summary}
          </span>
        ) : null}
      </button>
      <div
        id={bodyId}
        className={cn("flex flex-col", bodyClassName, collapsed && "hidden")}
      >
        {children}
      </div>
    </section>
  );
}
