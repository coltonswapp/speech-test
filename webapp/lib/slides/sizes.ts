import type { ExportSizeId } from "./types";

export type ExportCanvas = {
  id: ExportSizeId;
  title: string;
  shortTitle: string;
  width: number;
  height: number;
  pixelWidth: number;
  pixelHeight: number;
};

const SCALE = 3;

export const EXPORT_SIZES: Record<ExportSizeId, ExportCanvas> = {
  feedPortrait: {
    id: "feedPortrait",
    title: "Post (4:5)",
    shortTitle: "4:5",
    width: 360,
    height: 450,
    pixelWidth: 360 * SCALE,
    pixelHeight: 450 * SCALE,
  },
  square: {
    id: "square",
    title: "Square (1:1)",
    shortTitle: "1:1",
    width: 360,
    height: 360,
    pixelWidth: 360 * SCALE,
    pixelHeight: 360 * SCALE,
  },
  story: {
    id: "story",
    title: "Story (9:16)",
    shortTitle: "9:16",
    width: 360,
    height: 640,
    pixelWidth: 360 * SCALE,
    pixelHeight: 640 * SCALE,
  },
};

export const EXPORT_SIZE_LIST: ExportCanvas[] = [
  EXPORT_SIZES.feedPortrait,
  EXPORT_SIZES.square,
  EXPORT_SIZES.story,
];

export const EXPORT_PIXEL_SCALE = SCALE;
