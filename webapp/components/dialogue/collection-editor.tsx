"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import {
  ArrowDown,
  ArrowUp,
  Download,
  Plus,
  Sparkles,
  Trash2,
  Upload,
} from "lucide-react";
import { GrammarPointPicker } from "@/components/content/grammar-point-picker";
import { DifficultyLevelPicker } from "@/components/dialogue/difficulty-level-picker";
import { FormalityLevelPicker } from "@/components/dialogue/formality-level-picker";
import { Button, buttonVariants } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Skeleton } from "@/components/ui/skeleton";
import { Textarea } from "@/components/ui/textarea";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Badge } from "@/components/ui/badge";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  dialogueApi,
  scenarioSlug,
  type DialogueCollection,
} from "@/lib/dialogue/client";
import {
  buildCollectionFile,
  serializeCollectionFile,
} from "@/lib/dialogue/export";
import { collectionFileSchema, type CollectionFile } from "@/lib/dialogue/types";
import { flushPendingTokenSync } from "@/lib/dialogue/token-sync-persist";
import { ScenarioTemplatePicker } from "@/components/dialogue/scenario-template-picker";
import { scenarioTemplates } from "@/lib/dialogue/scenario-templates";
import {
  dialogueLinesFromGenerated,
  generationBriefFromSetting,
} from "@/lib/dialogue/generated-lines";
import type { DialogueDifficulty } from "@/lib/dialogue/difficulty";
import type { DialogueFormality } from "@/lib/dialogue/formality";

function collectionToRawJson(collection: DialogueCollection): string {
  return serializeCollectionFile(
    buildCollectionFile(collection, collection.scenarios)
  );
}

