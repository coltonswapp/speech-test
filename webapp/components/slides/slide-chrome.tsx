import type { CSSProperties, ReactNode } from "react";
import type { SlideRecipe } from "@/lib/slides/types";

export function Watermark({
  recipe,
  placement = "top",
}: {
  recipe: SlideRecipe;
  placement?: "top" | "bottom";
}) {
  return (
    <div
      style={{
        position: "absolute",
        left: 0,
        right: 0,
        top: placement === "top" ? 16 : undefined,
        bottom: placement === "bottom" ? 14 : undefined,
        textAlign: "center",
        fontFamily: recipe.type.uiFont,
        fontSize: recipe.type.watermarkSize,
        fontWeight: 500,
        color: recipe.colors.watermark,
        letterSpacing: 0.2,
        zIndex: 40,
      }}
    >
      {recipe.chrome.watermark}
    </div>
  );
}

export function HeroCard({
  recipe,
  width,
  children,
  style,
}: {
  recipe: SlideRecipe;
  width: number;
  children: ReactNode;
  style?: CSSProperties;
}) {
  return (
    <div
      style={{
        width,
        minHeight: width,
        borderRadius: recipe.chrome.cornerRadius,
        background: recipe.colors.surface,
        border: `${recipe.chrome.cardBorderWidth}px solid ${recipe.colors.border}`,
        boxShadow: `0 1px 4px ${recipe.colors.shadow}`,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        position: "relative",
        ...style,
      }}
    >
      {children}
    </div>
  );
}

export function MeaningBadge({
  recipe,
  text,
  compact = false,
}: {
  recipe: SlideRecipe;
  text: string;
  compact?: boolean;
}) {
  return (
    <div
      style={{
        maxWidth: compact ? 96 : 120,
        padding: compact ? "5px 10px" : "6px 12px",
        borderRadius: compact ? 8 : 10,
        background: recipe.colors.badgeBg,
        color: recipe.colors.badgeText,
        fontFamily: recipe.type.uiFont,
        fontSize: compact ? 11 : 13,
        fontWeight: 600,
        lineHeight: 1.2,
        textAlign: "center",
      }}
    >
      {text}
    </div>
  );
}

export function CharacterHero({
  recipe,
  character,
  meaning,
  width,
  glyphSize,
}: {
  recipe: SlideRecipe;
  character: string;
  meaning: string;
  width: number;
  glyphSize: number;
}) {
  const trailing = recipe.chrome.badgePlacement === "trailingEdgeCentered";
  return (
    <div
      style={{
        width,
        position: "relative",
        paddingBottom: 18,
      }}
    >
      <HeroCard recipe={recipe} width={width} style={{ minHeight: width }}>
        <span
          style={{
            fontFamily: recipe.type.heroFont,
            fontSize: glyphSize,
            fontWeight: 700,
            color: recipe.colors.text,
            lineHeight: 1,
          }}
        >
          {character}
        </span>
      </HeroCard>
      <div
        style={{
          position: "absolute",
          left: trailing ? undefined : "50%",
          right: trailing ? -14 : undefined,
          transform: trailing ? undefined : "translateX(-50%)",
          bottom: 0,
        }}
      >
        <MeaningBadge recipe={recipe} text={meaning} />
      </div>
    </div>
  );
}

export function SlideContent({
  children,
  padding = "40px 24px",
}: {
  children: ReactNode;
  padding?: string;
}) {
  return (
    <div
      style={{
        position: "absolute",
        inset: 0,
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        padding,
        boxSizing: "border-box",
      }}
    >
      {children}
    </div>
  );
}

export function SlideShell({
  recipe,
  children,
  width,
  height,
}: {
  recipe: SlideRecipe;
  children: ReactNode;
  width: number;
  height: number;
}) {
  return (
    <div
      style={{
        width,
        height,
        position: "relative",
        overflow: "hidden",
        background: "transparent",
        color: recipe.colors.text,
        fontFamily: recipe.type.uiFont,
      }}
    >
      {children}
    </div>
  );
}
