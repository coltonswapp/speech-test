"use client";

import { useEffect, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Skeleton } from "@/components/ui/skeleton";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Badge } from "@/components/ui/badge";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { contentApi, type GrammarPoint } from "@/lib/content/client";
import { TeachingBlockEditor } from "@/components/content/teaching-block-editor";
import { UsageLadderEditor } from "@/components/content/usage-ladder-editor";
import { ExampleEditor } from "@/components/content/example-editor";
import { DrillEditor } from "@/components/content/drill-editor";
import { RawJsonEditor } from "@/components/content/raw-json-editor";
import { RegenerateSectionButton } from "@/components/content/regenerate-section-button";

const statusBadgeVariant: Record<
  string,
  "default" | "secondary" | "outline" | "destructive"
> = {
  draft: "outline",
  needsRevision: "destructive",
  approved: "default",
};

export function PointEditor({ pointId }: { pointId: string }) {
  const queryClient = useQueryClient();

  const { data, isLoading } = useQuery({
    queryKey: ["content-point", pointId],
    queryFn: () => contentApi.getPoint(pointId),
  });

  const [draft, setDraft] = useState<GrammarPoint | null>(null);
  const [reviewNotes, setReviewNotes] = useState("");

  useEffect(() => {
    if (data?.point) {
      setDraft(data.point);
      setReviewNotes(data.point.reviewNotes ?? "");
    }
  }, [data?.point]);

  const saveMutation = useMutation({
    mutationFn: () => {
      if (!draft) throw new Error("Nothing to save");
      return contentApi.updatePoint(pointId, { ...draft, reviewNotes });
    },
    onSuccess: ({ point }) => {
      setDraft(point);
      queryClient.invalidateQueries({ queryKey: ["content-point", pointId] });
      queryClient.invalidateQueries({ queryKey: ["content-points"] });
      toast.success("Point saved.");
    },
    onError: (error) => toast.error(error.message),
  });

  const statusMutation = useMutation({
    mutationFn: (status: "draft" | "needsRevision" | "approved") =>
      contentApi.setStatus(pointId, status, reviewNotes),
    onSuccess: ({ point }) => {
      setDraft(point);
      queryClient.invalidateQueries({ queryKey: ["content-point", pointId] });
      queryClient.invalidateQueries({ queryKey: ["content-points"] });
      toast.success(`Status set to ${point.status}.`);
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

  function update<K extends keyof GrammarPoint>(key: K, value: GrammarPoint[K]) {
    setDraft((prev) => (prev ? { ...prev, [key]: value } : prev));
  }

  return (
    <div className="flex flex-1 flex-col gap-6">
      <div className="flex items-start justify-between gap-4">
        <div>
          <div className="flex items-center gap-2">
            <h1 className="text-2xl font-semibold tracking-tight">
              {draft.title}
            </h1>
            <Badge variant={statusBadgeVariant[draft.status]}>
              {draft.status}
            </Badge>
          </div>
          <p className="text-sm text-muted-foreground">{draft.id}</p>
        </div>
        <div className="flex gap-2">
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
          <TabsTrigger value="formation">Formation</TabsTrigger>
          <TabsTrigger value="usage">Usage</TabsTrigger>
          <TabsTrigger value="examples">Examples</TabsTrigger>
          <TabsTrigger value="drills">Drills</TabsTrigger>
          <TabsTrigger value="raw">Raw JSON</TabsTrigger>
          <TabsTrigger value="review">Review</TabsTrigger>
        </TabsList>

        <TabsContent value="overview" className="flex flex-col gap-4 pt-4">
          <div className="flex justify-end">
            <RegenerateSectionButton
              pointId={pointId}
              task="overview"
              onGenerated={(point) => setDraft(point)}
            />
          </div>
          <div className="grid grid-cols-2 gap-4">
            <div className="flex flex-col gap-2">
              <Label>Title</Label>
              <Input
                value={draft.title}
                onChange={(e) => update("title", e.target.value)}
              />
            </div>
            <div className="flex flex-col gap-2">
              <Label>Pattern</Label>
              <Input
                value={draft.pattern ?? ""}
                onChange={(e) => update("pattern", e.target.value)}
              />
            </div>
            <div className="flex flex-col gap-2">
              <Label>Reading</Label>
              <Input
                value={draft.reading ?? ""}
                onChange={(e) => update("reading", e.target.value)}
              />
            </div>
            <div className="flex flex-col gap-2">
              <Label>Register</Label>
              <Select
                value={draft.register ?? "none"}
                onValueChange={(value) => {
                  if (!value) return;
                  update(
                    "register",
                    value === "none"
                      ? null
                      : (value as "casual" | "polite" | "formal")
                  );
                }}
              >
                <SelectTrigger className="w-full">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="none">—</SelectItem>
                  <SelectItem value="casual">Casual</SelectItem>
                  <SelectItem value="polite">Polite</SelectItem>
                  <SelectItem value="formal">Formal</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </div>

          <div className="flex flex-col gap-2">
            <Label>Headline (English)</Label>
            <Input
              value={draft.headlineEnglish}
              onChange={(e) => update("headlineEnglish", e.target.value)}
            />
          </div>

          <div className="flex flex-col gap-2">
            <Label>Short definition</Label>
            <Input
              value={draft.shortDefinition ?? ""}
              onChange={(e) => update("shortDefinition", e.target.value)}
            />
          </div>

          <div className="flex flex-col gap-2">
            <Label>Blurb</Label>
            <Textarea
              rows={3}
              value={draft.blurb ?? ""}
              onChange={(e) => update("blurb", e.target.value)}
            />
          </div>

          <div className="flex flex-col gap-2">
            <Label>Structure</Label>
            <Textarea
              rows={3}
              value={draft.structure ?? ""}
              onChange={(e) => update("structure", e.target.value)}
            />
          </div>

          <div className="flex flex-col gap-2">
            <Label>Forms (one per line)</Label>
            <Textarea
              rows={2}
              value={draft.forms.join("\n")}
              onChange={(e) =>
                update(
                  "forms",
                  e.target.value.split("\n").filter((f) => f.trim())
                )
              }
            />
          </div>

          <div className="flex flex-col gap-2">
            <Label>Related point IDs (comma separated)</Label>
            <Input
              value={draft.relatedPointIds.join(", ")}
              onChange={(e) =>
                update(
                  "relatedPointIds",
                  e.target.value
                    .split(",")
                    .map((s) => s.trim())
                    .filter(Boolean)
                )
              }
            />
          </div>
        </TabsContent>

        <TabsContent value="formation" className="flex flex-col gap-4 pt-4">
          <div className="flex justify-end">
            <RegenerateSectionButton
              pointId={pointId}
              task="formation"
              onGenerated={(point) => setDraft(point)}
            />
          </div>
          <TeachingBlockEditor
            label="Formation blocks"
            blocks={draft.formation}
            onChange={(blocks) => update("formation", blocks)}
          />
        </TabsContent>

        <TabsContent value="usage" className="flex flex-col gap-6 pt-4">
          <div className="flex justify-end gap-2">
            <RegenerateSectionButton
              pointId={pointId}
              task="usage"
              onGenerated={(point) => setDraft(point)}
            />
            <RegenerateSectionButton
              pointId={pointId}
              task="usageLadders"
              onGenerated={(point) => setDraft(point)}
            />
          </div>
          <TeachingBlockEditor
            label="Usage blocks"
            blocks={draft.usage ?? []}
            onChange={(blocks) => update("usage", blocks)}
          />
          <UsageLadderEditor
            ladders={draft.usageLadders ?? []}
            onChange={(ladders) => update("usageLadders", ladders)}
          />
        </TabsContent>

        <TabsContent value="examples" className="flex flex-col gap-4 pt-4">
          <div className="flex justify-end">
            <RegenerateSectionButton
              pointId={pointId}
              task="example"
              onGenerated={(point) => setDraft(point)}
            />
          </div>
          <ExampleEditor
            examples={draft.examples}
            onChange={(examples) => update("examples", examples)}
          />
        </TabsContent>

        <TabsContent value="drills" className="flex flex-col gap-4 pt-4">
          <div className="flex justify-end">
            <RegenerateSectionButton
              pointId={pointId}
              task="drills"
              onGenerated={(point) => setDraft(point)}
            />
          </div>
          <DrillEditor
            drills={draft.drills}
            onChange={(drills) => update("drills", drills)}
          />
        </TabsContent>

        <TabsContent value="raw" className="pt-4">
          <RawJsonEditor
            point={draft}
            onApply={(point) => setDraft(point)}
          />
        </TabsContent>

        <TabsContent value="review" className="flex flex-col gap-4 pt-4">
          <div className="flex flex-col gap-2">
            <Label>Review notes</Label>
            <Textarea
              rows={4}
              value={reviewNotes}
              onChange={(e) => setReviewNotes(e.target.value)}
            />
          </div>
          <div className="flex gap-2">
            <Button
              variant="outline"
              onClick={() => statusMutation.mutate("approved")}
              disabled={statusMutation.isPending}
            >
              Approve
            </Button>
            <Button
              variant="outline"
              onClick={() => statusMutation.mutate("needsRevision")}
              disabled={statusMutation.isPending}
            >
              Request revision
            </Button>
            <Button
              variant="ghost"
              onClick={() => statusMutation.mutate("draft")}
              disabled={statusMutation.isPending}
            >
              Revert to draft
            </Button>
          </div>
        </TabsContent>
      </Tabs>
    </div>
  );
}
