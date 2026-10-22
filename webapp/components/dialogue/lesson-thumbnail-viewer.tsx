"use client";

import { useEffect, useRef, useState } from "react";
import { toast } from "sonner";
import { Download, MoreHorizontal, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { dialogueApi } from "@/lib/dialogue/client";
import {
  hasDownloadableThumbnails,
  type LessonThumbnailItem,
} from "@/lib/dialogue/lesson-thumbnails";
import { cn } from "@/lib/utils";

function triggerBlobDownload(blob: Blob, filename: string) {
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  link.remove();
  URL.revokeObjectURL(url);
}

function filenameFromDisposition(
  header: string | null,
  fallback: string
): string {
  if (!header) return fallback;
  const utf = header.match(/filename\*=UTF-8''([^;]+)/i);
  if (utf?.[1]) {
    try {
      return decodeURIComponent(utf[1]);
    } catch {
      return fallback;
    }
  }
  const ascii = header.match(/filename="([^"]+)"/i);
  return ascii?.[1] ?? fallback;
}

export function LessonThumbnailViewer({
  open,
  onOpenChange,
  collectionId,
  items,
  initialId,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  collectionId: string;
  items: LessonThumbnailItem[];
  initialId: string | null;
}) {
  const [index, setIndex] = useState(0);
  const [sessionKey, setSessionKey] = useState<string | null>(null);
  const [brokenId, setBrokenId] = useState<string | null>(null);
  const [zipping, setZipping] = useState(false);
  const filmstripRef = useRef<HTMLDivElement>(null);

  const nextSessionKey = open ? (initialId ?? "") : null;
  if (nextSessionKey !== sessionKey) {
    setSessionKey(nextSessionKey);
    if (nextSessionKey) {
      const next = initialId
        ? items.findIndex((item) => item.id === initialId)
        : 0;
      setIndex(next >= 0 ? next : 0);
      setBrokenId(null);
    }
  }

  const current = items[index] ?? null;
  const broken = !!current && brokenId === current.id;

  useEffect(() => {
    if (!open) return;
    const selected = filmstripRef.current?.querySelector<HTMLElement>(
      `[data-thumb-index="${index}"]`
    );
    selected?.scrollIntoView({
      inline: "center",
      block: "nearest",
      behavior: "smooth",
    });
  }, [index, open]);

  useEffect(() => {
    if (!open || items.length === 0) return;
    function onKey(event: KeyboardEvent) {
      const target = event.target;
      if (
        target instanceof HTMLElement &&
        target.closest("[data-slot='dropdown-menu-content']")
      ) {
        return;
      }
      if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") return;
      event.preventDefault();
      event.stopPropagation();
      const delta = event.key === "ArrowLeft" ? -1 : 1;
      setIndex((value) => {
        const next = value + delta;
        if (next < 0) return items.length - 1;
        if (next >= items.length) return 0;
        return next;
      });
    }
    window.addEventListener("keydown", onKey, true);
    return () => window.removeEventListener("keydown", onKey, true);
  }, [open, items.length]);

  const canDownloadCurrent = !!current?.thumbnailUrl && !broken;
  const canDownloadAll = hasDownloadableThumbnails(items);

  function downloadCurrent() {
    if (!current?.thumbnailUrl) return;
    const link = document.createElement("a");
    link.href = dialogueApi.thumbnailFileUrl(collectionId, current);
    link.rel = "noreferrer";
    document.body.appendChild(link);
    link.click();
    link.remove();
  }

  async function downloadAll() {
    if (!canDownloadAll || zipping) return;
    setZipping(true);
    try {
      const res = await fetch(dialogueApi.thumbnailZipUrl(collectionId));
      if (!res.ok) {
        const body = await res.json().catch(() => ({}));
        throw new Error(
          typeof body?.error === "string"
            ? body.error
            : "Could not download thumbnails."
        );
      }
      const blob = await res.blob();
      triggerBlobDownload(
        blob,
        filenameFromDisposition(res.headers.get("content-disposition"), `${collectionId}-thumbnails.zip`)
      );
      toast.success("Downloaded all lesson thumbnails.");
    } catch (error) {
      toast.error(
        error instanceof Error ? error.message : "Could not download thumbnails."
      );
    } finally {
      setZipping(false);
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent
        showCloseButton={false}
        className="fixed inset-0 top-0 left-0 flex h-dvh max-h-dvh w-full max-w-none transform-none flex-col gap-0 rounded-none bg-black p-0 text-white ring-0 sm:max-w-none data-open:zoom-in-100 data-closed:zoom-out-100"
      >
        <DialogTitle className="sr-only">
          {current?.caption ?? "Lesson thumbnails"}
        </DialogTitle>

        <div className="flex shrink-0 items-center justify-between px-2 pt-[max(0.5rem,env(safe-area-inset-top))] sm:px-3">
          <Button
            type="button"
            variant="ghost"
            size="icon"
            className="size-11 text-white hover:bg-white/10 hover:text-white md:size-10"
            onClick={() => onOpenChange(false)}
            aria-label="Close thumbnail viewer"
          >
            <X className="size-6" />
          </Button>
          <DropdownMenu>
            <DropdownMenuTrigger
              render={
                <Button
                  type="button"
                  variant="ghost"
                  size="icon"
                  className="size-11 text-white hover:bg-white/10 hover:text-white md:size-10"
                  aria-label="Thumbnail actions"
                >
                  <MoreHorizontal className="size-6" />
                </Button>
              }
            />
            <DropdownMenuContent
              align="end"
              className="min-w-44 bg-neutral-900 text-white ring-white/20"
            >
              <DropdownMenuItem
                onClick={downloadCurrent}
                disabled={!canDownloadCurrent}
              >
                <Download />
                Download
              </DropdownMenuItem>
              <DropdownMenuItem onClick={downloadAll} disabled={!canDownloadAll || zipping}>
                <Download />
                {zipping ? "Preparing zip…" : "Download all"}
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        </div>

        <div className="flex min-h-0 flex-1 flex-col items-center justify-center px-4 py-2 sm:px-8">
          {current?.thumbnailUrl && !broken ? (
            // eslint-disable-next-line @next/next/no-img-element -- CDN lesson thumbs; arbitrary host
            <img
              src={current.thumbnailUrl}
              alt={current.caption}
              onError={() => setBrokenId(current.id)}
              className="max-h-full max-w-full rounded-3xl object-contain shadow-[0_20px_60px_rgba(0,0,0,0.45)]"
            />
          ) : (
            <div className="flex aspect-square w-full max-w-md items-center justify-center rounded-3xl border border-white/15 bg-neutral-950 text-sm text-white/50">
              No thumbnail
            </div>
          )}
        </div>

        <p className="shrink-0 px-4 pb-2 text-center text-sm text-white/85 sm:text-base">
          {current?.caption ?? "No thumbnails"}
          {current?.inherited ? (
            <span className="mt-0.5 block text-xs text-white/45">
              Inherits the lesson thumbnail
            </span>
          ) : null}
        </p>

        <div
          ref={filmstripRef}
          className="shrink-0 overflow-x-auto px-4 pb-[max(1rem,env(safe-area-inset-bottom))] [scrollbar-width:none] sm:px-8 [&::-webkit-scrollbar]:hidden"
          role="listbox"
          aria-label="Lesson thumbnails"
        >
          <div className="flex w-max min-w-full items-center justify-center gap-2">
          {items.map((item, itemIndex) => {
            const selected = itemIndex === index;
            const src = item.thumbnailSmallUrl ?? item.thumbnailUrl;
            return (
              <button
                key={item.id}
                type="button"
                data-thumb-index={itemIndex}
                role="option"
                aria-selected={selected}
                aria-label={item.caption}
                onClick={() => setIndex(itemIndex)}
                className={cn(
                  "size-12 shrink-0 overflow-hidden rounded-lg border-2 bg-neutral-900 transition-colors sm:size-14",
                  selected
                    ? "border-white"
                    : "border-transparent opacity-70 hover:opacity-100"
                )}
              >
                {src ? (
                  // eslint-disable-next-line @next/next/no-img-element -- CDN lesson thumbs; arbitrary host
                  <img
                    src={src}
                    alt=""
                    className="size-full object-cover"
                  />
                ) : (
                  <span className="flex size-full items-center justify-center text-[10px] text-white/35">
                    —
                  </span>
                )}
              </button>
            );
          })}
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}
