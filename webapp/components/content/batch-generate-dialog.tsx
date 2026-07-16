"use client";

import { useMemo, useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { SparklesIcon } from "lucide-react";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { ScrollArea } from "@/components/ui/scroll-area";
import { contentApi, type PointSummary } from "@/lib/content/client";
import { n5GrammarSeedCatalog } from "@/lib/content/seed-catalog";
import { cn } from "@/lib/utils";

type GenerationStatus = "pending" | "generating" | "done" | "error";

export function BatchGenerateDialog({ points }: { points: PointSummary[] }) {
  const queryClient = useQueryClient();
  const [open, setOpen] = useState(false);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [isRunning, setIsRunning] = useState(false);
  const [statuses, setStatuses] = useState<Record<string, GenerationStatus>>({});

  const existingIds = useMemo(() => new Set(points.map((p) => p.id)), [points]);
  const missingSeeds = useMemo(
    () => n5GrammarSeedCatalog.filter((seed) => !existingIds.has(seed.id)),
    [existingIds]
  );

  function toggle(id: string) {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  async function runGeneration() {
    const seeds = missingSeeds.filter((seed) => selected.has(seed.id));
    if (seeds.length === 0) return;

    setIsRunning(true);
    setStatuses(Object.fromEntries(seeds.map((s) => [s.id, "pending" as const])));

    let successCount = 0;
    for (const seed of seeds) {
      setStatuses((prev) => ({ ...prev, [seed.id]: "generating" }));
      try {
        await contentApi.generatePoint({
          pointID: seed.id,
          title: seed.title,
          headlineEnglish: seed.headlineEnglish,
          orderIndex: seed.orderIndex,
        });
        setStatuses((prev) => ({ ...prev, [seed.id]: "done" }));
        successCount++;
      } catch (error) {
        setStatuses((prev) => ({ ...prev, [seed.id]: "error" }));
        toast.error(
          `${seed.id}: ${error instanceof Error ? error.message : "generation failed"}`
        );
      }
    }

    queryClient.invalidateQueries({ queryKey: ["content-points"] });
    setIsRunning(false);
    if (successCount > 0) {
      toast.success(`Generated ${successCount} of ${seeds.length} point(s).`);
    }
  }

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        if (!isRunning) setOpen(next);
      }}
    >
      <Button
        variant="outline"
        size="sm"
        className="gap-1.5"
        onClick={() => setOpen(true)}
      >
        <SparklesIcon className="size-3.5" />
        Batch generate
      </Button>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Batch generate grammar points</DialogTitle>
          <DialogDescription>
            Select seed points not yet in the catalog. Each is generated with
            Gemini using approved points as gold examples, then saved as a
            draft.
          </DialogDescription>
        </DialogHeader>

        {missingSeeds.length === 0 ? (
          <p className="py-4 text-sm text-muted-foreground">
            All seed catalog points already exist.
          </p>
        ) : (
          <ScrollArea className="h-72 rounded-md border">
            <div className="flex flex-col divide-y">
              {missingSeeds.map((seed) => {
                const status = statuses[seed.id];
                return (
                  <label
                    key={seed.id}
                    className={cn(
                      "flex items-center gap-3 px-3 py-2 text-sm",
                      !isRunning && "cursor-pointer hover:bg-accent/50"
                    )}
                  >
                    <input
                      type="checkbox"
                      className="size-4 shrink-0"
                      checked={selected.has(seed.id)}
                      disabled={isRunning}
                      onChange={() => toggle(seed.id)}
                    />
                    <div className="flex min-w-0 flex-1 flex-col">
                      <span className="truncate font-medium">{seed.title}</span>
                      <span className="truncate text-xs text-muted-foreground">
                        {seed.id} — {seed.headlineEnglish}
                      </span>
                    </div>
                    {status && (
                      <span
                        className={cn(
                          "shrink-0 text-xs",
                          status === "done" && "text-emerald-500",
                          status === "error" && "text-destructive",
                          status === "generating" && "text-muted-foreground",
                          status === "pending" && "text-muted-foreground"
                        )}
                      >
                        {status === "generating"
                          ? "Generating…"
                          : status === "done"
                            ? "Done"
                            : status === "error"
                              ? "Failed"
                              : "Queued"}
                      </span>
                    )}
                  </label>
                );
              })}
            </div>
          </ScrollArea>
        )}

        <DialogFooter>
          <Button
            variant="outline"
            disabled={isRunning}
            onClick={() => setOpen(false)}
          >
            Close
          </Button>
          <Button
            disabled={isRunning || selected.size === 0}
            onClick={runGeneration}
          >
            {isRunning
              ? `Generating (${Object.values(statuses).filter((s) => s === "done" || s === "error").length}/${selected.size})…`
              : `Generate ${selected.size || ""}`.trim()}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
