"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { Plus, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { dialogueApi, type UnitNotes } from "@/lib/dialogue/client";
import { CreateCollectionDialog } from "@/components/dialogue/create-collection-dialog";

/** Build a notes doc from form fields; empty sections omitted; all-empty → null. */
function notesFromForm(sections: {
  storyboard: string;
  characters: string;
  background: string;
  freeform: string;
}): UnitNotes | null {
  const notes: UnitNotes = {};
  const storyboard = sections.storyboard.trim();
  const characters = sections.characters.trim();
  const background = sections.background.trim();
  const freeform = sections.freeform.trim();
  if (storyboard) notes.storyboard = storyboard;
  if (characters) notes.characters = characters;
  if (background) notes.background = background;
  if (freeform) notes.freeform = freeform;
  return Object.keys(notes).length > 0 ? notes : null;
}

export function UnitEditor({ unitId }: { unitId: string }) {
  const router = useRouter();
  const queryClient = useQueryClient();

  const { data: unitsData, isLoading: unitsLoading } = useQuery({
    queryKey: ["curriculum-units"],
    queryFn: dialogueApi.listUnits,
  });
  const { data: collectionsData, isLoading: collectionsLoading } = useQuery({
    queryKey: ["dialogue-collections"],
    queryFn: dialogueApi.listCollections,
  });

  const unit = unitsData?.units.find((u) => u.id === unitId);
  const collections = (collectionsData?.collections ?? []).filter(
    (c) => c.unitId === unitId,
  );

  const [title, setTitle] = useState("");
  const [subtitle, setSubtitle] = useState("");
  const [jlptLevel, setJlptLevel] = useState("5");
  const [storyboard, setStoryboard] = useState("");
  const [characters, setCharacters] = useState("");
  const [background, setBackground] = useState("");
  const [freeform, setFreeform] = useState("");
  const [createOpen, setCreateOpen] = useState(false);

  useEffect(() => {
    if (unit) {
      setTitle(unit.title);
      setSubtitle(unit.subtitle ?? "");
      setJlptLevel(String(unit.jlptLevel));
      setStoryboard(unit.notes?.storyboard ?? "");
      setCharacters(unit.notes?.characters ?? "");
      setBackground(unit.notes?.background ?? "");
      setFreeform(unit.notes?.freeform ?? "");
    }
  }, [unit]);

  const saveMutation = useMutation({
    mutationFn: () =>
      dialogueApi.updateUnit(unitId, {
        title: title.trim(),
        subtitle: subtitle.trim() || null,
        jlptLevel: Number(jlptLevel),
        notes: notesFromForm({
          storyboard,
          characters,
          background,
          freeform,
        }),
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["curriculum-units"] });
      toast.success("Unit saved.");
    },
    onError: (error) => toast.error(error.message),
  });

  const deleteMutation = useMutation({
    mutationFn: () => dialogueApi.deleteUnit(unitId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["curriculum-units"] });
      queryClient.invalidateQueries({ queryKey: ["dialogue-collections"] });
      toast.success("Unit deleted.");
      router.push("/content/dialogues");
    },
    onError: (error) => toast.error(error.message),
  });

  if (unitsLoading || collectionsLoading) {
    return (
      <div className="flex flex-1 flex-col gap-4">
        <Skeleton className="h-8 w-64" />
        <Skeleton className="h-48 w-full" />
      </div>
    );
  }

  if (!unit) {
    return (
      <div className="flex flex-1 items-center justify-center text-sm text-muted-foreground">
        Unit not found.
      </div>
    );
  }

  return (
    <div className="flex flex-1 flex-col gap-6">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">
            {unit.title}
          </h1>
          <p className="text-sm text-muted-foreground">
            {unit.id} · N{unit.jlptLevel}
          </p>
        </div>
        <Button
          variant="outline"
          onClick={() => saveMutation.mutate()}
          disabled={saveMutation.isPending}
        >
          Save
        </Button>
      </div>

      <div className="grid max-w-2xl grid-cols-2 gap-4">
        <div className="flex flex-col gap-2">
          <Label>Title</Label>
          <Input value={title} onChange={(e) => setTitle(e.target.value)} />
        </div>
        <div className="flex flex-col gap-2">
          <Label>JLPT level</Label>
          <Select
            value={jlptLevel}
            onValueChange={(value) => setJlptLevel(value ?? "5")}
          >
            <SelectTrigger>
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {[5, 4, 3, 2, 1].map((level) => (
                <SelectItem key={level} value={String(level)}>
                  N{level}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        <div className="col-span-2 flex flex-col gap-2">
          <Label>Subtitle</Label>
          <Textarea
            rows={2}
            value={subtitle}
            onChange={(e) => setSubtitle(e.target.value)}
          />
        </div>
      </div>

      <div className="flex max-w-2xl flex-col gap-4 border-t border-border/60 pt-4">
        <div>
          <Label className="text-base">Writer notes</Label>
          <p className="mt-1 text-xs text-muted-foreground">
            Studio-only drafting space for storyboard, cast, and backstory.
            Sections save together on the unit; they never ship in public
            dialogue export or the app.
          </p>
        </div>
        <div className="flex flex-col gap-2">
          <Label>Storyboard</Label>
          <Textarea
            rows={4}
            value={storyboard}
            onChange={(e) => setStoryboard(e.target.value)}
            placeholder="Beat outline for the unit — lesson flow, scene sequence, teaching beats…"
          />
        </div>
        <div className="flex flex-col gap-2">
          <Label>Characters</Label>
          <Textarea
            rows={3}
            value={characters}
            onChange={(e) => setCharacters(e.target.value)}
            placeholder="Recurring cast notes — names, relationship, tone, voice direction…"
          />
        </div>
        <div className="flex flex-col gap-2">
          <Label>Background</Label>
          <Textarea
            rows={3}
            value={background}
            onChange={(e) => setBackground(e.target.value)}
            placeholder="Setting and backstory that lessons in this unit share…"
          />
        </div>
        <div className="flex flex-col gap-2">
          <Label>Freeform</Label>
          <Textarea
            rows={3}
            value={freeform}
            onChange={(e) => setFreeform(e.target.value)}
            placeholder="Anything else — open paste space for drafts and scratch notes…"
          />
        </div>
      </div>

      <div className="flex max-w-2xl flex-col gap-3">
        <div className="flex items-center justify-between gap-4">
          <Label>Lessons in this unit</Label>
          <Button
            variant="outline"
            size="sm"
            className="gap-2"
            onClick={() => setCreateOpen(true)}
          >
            <Plus className="size-4" />
            New lesson
          </Button>
        </div>

        {collections.length === 0 && (
          <p className="text-sm text-muted-foreground">
            No lessons in this unit yet.
          </p>
        )}

        {collections.map((collection) => (
          <Link
            key={collection.id}
            href={`/content/dialogues/${collection.id}`}
            className="flex flex-col rounded-md border border-border/60 px-3 py-2 text-sm transition-colors hover:bg-accent/50"
          >
            <span className="font-medium">{collection.title}</span>
            <span className="text-xs text-muted-foreground">
              {collection.id} · {collection.scenarios.length} scenarios
            </span>
          </Link>
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
                `Delete unit "${unit.title}"? Its lessons will become unfiled.`,
              )
            ) {
              deleteMutation.mutate();
            }
          }}
          disabled={deleteMutation.isPending}
        >
          <Trash2 className="size-4" />
          Delete unit
        </Button>
      </div>

      <CreateCollectionDialog
        open={createOpen}
        onOpenChange={setCreateOpen}
        units={unitsData?.units ?? []}
        defaultUnitId={unitId}
        lockUnit
      />
    </div>
  );
}
