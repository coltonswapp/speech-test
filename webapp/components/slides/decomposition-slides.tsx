import { displayBadgeMeaning, findKanji } from "@/lib/slides/catalog";
import { annotatedReadings, readingLine } from "@/lib/slides/romaji";
import type {
  DecompositionCharacter,
  DecompositionPayload,
  SlideRecipe,
} from "@/lib/slides/types";
import {
  CharacterHero,
  HeroCard,
  SlideContent,
  SlideShell,
  Watermark,
} from "./slide-chrome";

export function DecompositionIntroSlide({
  payload,
  recipe,
  width,
  height,
}: {
  payload: DecompositionPayload;
  recipe: SlideRecipe;
  width: number;
  height: number;
}) {
  return (
    <SlideShell recipe={recipe} width={width} height={height}>
      <Watermark recipe={recipe} placement="bottom" />
      <SlideContent>
        <div
          style={{
            fontSize: 13,
            fontWeight: 600,
            color: recipe.colors.muted,
            marginBottom: 12,
          }}
        >
          {payload.partLabel}
        </div>
        <div
          style={{
            fontSize: 20,
            fontWeight: 600,
            textAlign: "center",
            marginBottom: 48,
            maxWidth: 280,
          }}
        >
          Do you know the meaning of this kanji?
        </div>
        <WordHero recipe={recipe} expression={payload.expression} reading={payload.reading} />
      </SlideContent>
    </SlideShell>
  );
}

export function DecompositionCharacterSlide({
  payload,
  character,
  recipe,
  width,
  height,
}: {
  payload: DecompositionPayload;
  character: DecompositionCharacter;
  recipe: SlideRecipe;
  width: number;
  height: number;
}) {
  const meaning = displayBadgeMeaning(character.meanings, character.badgeMeanings);
  const on = annotatedReadings(character.onReadings);
  const kun = annotatedReadings(character.kunReadings);
  const compounds = (findKanji(character.character)?.compounds ?? [])
    .filter((row) => row.expression !== payload.expression)
    .slice(0, 3);
  return (
    <SlideShell recipe={recipe} width={width} height={height}>
      <Watermark recipe={recipe} placement="bottom" />
      <SlideContent>
        <CharacterHero
          recipe={recipe}
          character={character.character}
          meaning={meaning}
          width={recipe.chrome.heroWidth}
          glyphSize={64}
        />
        <div style={{ width: "100%", marginTop: 20 }}>
          <MutedLabel recipe={recipe}>Readings</MutedLabel>
          <div style={{ display: "flex", justifyContent: "center", gap: 18, marginTop: 6 }}>
            <Reading recipe={recipe} title="On" value={on || "—"} />
            <Reading recipe={recipe} title="Kun" value={kun || "—"} />
          </div>
        </div>
        {compounds.length > 0 ? (
          <div style={{ width: "100%", marginTop: 18 }}>
            <MutedLabel recipe={recipe}>Compounds</MutedLabel>
            <div style={{ marginTop: 8, display: "flex", flexDirection: "column", gap: 6 }}>
              {compounds.map((row) => (
                <div
                  key={row.expression}
                  style={{
                    display: "flex",
                    justifyContent: "space-between",
                    gap: 12,
                    fontSize: 14,
                  }}
                >
                  <span style={{ fontWeight: 600 }}>
                    {row.expression}
                    {row.reading ? (
                      <span style={{ color: recipe.colors.muted, fontWeight: 500 }}>
                        {" "}
                        {readingLine(row.reading)}
                      </span>
                    ) : null}
                  </span>
                  <span style={{ color: recipe.colors.muted, textAlign: "right" }}>
                    {row.gloss}
                  </span>
                </div>
              ))}
            </div>
          </div>
        ) : null}
      </SlideContent>
    </SlideShell>
  );
}

export function DecompositionTeaserSlide({
  payload,
  recipe,
  width,
  height,
}: {
  payload: DecompositionPayload;
  recipe: SlideRecipe;
  width: number;
  height: number;
}) {
  return (
    <SlideShell recipe={recipe} width={width} height={height}>
      <Watermark recipe={recipe} placement="bottom" />
      <SlideContent>
        <PreviewRow payload={payload} recipe={recipe} />
        <div
          style={{
            fontSize: 42,
            fontWeight: 600,
            color: recipe.colors.muted,
            margin: "28px 0",
          }}
        >
          ?
        </div>
        <WordHero recipe={recipe} expression={payload.expression} />
      </SlideContent>
    </SlideShell>
  );
}

export function DecompositionRevealSlide({
  payload,
  recipe,
  width,
  height,
}: {
  payload: DecompositionPayload;
  recipe: SlideRecipe;
  width: number;
  height: number;
}) {
  const meaning = payload.definitionOverride?.trim() || payload.gloss;
  return (
    <SlideShell recipe={recipe} width={width} height={height}>
      <Watermark recipe={recipe} placement="bottom" />
      <SlideContent>
        <PreviewRow payload={payload} recipe={recipe} />
        <div style={{ height: 28 }} />
        <WordHero recipe={recipe} expression={payload.expression} reading={payload.reading} />
        <div
          style={{
            marginTop: 28,
            fontSize: 22,
            fontWeight: 600,
            textAlign: "center",
            maxWidth: 280,
          }}
        >
          {meaning}
        </div>
      </SlideContent>
    </SlideShell>
  );
}

function PreviewRow({
  payload,
  recipe,
}: {
  payload: DecompositionPayload;
  recipe: SlideRecipe;
}) {
  const compact = payload.characters.length > 2;
  return (
    <div style={{ display: "flex", gap: compact ? 8 : 12, alignItems: "flex-end" }}>
      {payload.characters.map((character, index) => (
        <div key={`${character.character}-${index}`}>
          <CharacterHero
            recipe={recipe}
            character={character.character}
            meaning={displayBadgeMeaning(character.meanings, character.badgeMeanings)}
            width={compact ? 72 : 88}
            glyphSize={compact ? 36 : 44}
          />
        </div>
      ))}
    </div>
  );
}

function WordHero({
  recipe,
  expression,
  reading,
}: {
  recipe: SlideRecipe;
  expression: string;
  reading?: string;
}) {
  return (
    <HeroCard
      recipe={recipe}
      width={recipe.chrome.exampleHeroWidth}
      style={{ minHeight: recipe.chrome.exampleHeroWidth, padding: 16 }}
    >
      <div style={{ textAlign: "center" }}>
        <div
          style={{
            fontFamily: recipe.type.heroFont,
            fontSize: recipe.type.japaneseSize,
            fontWeight: 700,
          }}
        >
          {expression}
        </div>
        {reading ? (
          <div
            style={{
              marginTop: 8,
              fontSize: 13,
              color: recipe.colors.muted,
              fontWeight: 500,
            }}
          >
            {readingLine(reading)}
          </div>
        ) : null}
      </div>
    </HeroCard>
  );
}

function MutedLabel({
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
        textTransform: "uppercase",
        letterSpacing: 0.4,
        textAlign: "center",
      }}
    >
      {children}
    </div>
  );
}

function Reading({
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
      <div style={{ fontSize: 13, fontWeight: 500 }}>{value}</div>
    </div>
  );
}
