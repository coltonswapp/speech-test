"use client";

import { useState } from "react";
import Link from "next/link";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { Trash2, Upload } from "lucide-react";
import { Button, buttonVariants } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { slidesApi } from "@/lib/slides/client";
import { photoThumbUrl } from "@/lib/slides/types";

export function PhotoLibrary() {
  const queryClient = useQueryClient();
  const { data, isLoading } = useQuery({
    queryKey: ["slide-photos"],
    queryFn: () => slidesApi.listPhotos(),
  });
  const [files, setFiles] = useState<File[]>([]);
  const [tags, setTags] = useState("");

  const upload = useMutation({
    mutationFn: () => slidesApi.uploadPhotos(files, tags),
    onSuccess: (result) => {
      queryClient.invalidateQueries({ queryKey: ["slide-photos"] });
      setFiles([]);
      toast.success(`Uploaded ${result.photos.length} photo${result.photos.length === 1 ? "" : "s"}.`);
    },
    onError: (error) => toast.error(error.message),
  });

  const remove = useMutation({
    mutationFn: (id: string) => slidesApi.deletePhoto(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["slide-photos"] });
      toast.success("Photo removed.");
    },
    onError: (error) => toast.error(error.message),
  });

  const photos = data?.photos ?? [];

  return (
    <div className="flex flex-col gap-6">
      <div>
        <Link href="/slides" className="text-sm text-muted-foreground hover:text-foreground">
          ← Slides
        </Link>
        <h1 className="mt-2 text-2xl font-semibold tracking-tight">Japan photos</h1>
        <p className="text-sm text-muted-foreground">
          Dump a folder of travel shots. Scatter recipes throw a handful behind
          every slide.
        </p>
      </div>

      <div className="flex flex-col gap-3 rounded-xl border border-border/60 p-4">
        <div className="max-w-md space-y-2">
          <Label htmlFor="photo-tags">Tags (optional, comma-separated)</Label>
          <Input
            id="photo-tags"
            placeholder="tokyo, train, night"
            value={tags}
            onChange={(event) => setTags(event.target.value)}
          />
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <label className={buttonVariants({ variant: "outline" })}>
            <Upload className="mr-1 size-3.5" />
            {files.length > 0 ? `${files.length} selected` : "Choose JPEG / PNG / WebP / HEIC"}
            <input
              type="file"
              accept="image/jpeg,image/png,image/webp,image/heic,image/heif,.jpg,.jpeg,.png,.webp,.heic"
              multiple
              className="sr-only"
              onChange={(event) =>
                setFiles(Array.from(event.target.files ?? []))
              }
            />
          </label>
          <Button
            onClick={() => upload.mutate()}
            disabled={upload.isPending || files.length === 0}
          >
            {upload.isPending ? "Uploading…" : "Upload"}
          </Button>
        </div>
      </div>

      {isLoading ? (
        <p className="text-sm text-muted-foreground">Loading photos…</p>
      ) : photos.length === 0 ? (
        <p className="text-sm text-muted-foreground">
          No photos yet. A handful is enough to judge the handmade look.
        </p>
      ) : (
        <ul className="grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5">
          {photos.map((photo) => (
            <li key={photo.id} className="overflow-hidden rounded-lg border border-border/60">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src={photoThumbUrl(photo.id)}
                alt={photo.title}
                className="aspect-square w-full object-cover"
              />
              <div className="flex items-start justify-between gap-2 p-2">
                <div className="min-w-0">
                  <div className="truncate text-xs font-medium">{photo.title}</div>
                  <div className="truncate text-[11px] text-muted-foreground">
                    {photo.tags.join(", ") || "untagged"}
                  </div>
                </div>
                <Button
                  variant="ghost"
                  size="icon-xs"
                  aria-label={`Delete ${photo.title}`}
                  onClick={() => remove.mutate(photo.id)}
                >
                  <Trash2 className="size-3.5" />
                </Button>
              </div>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
