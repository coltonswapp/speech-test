import JSZip from "jszip";
import { EXPORT_PIXEL_SCALE } from "@/lib/slides/sizes";

function waitForImages(root: HTMLElement): Promise<void> {
  const images = Array.from(root.querySelectorAll("img"));
  return Promise.all(
    images.map(
      (image) =>
        new Promise<void>((resolve) => {
          if (image.complete) {
            resolve();
            return;
          }
          image.addEventListener("load", () => resolve(), { once: true });
          image.addEventListener("error", () => resolve(), { once: true });
        })
    )
  ).then(() => undefined);
}

export async function captureSlidePng(node: HTMLElement): Promise<Blob> {
  await waitForImages(node);
  if (document.fonts?.ready) await document.fonts.ready;
  const { domToBlob } = await import("modern-screenshot");
  const blob = await domToBlob(node, {
    scale: EXPORT_PIXEL_SCALE,
    width: node.offsetWidth,
    height: node.offsetHeight,
    type: "image/png",
  });
  return blob;
}

export function downloadBlob(blob: Blob, filename: string) {
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  link.remove();
  URL.revokeObjectURL(url);
}

export async function zipPngs(
  files: Array<{ name: string; blob: Blob }>
): Promise<Blob> {
  const zip = new JSZip();
  for (const file of files) {
    zip.file(file.name, file.blob);
  }
  return zip.generateAsync({ type: "blob" });
}