function slugify(input: string): string {
  return input
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

export function CollectionEditor({ collectionId }: { collectionId: string }) {
  const router = useRouter();
  const queryClient = useQueryClient();

  const { data, isLoading } = useQuery({
    queryKey: ["dialogue-collection", collectionId],
    queryFn: () => dialogueApi.getCollection(collectionId),
  });

  const audioStatusQuery = useQuery({
    queryKey: ["dialogue-collection-audio-status", collectionId],
    queryFn: () => dialogueApi.audioStatus(collectionId),
  });
  const audioStatusById = new Map(
    (audioStatusQuery.data?.scenarios ?? []).map((s) => [s.id, s])
  );

  const [title, setTitle] = useState("");
  const [subtitle, setSubtitle] = useState("");
  const [premise, setPremise] = useState("");
  const [sceneImage, setSceneImage] = useState("");
  const [unitId, setUnitId] = useState("");
  const [addOpen, setAddOpen] = useState(false);
  const [newSlug, setNewSlug] = useState("");
  const [newMenuTitle, setNewMenuTitle] = useState("");
  const [newSetting, setNewSetting] = useState("");
  const [newGrammarPointIds, setNewGrammarPointIds] = useState<string[]>([]);
  const [newDifficulty, setNewDifficulty] =
    useState<DialogueDifficulty>("beginner");
  const [newFormality, setNewFormality] =
    useState<DialogueFormality>("polite");
  const [aiPrompt, setAiPrompt] = useState("");
  const [rawText, setRawText] = useState("");
  const [rawError, setRawError] = useState<string | null>(null);

  const collection = data?.collection;

  const defaultGrammarPointIds = useMemo(() => {
    if (!collection) return [];
    const counts = new Map<string, number>();
    for (const scenario of collection.scenarios) {
      for (const id of scenario.grammarPointIds) {
        counts.set(id, (counts.get(id) ?? 0) + 1);
      }
    }
    return [...counts.entries()]
      .sort((a, b) => b[1] - a[1])
      .slice(0, 3)
      .map(([id]) => id);
  }, [collection]);

  useEffect(() => {
    if (collection) {
      setTitle(collection.title);
      setSubtitle(collection.subtitle ?? "");
      setPremise(collection.premise ?? "");
      setSceneImage(collection.sceneImage ?? "");
      setUnitId(collection.unitId ?? "");
      setRawText(collectionToRawJson(collection));
      setRawError(null);
    }
  }, [collection]);

  const { data: unitsData } = useQuery({
    queryKey: ["curriculum-units"],
    queryFn: dialogueApi.listUnits,
  });
  const units = unitsData?.units ?? [];

  function invalidate() {
    queryClient.invalidateQueries({
      queryKey: ["dialogue-collection", collectionId],
    });
    queryClient.invalidateQueries({
      queryKey: ["dialogue-collection-audio-status", collectionId],
    });
    queryClient.invalidateQueries({ queryKey: ["dialogue-collections"] });
  }

  const saveMutation = useMutation({
    mutationFn: () =>
      dialogueApi.updateCollection(collectionId, {
        title: title.trim(),
        subtitle: subtitle.trim() || null,
        premise: premise.trim() || null,
        sceneImage: sceneImage.trim() || null,
        unitId: unitId || null,
      }),
    onSuccess: () => {
      invalidate();
      queryClient.invalidateQueries({ queryKey: ["curriculum-units"] });
      toast.success("Collection saved.");
    },
    onError: (error) => toast.error(error.message),
  });

  const reorderMutation = useMutation({
    mutationFn: (scenarioOrder: string[]) =>
      dialogueApi.updateCollection(collectionId, { scenarioOrder }),
    onSuccess: invalidate,
    onError: (error) => toast.error(error.message),
  });

  const addScenarioMutation = useMutation({
    mutationFn: async (withAi: boolean) => {
      const slug = newSlug.trim();
      const menuTitle = newMenuTitle.trim();
      const setting = newSetting.trim();
      const grammarPointIds = newGrammarPointIds;

      const { scenario } = await dialogueApi.createScenario(collectionId, {
        slug,
        menuTitle,
        setting: setting || undefined,
      });

      if (!withAi || !setting) {
        return { scenario, generated: false, withAi };
      }

      try {
        const { generated } = await dialogueApi.generateLines({
          prompt: generationBriefFromSetting(setting, menuTitle),
          collectionId,
          setting,
          grammarPointIds,
          mode: "replace",
          variantIndex: 0,
          variantCount: 3,
          difficulty: newDifficulty,
          formality: newFormality,
        });
        const lines = dialogueLinesFromGenerated(generated, grammarPointIds);
        const { scenario: updated } = await dialogueApi.updateScenario(
          collectionId,
          slug,
          {
            lines,
            grammarPointIds,
            setting,
          }
        );
        return { scenario: updated, generated: true, withAi };
      } catch (error) {
        toast.warning(
          error instanceof Error
            ? `Scenario created, but generation failed: ${error.message}`
            : "Scenario created, but line generation failed."
        );
        return { scenario, generated: false, withAi };
      }
    },
    onSuccess: ({ scenario, generated, withAi }) => {
      invalidate();
      queryClient.invalidateQueries({ queryKey: ["dialogue-scenario"] });
      setAddOpen(false);
      setNewSlug("");
      setNewMenuTitle("");
      setNewSetting("");
      setNewGrammarPointIds([]);
      setNewDifficulty("beginner");
      setNewFormality("polite");
      toast.success(
        generated
          ? "Scenario created with generated dialogue."
          : "Scenario created."
      );
      // If the user opted out of AI generation, tell the scenario editor not
      // to auto-generate dialogue just because a setting/grammar points
      // happen to be filled in.
      const query = withAi ? "?tab=lines" : "?tab=lines&autogen=0";
      router.push(
        `/content/dialogues/${collectionId}/${scenarioSlug(scenario)}${query}`
      );
    },
    onError: (error) => toast.error(error.message),
  });

  const generateScenarioIdeaMutation = useMutation({
    mutationFn: () =>
      dialogueApi.generateScenario({
        prompt: aiPrompt.trim(),
        collectionId,
        existingSlugs,
        difficulty: newDifficulty,
        formality: newFormality,
      }),
    onSuccess: ({ generated }) => {
      const slug = slugify(generated.slug);
      setNewSlug(
        existingSlugs.includes(slug) ? `${slug}-${Date.now()}` : slug
      );
      setNewMenuTitle(generated.menuTitle);
      setNewSetting(generated.setting);
      if (generated.grammarPointIds.length > 0) {
        setNewGrammarPointIds(generated.grammarPointIds);
      }
      toast.success("Scenario idea generated. Review and add below.");
    },
    onError: (error) => toast.error(error.message),
  });

  const replaceMutation = useMutation({
    mutationFn: (file: CollectionFile) =>
      dialogueApi.replaceCollection(collectionId, file),
    onSuccess: () => {
      invalidate();
      queryClient.invalidateQueries({ queryKey: ["dialogue-scenario"] });
      toast.success("Collection replaced from JSON.");
    },
    onError: (error) => toast.error(error.message),
  });

  const deleteMutation = useMutation({
    mutationFn: () => dialogueApi.deleteCollection(collectionId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["dialogue-collections"] });
      toast.success("Collection deleted.");
      router.push("/content/dialogues");
    },
    onError: (error) => toast.error(error.message),
  });

  const uploadThumbnailMutation = useMutation({
    mutationFn: (file: File) => dialogueApi.uploadThumbnail(collectionId, file),
    onSuccess: () => {
      invalidate();
      toast.success("Thumbnail uploaded to CDN.");
    },
    onError: (error) => toast.error(error.message),
  });

  const clearThumbnailMutation = useMutation({
    mutationFn: () => dialogueApi.clearThumbnail(collectionId),
    onSuccess: () => {
      invalidate();
      toast.success("Thumbnail removed.");
    },
    onError: (error) => toast.error(error.message),
  });

  const publishLessonMutation = useMutation({
    mutationFn: async () => {
      await flushPendingTokenSync();
      return dialogueApi.publishLesson(collectionId);
    },
    onSuccess: (result) => {
      invalidate();
      const karaokeCount = result.results.filter((row) => row.hasTokenKaraoke)
        .length;
      const parts = [
        result.publishedCount > 0
          ? `${result.publishedCount} published`
          : null,
        result.results.filter((r) => r.status === "unchanged").length > 0
          ? `${result.results.filter((r) => r.status === "unchanged").length} already current`
          : null,
        result.skippedCount > 0
          ? `${result.skippedCount} without audio`
          : null,
        karaokeCount > 0 ? `${karaokeCount} with token karaoke` : null,
      ].filter(Boolean);
      if (result.failedCount > 0) {
        const firstError = result.results.find((r) => r.status === "failed");
        toast.error(
          `Lesson publish finished with ${result.failedCount} failure(s)` +
            (firstError?.error ? `: ${firstError.error}` : ".")
        );
      } else {
        toast.success(
          parts.length > 0
            ? `Lesson published (${parts.join(", ")}).`
            : "Lesson published."
        );
      }
    },
    onError: (error) => toast.error(error.message),
  });

  if (isLoading || !collection) {
    return (
      <div className="flex flex-1 flex-col gap-4">
        <Skeleton className="h-8 w-64" />
        <Skeleton className="h-48 w-full" />
      </div>
    );
  }

  const scenarios = collection.scenarios;
  const existingSlugs = scenarios.map((scenario) =>
    scenarioSlug(scenario)
  );

  function move(index: number, delta: number) {
    const target = index + delta;
    if (target < 0 || target >= scenarios.length) return;
    const order = scenarios.map((s) => s.id);
    [order[index], order[target]] = [order[target], order[index]];
    reorderMutation.mutate(order);
  }

  function validateRaw(): CollectionFile | null {
    try {
      const parsed = collectionFileSchema.safeParse(JSON.parse(rawText));
      if (!parsed.success) {
        setRawError(
          parsed.error.issues
            .slice(0, 5)
            .map((issue) => `${issue.path.join(".")}: ${issue.message}`)
            .join("; ")
        );
        return null;
      }
      if (parsed.data.id !== collectionId) {
        setRawError(`Collection id must remain "${collectionId}".`);
        return null;
      }
      setRawError(null);
      return parsed.data;
    } catch (e) {
      setRawError(e instanceof Error ? e.message : "Invalid JSON.");
      return null;
    }
  }

  return (
    <div className="flex flex-1 flex-col gap-6">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">
            {collection.title}
          </h1>
          <p className="text-sm text-muted-foreground">{collection.id}</p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Button
            onClick={() => publishLessonMutation.mutate()}
            disabled={publishLessonMutation.isPending || scenarios.length === 0}
          >
            <Upload className="size-4" />
            {publishLessonMutation.isPending
              ? "Publishing lesson…"
              : "Publish lesson"}
          </Button>
          <a
            href={dialogueApi.exportUrl(collectionId)}
            download
            className={buttonVariants({ variant: "outline" })}
          >
            <Download className="size-4" />
            Export JSON
          </a>
          <a
            href={dialogueApi.exportZipUrl(collectionId)}
            className={buttonVariants({ variant: "outline" })}
          >
            <Download className="size-4" />
            Export zip (JSON + audio)
          </a>
          <Button
            variant="outline"
            onClick={() => saveMutation.mutate()}
            disabled={saveMutation.isPending}
          >
            Save
          </Button>
        </div>
      </div>

      <Tabs defaultValue="overview">
        <TabsList>
          <TabsTrigger value="overview">Overview</TabsTrigger>
          <TabsTrigger value="raw">Raw JSON</TabsTrigger>
        </TabsList>

        <TabsContent value="overview" className="flex flex-col gap-6 pt-4">
      <div className="grid max-w-2xl grid-cols-2 gap-4">
        <div className="flex flex-col gap-2">
          <Label>Title</Label>
          <Input value={title} onChange={(e) => setTitle(e.target.value)} />
        </div>
        <div className="flex flex-col gap-2">
          <Label>Scene image (bundled asset name)</Label>
          <Input
            value={sceneImage}
            onChange={(e) => setSceneImage(e.target.value)}
            placeholder="train-station"
          />
          <p className="text-xs text-muted-foreground">
            Optional fallback for the iOS asset catalog. Prefer uploading a CDN
            thumbnail below for Shizen.
          </p>
        </div>
        <div className="col-span-2 flex flex-col gap-2">
          <Label>Subtitle</Label>
          <Textarea
            rows={2}
            value={subtitle}
            onChange={(e) => setSubtitle(e.target.value)}
          />
        </div>
        <div className="col-span-2 flex flex-col gap-2">
          <Label>Premise</Label>
          <Textarea
            rows={4}
            value={premise}
            onChange={(e) => setPremise(e.target.value)}
            placeholder="e.g. Aiko and Ren are next-door neighbors in a Tokyo apartment building who keep running into each other. Aiko: curious, upbeat. Ren: reserved, polite."
          />
          <p className="text-xs text-muted-foreground">
            Admin-only. Describe the recurring setting and cast for this
            collection&apos;s scenarios — it&apos;s passed to dialogue and
            scenario generation to keep characters and tone consistent across
            conversations, but it never ships in exported collection files or
            the app.
          </p>
        </div>
        <div className="col-span-2 flex flex-col gap-2">
          <Label>Curriculum unit</Label>
          <Select
            value={unitId || "__unfiled__"}
            onValueChange={(value) =>
              setUnitId(!value || value === "__unfiled__" ? "" : value)
            }
          >
            <SelectTrigger className="max-w-sm">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="__unfiled__">Unfiled</SelectItem>
              {units.map((unit) => (
                <SelectItem key={unit.id} value={unit.id}>
                  {unit.title} (N{unit.jlptLevel})
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
          <p className="text-xs text-muted-foreground">
            Groups this collection under a grammar band in the lesson list and
            the Shizen app. Saved with the collection.
          </p>
        </div>
        <div className="col-span-2 flex flex-col gap-3 rounded-md border p-4">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <div>
              <Label>Lesson thumbnail</Label>
              <p className="text-xs text-muted-foreground">
                Uploaded to the public CDN and included as{" "}
                <code className="text-xs">thumbnailUrl</code> in the lesson JSON.
              </p>
            </div>
            {collection.thumbnailUrl && (
              <Badge variant="secondary">uploaded</Badge>
            )}
          </div>
          {collection.thumbnailUrl ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={collection.thumbnailUrl}
              alt={`${collection.title} thumbnail`}
              className="h-40 w-full max-w-sm rounded-md border object-cover"
            />
          ) : (
            <div className="flex h-40 max-w-sm items-center justify-center rounded-md border border-dashed text-sm text-muted-foreground">
              No thumbnail yet
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
                : collection.thumbnailUrl
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
            {collection.thumbnailUrl && (
              <>
                <a
                  href={collection.thumbnailUrl}
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
                  {clearThumbnailMutation.isPending ? "Removing…" : "Remove"}
                </Button>
              </>
            )}
          </div>
        </div>
      </div>

      <div className="flex max-w-2xl flex-col gap-3">
        <div className="flex items-center justify-between gap-4">
          <div className="flex min-w-0 flex-col gap-1">
            <Label>Scenarios</Label>
            <p className="text-xs text-muted-foreground">
              Publish lesson uploads CDN audio for every scenario with a selected
              take, then serves the full lesson JSON (all scenarios + accurate
              audio URLs) to Shizen.
            </p>
          </div>
          <Button
            variant="outline"
            size="sm"
            className="gap-2 shrink-0"
            onClick={() => setAddOpen(true)}
          >
            <Plus className="size-4" />
            Add scenario
          </Button>
        </div>

        {scenarios.length === 0 && (
          <p className="text-sm text-muted-foreground">No scenarios yet.</p>
        )}

        {scenarios.map((scenario, index) => (
          <div
            key={scenario.id}
            className="flex items-center gap-2 rounded-md border border-border/60 p-3"
          >
            <div className="flex min-w-0 flex-1 flex-col">
              <Link
                href={`/content/dialogues/${collectionId}/${scenarioSlug(scenario)}`}
                className="truncate text-sm font-medium hover:underline"
              >
                {scenario.menuTitle}
              </Link>
              <span className="truncate text-xs text-muted-foreground">
                {scenario.id}
              </span>
            </div>
            {(() => {
              const status = audioStatusById.get(scenario.id);
              if (status?.published) {
                return status.publishStale ? (
                  <Badge
                    variant="outline"
                    className="border-amber-500/50 text-amber-600 dark:text-amber-400"
                  >
                    published · stale
                  </Badge>
                ) : (
                  <Badge variant="default">published</Badge>
                );
              }
              if (!status?.hasSelectedTake) {
                return (
                  <span className="text-xs text-muted-foreground">
                    no audio
                  </span>
                );
              }
              return status.stale ? (
                <Badge
                  variant="outline"
                  className="border-amber-500/50 text-amber-600 dark:text-amber-400"
                >
                  audio stale
                </Badge>
              ) : (
                <Badge variant="secondary">audio ready</Badge>
              );
            })()}
            <Button
              variant="ghost"
              size="icon-sm"
              onClick={() => move(index, -1)}
              disabled={index === 0 || reorderMutation.isPending}
              aria-label="Move up"
            >
              <ArrowUp className="size-3.5" />
            </Button>
            <Button
              variant="ghost"
              size="icon-sm"
              onClick={() => move(index, 1)}
              disabled={
                index === scenarios.length - 1 || reorderMutation.isPending
              }
              aria-label="Move down"
            >
              <ArrowDown className="size-3.5" />
            </Button>
          </div>
        ))}
      </div>

      <div className="max-w-2xl border-t border-border/60 pt-4">
        <Button
          variant="destructive"
          size="sm"
          className="gap-2"
          onClick={() => {
            if (
              window.confirm(
                `Delete collection "${collection.title}" and all its scenarios?`
              )
            ) {
              deleteMutation.mutate();
            }
          }}
          disabled={deleteMutation.isPending}
        >
          <Trash2 className="size-4" />
          Delete collection
        </Button>
      </div>
        </TabsContent>

        <TabsContent value="raw" className="flex flex-col gap-3 pt-4">
          <p className="text-sm text-muted-foreground">
            The whole collection in the shizen export format — every scenario
            in one JSON. Applying replaces all scenarios with the file
            contents.
          </p>
          <Textarea
            rows={28}
            value={rawText}
            onChange={(e) => setRawText(e.target.value)}
            className="font-mono text-xs"
            spellCheck={false}
          />
          {rawError && <p className="text-sm text-destructive">{rawError}</p>}
          <div className="flex gap-2">
            <Button variant="outline" size="sm" onClick={validateRaw}>
              Validate
            </Button>
            <Button
              variant="outline"
              size="sm"
              onClick={() => {
                setRawText(collectionToRawJson(collection));
                setRawError(null);
              }}
            >
              Reset to saved
            </Button>
            <Button
              size="sm"
              onClick={() => {
                const file = validateRaw();
                if (file) replaceMutation.mutate(file);
              }}
              disabled={replaceMutation.isPending}
            >
              {replaceMutation.isPending ? "Applying…" : "Apply & save"}
            </Button>
          </div>
        </TabsContent>
      </Tabs>

      <Dialog
        open={addOpen}
        onOpenChange={(open) => {
          setAddOpen(open);
          if (open) {
            setNewGrammarPointIds(defaultGrammarPointIds);
          } else {
            setNewSlug("");
            setNewMenuTitle("");
            setNewSetting("");
            setNewGrammarPointIds([]);
            setNewDifficulty("beginner");
            setAiPrompt("");
          }
        }}
      >
        <DialogContent className="flex h-[90vh] w-[95vw] max-w-[1600px] flex-col sm:max-w-[1600px]">
          <DialogHeader>
            <DialogTitle>Add scenario</DialogTitle>
          </DialogHeader>
          <div className="grid flex-1 grid-cols-[380px_1fr] gap-8 overflow-y-auto pr-1">
            <div className="flex flex-col gap-5">
              <div className="flex flex-col gap-2 rounded-lg border border-border/60 p-4">
                <Label className="flex items-center gap-1.5 text-xs text-muted-foreground">
                  <Sparkles className="size-3.5" />
                  Generate with AI
                </Label>
                <Textarea
                  rows={3}
                  value={aiPrompt}
                  onChange={(e) => setAiPrompt(e.target.value)}
                  placeholder="A tourist asks a station attendant for directions to the shinkansen platform."
                />
                <Button
                  variant="outline"
                  size="sm"
                  className="w-fit gap-2"
                  onClick={() => generateScenarioIdeaMutation.mutate()}
                  disabled={
                    generateScenarioIdeaMutation.isPending || !aiPrompt.trim()
                  }
                >
                  <Sparkles className="size-3.5" />
                  {generateScenarioIdeaMutation.isPending
                    ? "Generating…"
                    : "Generate scenario"}
                </Button>
                <p className="text-xs text-muted-foreground">
                  Describe an idea and AI fills in the slug, title, setting,
                  and grammar points below — review before adding.
                </p>
              </div>

              <div className="flex flex-1 flex-col gap-2">
                <Label className="text-xs text-muted-foreground">
                  Quick start
                </Label>
                <ScenarioTemplatePicker
                  templates={scenarioTemplates}
                  prioritizeCollectionId={collectionId}
                  existingSlugs={existingSlugs}
                  onSelect={(template) => {
                    setNewSlug(template.slug);
                    setNewMenuTitle(template.menuTitle);
                    setNewSetting(template.setting);
                  }}
                  className="flex-1"
                />
              </div>
            </div>

            <div className="flex flex-col gap-4">
              <div className="grid grid-cols-2 gap-4">
                <div className="flex flex-col gap-2">
                  <Label>Slug</Label>
                  <Input
                    value={newSlug}
                    onChange={(e) => setNewSlug(e.target.value)}
                    placeholder="buying-a-ticket"
                  />
                  <p className="text-xs text-muted-foreground">
                    Scenario ID will be {collectionId}/{newSlug || "…"}
                  </p>
                </div>
                <div className="flex flex-col gap-2">
                  <Label>Menu title</Label>
                  <Input
                    value={newMenuTitle}
                    onChange={(e) => setNewMenuTitle(e.target.value)}
                    placeholder="Buying a ticket"
                  />
                </div>
              </div>
              <div className="flex flex-col gap-2">
                <Label>Setting</Label>
                <Textarea
                  rows={3}
                  value={newSetting}
                  onChange={(e) => setNewSetting(e.target.value)}
                  placeholder="At the ticket counter — a tourist asks which ticket to buy for a day trip."
                />
              </div>

              <GrammarPointPicker
                label="Grammar points"
                description="Optional. Practiced points to weave into the generated dialogue."
                value={newGrammarPointIds}
                onChange={setNewGrammarPointIds}
              />

              <DifficultyLevelPicker
                value={newDifficulty}
                onChange={setNewDifficulty}
              />

              <FormalityLevelPicker
                value={newFormality}
                onChange={setNewFormality}
              />
            </div>
          </div>

          <div className="flex flex-col gap-2 border-t border-border/60 pt-4">
            <div className="flex flex-wrap gap-2">
              <Button
                onClick={() => addScenarioMutation.mutate(true)}
                disabled={
                  addScenarioMutation.isPending ||
                  !newSlug.trim() ||
                  !newMenuTitle.trim() ||
                  !newSetting.trim()
                }
              >
                <Sparkles className="size-4" />
                {addScenarioMutation.isPending
                  ? "Adding & generating…"
                  : "Add & generate dialogue"}
              </Button>
              <Button
                variant="outline"
                onClick={() => addScenarioMutation.mutate(false)}
                disabled={
                  addScenarioMutation.isPending ||
                  !newSlug.trim() ||
                  !newMenuTitle.trim()
                }
              >
                {addScenarioMutation.isPending
                  ? "Adding…"
                  : "Add scenario, write lines manually"}
              </Button>
            </div>
            <p className="text-xs text-muted-foreground">
              A setting is required to generate dialogue automatically;
              grammar points are optional. Skip the setting and use
              &quot;write lines manually&quot; to add lines yourself after
              creating the scenario.
            </p>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
}
