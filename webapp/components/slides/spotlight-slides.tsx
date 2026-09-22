import { displayBadgeMeaning } from "@/lib/slides/catalog";
import { highlightCss } from "@/lib/slides/highlights";
import { annotatedReadings, readingLine } from "@/lib/slides/romaji";
import type { SlideRecipe, SpotlightItem, SpotlightPayload } from "@/lib/slides/types";
import {
  CharacterHero,
  HeroCard,
  SlideContent,
  SlideShell,
  Watermark,
} from "./slide-chrome";

function HighlightedExpression({
  text,
  highlight,
  color,
  fontSize,
  fontFamily,
}: {
  text: string;
  highlight: string;
  color: string;
  fontSize: number;
  fontFamily: string;
}) {
  const index = highlight ? text.indexOf(highlight) : -1;
  if (index < 0) {
    return (
      <span style={{ fontFamily, fontSize, fontWeight: 700, lineHeight: 1.15 }}>
        {text}
      </span>
    );
  }
  return (
    <span style={{ fontFamily, fontSize, fontWeight: 700, lineHeight: 1.15 }}>
      {text.slice(0, index)}
      <span
        style={{
          background: color,
          borderRadius: 4,
          padding: "0 2px",
        }}
      >
        {text.slice(index, index + highlight.length)}
      </span>
      {text.slice(index + highlight.length)}
    </span>
  );
}

export function SpotlightKanjiSlide({
  payload,
  recipe,
  width,
  height,
}: {
  payload: SpotlightPayload;
  recipe: SlideRecipe;
  width: number;
  height: number;
}) {
  const meaning = displayBadgeMeaning(payload.meanings, payload.badgeMeanings);
  const on = annotatedReadings(payload.onReadings);
  const kun = annotatedReadings(payload.kunReadings);
  return (
    <SlideShell recipe={recipe} width={width} height={height}>
      <Watermark recipe={recipe} placement="top" />
      <SlideContent padding="40px 28px">
        <div
          style={{
            fontSize: recipe.type.titleSize,
            fontWeight: recipe.type.titleWeight,
            textAlign: "center",
            marginBottom: 22,
          }}
        >
          {payload.introTitle}
        </div>
        <CharacterHero
          recipe={recipe}
          character={payload.character}
          meaning={meaning}
          width={recipe.chrome.subjectHeroWidth}
          glyphSize={recipe.type.heroSize}
        />
        <div style={{ width: "100%", marginTop: 18 }}>
          <SectionLabel recipe={recipe}>Readings</SectionLabel>
          <div
            style={{
              display: "flex",
              gap: 16,
              justifyContent: "center",
              marginTop: 8,
            }}
          >
            <ReadingGroup recipe={recipe} title="On" value={on || "—"} />
            <ReadingGroup recipe={recipe} title="Kun" value={kun || "—"} />
          </div>
        </div>
        <div
          style={{
            marginTop: 16,
            color: recipe.colors.muted,
            fontSize: 14,
            fontWeight: 500,
          }}
        >
          swipe to see compounds →
        </div>
      </SlideContent>
    </SlideShell>
  );
}

export function SpotlightEntrySlide({
  payload,
  item,
  exampleNumber,
  exampleCount,
  recipe,
  width,
  height,
}: {
  payload: SpotlightPayload;
  item: SpotlightItem;
  exampleNumber: number;
  exampleCount: number;
  recipe: SlideRecipe;
  width: number;
  height: number;
}) {
  const reading = item.reading ? readingLine(item.reading) : "";
  return (
    <SlideShell recipe={recipe} width={width} height={height}>
      <Watermark recipe={recipe} placement="top" />
      <SlideContent>
        <div
          style={{
            fontSize: recipe.type.titleSize,
            fontWeight: 600,
            color: recipe.colors.muted,
            marginBottom: 32,
          }}
        >
          Example {exampleNumber}/{exampleCount}
        </div>
        <HeroCard
          recipe={recipe}
          width={recipe.chrome.exampleHeroWidth}
          style={{ minHeight: recipe.chrome.exampleHeroWidth, padding: 16 }}
        >
          <div style={{ textAlign: "center" }}>
            <HighlightedExpression
              text={item.expression}
              highlight={payload.character}
              color={highlightCss(payload.highlightColor)}
              fontSize={recipe.type.japaneseSize}
              fontFamily={recipe.type.heroFont}
            />
            {reading ? (
              <div
                style={{
                  marginTop: 10,
                  fontSize: 13,
                  color: recipe.colors.muted,
                  fontWeight: 500,
                }}
              >
                {reading}
              </div>
            ) : null}
          </div>
        </HeroCard>
        <div
          style={{
            marginTop: 32,
            fontSize: 22,
            fontWeight: 600,
            textAlign: "center",
            maxWidth: "100%",
          }}
        >
          {item.gloss}
        </div>
      </SlideContent>
    </SlideShell>
  );
}

function SectionLabel({
  recipe,
  children,
}: {
  recipe: SlideRecipe;
  children: string;
}) {
  return (
    <div
      style={{
        fontSize: 11,
        fontWeight: 600,
        color: recipe.colors.tertiary,
        letterSpacing: 0.4,
        textTransform: "uppercase",
        textAlign: "center",
      }}
    >
      {children}
    </div>
  );
}

function ReadingGroup({
  recipe,
  title,
  value,
}: {
  recipe: SlideRecipe;
  title: string;
  value: string;
}) {
  return (
    <div style={{ textAlign: "center", minWidth: 90 }}>
      <div
        style={{
          fontSize: 10,
          fontWeight: 600,
          color: recipe.colors.tertiary,
          marginBottom: 2,
        }}
      >
        {title}
      </div>
      <div style={{ fontSize: 13, fontWeight: 500, lineHeight: 1.35 }}>
        {value}
      </div>
    </div>
  );
}
