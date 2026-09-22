import type { RecipeId, SlideRecipe } from "./types";

// Matches iOS UIFont.systemFont: SF Pro + SF Symbols for Latin/icons,
// Hiragino Sans for Japanese, Noto Sans JP when those faces are missing.
const SYSTEM_SANS =
  '-apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro Display", "SF Pro Icons", "Hiragino Sans", "Hiragino Kaku Gothic ProN", "Yu Gothic", var(--font-noto-sans-jp), "Noto Sans JP", sans-serif';

const lightChrome = {
  watermark: "shizenapp.com",
  cornerRadius: 10,
  cardBorderWidth: 1,
  heroWidth: 118,
  subjectHeroWidth: 136,
  exampleHeroWidth: 200,
  badgePlacement: "trailingEdgeCentered" as const,
};

const lightType = {
  titleSize: 24,
  titleWeight: 700,
  heroSize: 72,
  japaneseSize: 28,
  bodySize: 16,
  captionSize: 13,
  watermarkSize: 11,
  heroFont: SYSTEM_SANS,
  uiFont: SYSTEM_SANS,
};

export const SLIDE_RECIPES: Record<RecipeId, SlideRecipe> = {
  "studio-light": {
    id: "studio-light",
    name: "Studio light",
    background: {
      mode: "solid",
      scrim: "rgba(255, 255, 255, 0)",
      scatterCount: 0,
    },
    colors: {
      page: "#F2F2F2",
      surface: "#FFFFFF",
      border: "#E0E0E0",
      text: "#111111",
      muted: "#6B6B6B",
      tertiary: "#8A8A8A",
      badgeBg: "#FFF4CC",
      badgeText: "#AD7A00",
      watermark: "rgba(0, 0, 0, 0.35)",
      shadow: "rgba(0, 0, 0, 0.08)",
    },
    type: lightType,
    chrome: lightChrome,
  },
  "studio-dark": {
    id: "studio-dark",
    name: "Studio dark",
    background: {
      mode: "solid",
      scrim: "rgba(0, 0, 0, 0)",
      scatterCount: 0,
    },
    colors: {
      page: "#1C1C1E",
      surface: "#2C2C2E",
      border: "rgba(255, 255, 255, 0.12)",
      text: "#F5F5F5",
      muted: "#A1A1A6",
      tertiary: "#8E8E93",
      badgeBg: "rgba(140, 117, 26, 0.55)",
      badgeText: "#EBBD2E",
      watermark: "rgba(255, 255, 255, 0.42)",
      shadow: "rgba(0, 0, 0, 0.35)",
    },
    type: lightType,
    chrome: lightChrome,
  },
  "japan-scatter": {
    id: "japan-scatter",
    name: "Japan scatter",
    background: {
      mode: "scatter",
      scrim: "rgba(247, 244, 238, 0.72)",
      scatterCount: 5,
    },
    colors: {
      page: "#EFE8DC",
      surface: "#FFFdf8",
      border: "#E4D8C4",
      text: "#1A1714",
      muted: "#6E655C",
      tertiary: "#8A8076",
      badgeBg: "#FFE7A8",
      badgeText: "#8A5A00",
      watermark: "rgba(40, 30, 16, 0.4)",
      shadow: "rgba(70, 50, 20, 0.12)",
    },
    type: lightType,
    chrome: lightChrome,
  },
  "japan-wash": {
    id: "japan-wash",
    name: "Japan wash",
    background: {
      mode: "wash",
      scrim: "rgba(247, 244, 238, 0.62)",
      scatterCount: 0,
    },
    colors: {
      page: "#EFE8DC",
      surface: "#FFFdf8",
      border: "#E4D8C4",
      text: "#1A1714",
      muted: "#6E655C",
      tertiary: "#8A8076",
      badgeBg: "#FFE7A8",
      badgeText: "#8A5A00",
      watermark: "rgba(40, 30, 16, 0.4)",
      shadow: "rgba(70, 50, 20, 0.12)",
    },
    type: lightType,
    chrome: lightChrome,
  },
};

export const RECIPE_LIST: SlideRecipe[] = Object.values(SLIDE_RECIPES);

export function recipeById(id: string): SlideRecipe {
  if (id in SLIDE_RECIPES) return SLIDE_RECIPES[id as RecipeId];
  return SLIDE_RECIPES["studio-light"];
}

export function defaultRecipeId(photoCount: number): RecipeId {
  return photoCount > 0 ? "japan-scatter" : "studio-light";
}
