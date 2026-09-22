"use client";

import { useEffect, useRef, type ReactNode } from "react";
import { SlideBackground } from "./slide-background";
import {
  DecompositionCharacterSlide,
  DecompositionIntroSlide,
  DecompositionRevealSlide,
  DecompositionTeaserSlide,
} from "./decomposition-slides";
import { SpotlightEntrySlide, SpotlightKanjiSlide } from "./spotlight-slides";
import type { PoolPhoto } from "@/lib/slides/scatter";
import { recipeById } from "@/lib/slides/recipes";
import { EXPORT_SIZES } from "@/lib/slides/sizes";
import type { RenderSlide } from "@/lib/slides/render-slides";
import type {
  DeckKind,
  DeckPayload,
  DecompositionPayload,
  ExportSizeId,
  RecipeId,
  SpotlightPayload,
} from "@/lib/slides/types";

export function SlideFrame({
  kind,
  payload,
  slide,
  recipeId,
  exportSize,
  photos,
  seed,
  slideIndex,
  captureRef,
}: {
  kind: DeckKind;
  payload: DeckPayload;
  slide: RenderSlide;
  recipeId: RecipeId;
  exportSize: ExportSizeId;
  photos: PoolPhoto[];
  seed: number;
  slideIndex: number;
  captureRef?: (node: HTMLDivElement | null) => void;
}) {
  const recipe = recipeById(recipeId);
  const canvas = EXPORT_SIZES[exportSize];
  return (
    <div
      ref={captureRef}
      data-slide-capture=""
      style={{
        width: canvas.width,
        height: canvas.height,
        position: "relative",
        overflow: "hidden",
        background: recipe.colors.page,
      }}
    >
      <SlideBackground
        recipe={recipe}
        photos={photos}
        seed={seed}
        slideIndex={slideIndex}
      />
      <div style={{ position: "relative", zIndex: 30 }}>
        <SlideBody
          kind={kind}
          payload={payload}
          slide={slide}
          recipeId={recipeId}
          width={canvas.width}
          height={canvas.height}
        />
      </div>
    </div>
  );
}

function SlideBody({
  kind,
  payload,
  slide,
  recipeId,
  width,
  height,
}: {
  kind: DeckKind;
  payload: DeckPayload;
  slide: RenderSlide;
  recipeId: RecipeId;
  width: number;
  height: number;
}) {
  const recipe = recipeById(recipeId);
  if (kind === "spotlight") {
    const spotlight = payload as SpotlightPayload;
    if (slide.key === "spotlight-kanji") {
      return (
        <SpotlightKanjiSlide
          payload={spotlight}
          recipe={recipe}
          width={width}
          height={height}
        />
      );
    }
    if (slide.key === "spotlight-entry") {
      const item = spotlight.items[slide.itemIndex];
      if (!item) return null;
      return (
        <SpotlightEntrySlide
          payload={spotlight}
          item={item}
          exampleNumber={slide.itemIndex + 1}
          exampleCount={spotlight.items.length}
          recipe={recipe}
          width={width}
          height={height}
        />
      );
    }
  }
  const word = payload as DecompositionPayload;
  if (slide.key === "decomp-intro") {
    return (
      <DecompositionIntroSlide
        payload={word}
        recipe={recipe}
        width={width}
        height={height}
      />
    );
  }
  if (slide.key === "decomp-character") {
    const character = word.characters[slide.charIndex];
    if (!character) return null;
    return (
      <DecompositionCharacterSlide
        payload={word}
        character={character}
        recipe={recipe}
        width={width}
        height={height}
      />
    );
  }
  if (slide.key === "decomp-teaser") {
    return (
      <DecompositionTeaserSlide
        payload={word}
        recipe={recipe}
        width={width}
        height={height}
      />
    );
  }
  if (slide.key === "decomp-reveal") {
    return (
      <DecompositionRevealSlide
        payload={word}
        recipe={recipe}
        width={width}
        height={height}
      />
    );
  }
  return null;
}

export function SlideViewfinder({
  children,
  canvasWidth,
  canvasHeight,
}: {
  children: ReactNode;
  canvasWidth: number;
  canvasHeight: number;
}) {
  const hostRef = useRef<HTMLDivElement>(null);
  const innerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const host = hostRef.current;
    const inner = innerRef.current;
    if (!host || !inner) return;
    const update = () => {
      const maxW = host.clientWidth;
      const maxH = Math.min(window.innerHeight * 0.72, 760);
      const scale = Math.min(maxW / canvasWidth, maxH / canvasHeight, 1.35);
      inner.style.transform = `scale(${scale})`;
      host.style.height = `${canvasHeight * scale}px`;
    };
    update();
    const observer = new ResizeObserver(update);
    observer.observe(host);
    window.addEventListener("resize", update);
    return () => {
      observer.disconnect();
      window.removeEventListener("resize", update);
    };
  }, [canvasWidth, canvasHeight]);

  return (
    <div
      ref={hostRef}
      className="flex w-full items-start justify-center overflow-hidden rounded-xl bg-neutral-800/80 p-4"
    >
      <div
        ref={innerRef}
        style={{
          width: canvasWidth,
          height: canvasHeight,
          transformOrigin: "top center",
          boxShadow: "0 12px 40px rgba(0,0,0,0.35)",
        }}
      >
        {children}
      </div>
    </div>
  );
}
