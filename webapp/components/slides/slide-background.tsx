"use client";

import type { CSSProperties } from "react";
import type { PoolPhoto } from "@/lib/slides/scatter";
import { pickWashPhoto, scatterForSlide } from "@/lib/slides/scatter";
import type { SlideRecipe } from "@/lib/slides/types";

export function SlideBackground({
  recipe,
  photos,
  seed,
  slideIndex,
}: {
  recipe: SlideRecipe;
  photos: PoolPhoto[];
  seed: number;
  slideIndex: number;
}) {
  const mode =
    photos.length === 0 && recipe.background.mode !== "solid"
      ? "solid"
      : recipe.background.mode;

  if (mode === "wash") {
    const photo = pickWashPhoto(photos, seed, slideIndex);
    return (
      <div style={layerStyle}>
        {photo ? <CoverPhoto url={photo.url} /> : null}
        <Scrim color={recipe.background.scrim} />
      </div>
    );
  }

  if (mode === "scatter") {
    const wash = pickWashPhoto(photos, seed, slideIndex);
    const pieces =
      photos.length <= 1
        ? []
        : scatterForSlide({
            photos,
            seed,
            slideIndex,
            count: recipe.background.scatterCount,
          });
    return (
      <div style={layerStyle}>
        {wash ? <CoverPhoto url={wash.url} /> : null}
        {pieces.map((piece) => (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            key={`${piece.photoId}-${piece.z}`}
            src={piece.url}
            alt=""
            style={{
              position: "absolute",
              left: `${piece.x}%`,
              top: `${piece.y}%`,
              width: `${piece.width}%`,
              height: `${piece.height}%`,
              transform: `rotate(${piece.rotate}deg)`,
              transformOrigin: "center center",
              objectFit: "cover",
              borderRadius: 6,
              boxShadow: "0 2px 10px rgba(0,0,0,0.18)",
              zIndex: piece.z + 1,
            }}
          />
        ))}
        <Scrim color={recipe.background.scrim} />
      </div>
    );
  }

  return <div style={layerStyle} />;
}

function CoverPhoto({ url }: { url: string }) {
  return (
    // eslint-disable-next-line @next/next/no-img-element
    <img
      src={url}
      alt=""
      style={{
        position: "absolute",
        inset: 0,
        width: "100%",
        height: "100%",
        objectFit: "cover",
        objectPosition: "center",
      }}
    />
  );
}

function Scrim({ color }: { color: string }) {
  return (
    <div
      style={{
        position: "absolute",
        inset: 0,
        background: color,
        zIndex: 20,
      }}
    />
  );
}

const layerStyle: CSSProperties = {
  position: "absolute",
  inset: 0,
  overflow: "hidden",
};
