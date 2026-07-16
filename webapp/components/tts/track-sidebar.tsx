"use client";

import { useMemo, useRef, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Skeleton } from "@/components/ui/skeleton";
import { cn } from "@/lib/utils";
import { ttsApi, type ProjectSummary } from "@/lib/tts/client";
import { Plus, FileJson, ChevronDown, ChevronRight } from "lucide-react";

function TrackRow({
  project,
  activeId,
}: {
  project: ProjectSummary;
  activeId?: string;
}) {
  return (
    <Link
      href={`/tts/${project.id}`}
      className={cn(
        "flex flex-col gap-0.5 rounded-md px-3 py-2 text-sm transition-colors",
        project.id === activeId
          ? "bg-accent text-accent-foreground"
          : "hover:bg-accent/50"
      )}
    >
      <span className="font-medium">{project.displayName}</span>
      <span className="text-xs text-muted-foreground">
        {project.provider} · {project.variantCount} take
        {project.variantCount === 1 ? "" : "s"}
      </span>
    </Link>
  );
}

function GroupSection({
  title,
  projects,
  activeId,
}: {
  title: string;
  projects: ProjectSummary[];
  activeId?: string;
}) {
  const [open, setOpen] = useState(true);
  return (
    <div className="flex flex-col gap-1">
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        className="flex items-center gap-1 rounded-md px-2 py-1 text-xs font-semibold uppercase tracking-wide text-muted-foreground hover:text-foreground"
      >
        {open ? (
          <ChevronDown className="size-3" />
        ) : (
          <ChevronRight className="size-3" />
        )}
        {title}
        <span className="font-normal normal-case">({projects.length})</span>
      </button>
      {open && (
        <div className="flex flex-col gap-1 pl-2">
          {projects.map((project) => (
            <TrackRow key={project.id} project={project} activeId={activeId} />
          ))}
        </div>
      )}
    </div>
  );
}

export function TrackSidebar({ activeId }: { activeId?: string }) {
  const router = useRouter();
  const queryClient = useQueryClient();
  const collectionInputRef = useRef<HTMLInputElement>(null);

  const { data, isLoading } = useQuery({
    queryKey: ["tts-projects"],
    queryFn: ttsApi.listProjects,
  });

  const createMutation = useMutation({
    mutationFn: () =>
      ttsApi.createProject({
        promptText: "",
        provider: "openai",
        voice: "coral",
        model: "gpt-4o-mini-tts",
        trackName: null,
      }),
    onSuccess: ({ project }) => {
      queryClient.invalidateQueries({ queryKey: ["tts-projects"] });
      router.push(`/tts/${project.id}`);
    },
    onError: (error) => toast.error(error.message),
  });

  const importCollectionMutation = useMutation({
    mutationFn: async (file: File) => {
      const formData = new FormData();
      formData.append("file", file);
      const res = await fetch("/api/tts/import-collection", {
        method: "POST",
        body: formData,
      });
      if (!res.ok) {
        const body = await res.json().catch(() => ({}));
        throw new Error(body?.error ?? "Import failed");
      }
      return res.json() as Promise<{
        groupTitle: string;
        created: number;
        updated: number;
        trackIds: string[];
      }>;
    },
    onSuccess: ({ groupTitle, created, updated, trackIds }) => {
      queryClient.invalidateQueries({ queryKey: ["tts-projects"] });
      const parts = [];
      if (created > 0) parts.push(`${created} created`);
      if (updated > 0) parts.push(`${updated} updated`);
      toast.success(`Imported "${groupTitle}" — ${parts.join(", ")}.`);
      if (trackIds[0]) router.push(`/tts/${trackIds[0]}`);
    },
    onError: (error) => toast.error(error.message),
  });

  const projects = data?.projects ?? [];

  const { grouped, ungrouped } = useMemo(() => {
    const groups = new Map<string, { title: string; projects: ProjectSummary[] }>();
    const loose: ProjectSummary[] = [];
    for (const project of projects) {
      if (project.groupId) {
        const key = project.groupId;
        if (!groups.has(key)) {
          groups.set(key, { title: project.groupTitle ?? key, projects: [] });
        }
        groups.get(key)!.projects.push(project);
      } else {
        loose.push(project);
      }
    }
    for (const group of groups.values()) {
      group.projects.sort(
        (a, b) => (a.groupOrderIndex ?? 0) - (b.groupOrderIndex ?? 0)
      );
    }
    return { grouped: [...groups.values()], ungrouped: loose };
  }, [projects]);

  return (
    <div className="flex w-72 shrink-0 flex-col gap-3 border-r border-border/60 pr-4">
      <Button
        size="sm"
        className="w-full justify-start gap-2"
        onClick={() => createMutation.mutate()}
        disabled={createMutation.isPending}
      >
        <Plus className="size-4" />
        New track
      </Button>
      <Button
        size="sm"
        variant="outline"
        className="w-full justify-start gap-2"
        onClick={() => collectionInputRef.current?.click()}
        disabled={importCollectionMutation.isPending}
      >
        <FileJson className="size-4" />
        {importCollectionMutation.isPending
          ? "Importing…"
          : "Import dialogue JSON"}
      </Button>
      <input
        ref={collectionInputRef}
        type="file"
        accept=".json"
        className="hidden"
        onChange={(e) => {
          const file = e.target.files?.[0];
          if (file) importCollectionMutation.mutate(file);
          e.target.value = "";
        }}
      />

      <ScrollArea className="flex-1">
        <div className="flex flex-col gap-3">
          {isLoading &&
            Array.from({ length: 4 }).map((_, i) => (
              <Skeleton key={i} className="h-14 w-full rounded-md" />
            ))}

          {!isLoading && projects.length === 0 && (
            <p className="px-2 py-4 text-sm text-muted-foreground">
              No tracks yet.
            </p>
          )}

          {grouped.map((group) => (
            <GroupSection
              key={group.title}
              title={group.title}
              projects={group.projects}
              activeId={activeId}
            />
          ))}

          {ungrouped.length > 0 && (
            <div className="flex flex-col gap-1">
              {grouped.length > 0 && (
                <div className="px-2 py-1 text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                  Tracks
                </div>
              )}
              {ungrouped.map((project) => (
                <TrackRow
                  key={project.id}
                  project={project}
                  activeId={activeId}
                />
              ))}
            </div>
          )}
        </div>
      </ScrollArea>
    </div>
  );
}
