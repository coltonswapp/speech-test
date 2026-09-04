"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { MoreVertical } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Accordion,
  AccordionItem,
  AccordionTrigger,
  AccordionPanel,
} from "@/components/ui/accordion";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuTrigger,
  DropdownMenuContent,
  DropdownMenuItem,
} from "@/components/ui/dropdown-menu";
import { ttsApi } from "@/lib/tts/client";
import { WaveformEditor } from "@/components/tts/waveform-editor";
import type { EditableDialogueLine } from "@/components/tts/dialogue-line-editor";

export function VariantList({
  projectId,
  dialogueLines,
  currentContentHash,
  selectedVariantId,
  hasUnsavedChanges,
}: {
  projectId: string;
  dialogueLines?: EditableDialogueLine[];
  /** When set, takes whose contentHash differs are badged as stale. */
  currentContentHash?: string;
  /** When set, enables explicit take selection and badges off this id instead of isSelected. */
  selectedVariantId?: string | null;
  hasUnsavedChanges?: boolean;
}) {
  const queryClient = useQueryClient();
  const { data, isLoading } = useQuery({
    queryKey: ["tts-variants", projectId],
    queryFn: () => ttsApi.listVariants(projectId),
  });

  const selectMutation = useMutation({
    mutationFn: (variantId: string) =>
      ttsApi.selectVariant(projectId, variantId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["tts-project", projectId] });
      queryClient.invalidateQueries({ queryKey: ["tts-projects"] });
      queryClient.invalidateQueries({ queryKey: ["scenario-audio"] });
      toast.success("Take selected.");
    },
    onError: (error) => toast.error(error.message),
  });

  const deleteMutation = useMutation({
    mutationFn: (variantId: string) =>
      ttsApi.deleteVariant(projectId, variantId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["tts-variants", projectId] });
      queryClient.invalidateQueries({ queryKey: ["tts-project", projectId] });
      queryClient.invalidateQueries({ queryKey: ["tts-projects"] });
      queryClient.invalidateQueries({ queryKey: ["scenario-audio"] });
      toast.success("Take deleted.");
    },
    onError: (error) => toast.error(error.message),
  });

  const regenerateMutation = useMutation({
    mutationFn: (variant: NonNullable<typeof data>["variants"][number]) => {
      const isConversation = variant.voice.includes("/");
      if (isConversation) {
        const [speaker1Voice, speaker2Voice] = variant.voice.split("/");
        return ttsApi.generate(projectId, { speaker1Voice, speaker2Voice });
      }
      return ttsApi.generate(projectId, {
        voice: variant.voice,
        provider: variant.provider,
      });
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["tts-variants", projectId] });
      queryClient.invalidateQueries({ queryKey: ["tts-projects"] });
      toast.success("New take generated with the same settings.");
    },
    onError: (error) => toast.error(error.message),
  });

  const ignoreMutation = useMutation({
    mutationFn: (variantId: string) =>
      ttsApi.acceptScript(projectId, variantId, currentContentHash),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["tts-variants", projectId] });
      queryClient.invalidateQueries({ queryKey: ["tts-project", projectId] });
      queryClient.invalidateQueries({ queryKey: ["tts-projects"] });
      queryClient.invalidateQueries({ queryKey: ["scenario-audio"] });
      queryClient.invalidateQueries({ queryKey: ["dialogue-scenario"] });
      queryClient.invalidateQueries({
        queryKey: ["dialogue-collection-audio-status"],
      });
      toast.success("Kept this take. Text-change badge cleared.");
    },
    onError: (error) => toast.error(error.message),
  });

  const variants = data?.variants ?? [];
  const selectionEnabled = selectedVariantId !== undefined;

  return (
    // overflow-visible so the waveform editor's sticky player can pin to the
    // viewport while sentence-map rows scroll underneath (Card defaults to
    // overflow-hidden for corner clipping).
    <Card className="overflow-visible">
      <CardHeader>
        <CardTitle className="text-base font-medium">Takes</CardTitle>
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        {isLoading && (
          <p className="text-sm text-muted-foreground">Loading…</p>
        )}
        {!isLoading && variants.length === 0 && (
          <p className="text-sm text-muted-foreground">
            No takes yet — generate one above.
          </p>
        )}
        {variants.length > 0 && (
          <Accordion defaultValue={[variants[0].id]}>
            {variants.map((variant) => {
              const isSelected = selectionEnabled
                ? variant.id === selectedVariantId
                : variant.isSelected;
              const isStale =
                !!currentContentHash &&
                !!variant.contentHash &&
                variant.contentHash !== currentContentHash;
              return (
                <AccordionItem key={variant.id} value={variant.id}>
                  <div className="flex min-w-0 items-center gap-1">
                    <AccordionTrigger className="min-h-11 flex-1 touch-manipulation justify-start gap-2 py-2 md:min-h-0">
                      <span className="flex min-w-0 flex-wrap items-center gap-2 text-sm">
                        <span>
                          {new Date(variant.createdAt).toLocaleString()}
                        </span>
                        <span className="text-xs text-muted-foreground">
                          {variant.voice}
                        </span>
                        {isSelected && (
                          <Badge variant="secondary">Selected</Badge>
                        )}
                        {isStale && (
                          <Badge
                            variant="outline"
                            className="border-amber-500/50 text-amber-600 dark:text-amber-400"
                          >
                            Text changed
                          </Badge>
                        )}
                        {!!currentContentHash && !variant.contentHash && (
                          <span
                            className="text-xs text-muted-foreground"
                            title="Generated before change tracking — staleness unknown."
                          >
                            untracked
                          </span>
                        )}
                      </span>
                    </AccordionTrigger>
                    <div className="ml-auto flex shrink-0 items-center">
                      <DropdownMenu>
                        <DropdownMenuTrigger
                          render={
                            <Button
                              variant="ghost"
                              size="icon"
                              className="size-10 shrink-0 touch-manipulation md:size-8"
                              onClick={(e) => e.stopPropagation()}
                            >
                              <MoreVertical className="size-4" />
                            </Button>
                          }
                        />
                        <DropdownMenuContent align="end">
                          {!!currentContentHash &&
                            variant.contentHash !== currentContentHash && (
                            <DropdownMenuItem
                              onClick={() => ignoreMutation.mutate(variant.id)}
                              disabled={ignoreMutation.isPending}
                            >
                              Ignore text changed
                            </DropdownMenuItem>
                          )}
                          <DropdownMenuItem
                            onClick={() => regenerateMutation.mutate(variant)}
                            disabled={regenerateMutation.isPending}
                          >
                            Regenerate with same settings
                          </DropdownMenuItem>
                          <DropdownMenuItem
                            variant="destructive"
                            onClick={() => {
                              if (
                                window.confirm(
                                  "Delete this take? This cannot be undone."
                                )
                              ) {
                                deleteMutation.mutate(variant.id);
                              }
                            }}
                            disabled={deleteMutation.isPending}
                          >
                            Delete take
                          </DropdownMenuItem>
                        </DropdownMenuContent>
                      </DropdownMenu>
                    </div>
                  </div>
                  <AccordionPanel className="overflow-visible">
                    <div className="flex flex-col gap-3">
                      {selectionEnabled && !isSelected && (
                        <Button
                          variant="outline"
                          size="sm"
                          className="min-h-11 w-full touch-manipulation sm:w-fit md:min-h-8"
                          onClick={() => selectMutation.mutate(variant.id)}
                          disabled={selectMutation.isPending}
                        >
                          Use this take
                        </Button>
                      )}
                      <WaveformEditor
                        projectId={projectId}
                        variant={variant}
                        dialogueLines={dialogueLines}
                        currentContentHash={currentContentHash}
                        hasUnsavedChanges={hasUnsavedChanges}
                      />
                    </div>
                  </AccordionPanel>
                </AccordionItem>
              );
            })}
          </Accordion>
        )}
      </CardContent>
    </Card>
  );
}
