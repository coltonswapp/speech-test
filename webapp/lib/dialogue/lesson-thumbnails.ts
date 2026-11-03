export type LessonThumbnailKind = "lesson" | "scene";

export type LessonThumbnailScenarioInput = {
  id: string;
  collectionId: string;
  orderIndex: number;
  menuTitle: string;
  thumbnailUrl: string | null;
  thumbnailSmallUrl: string | null;
};

export type LessonThumbnailItem = {
  id: string;
  kind: LessonThumbnailKind;
  /** Scenario slug; null for the lesson card. */
  slug: string | null;
  /** 1-based scene number; null for the lesson card. */
  sceneNumber: number | null;
  title: string;
  caption: string;
  /** Filename without extension, e.g. `campus-club-01-lost-outside`. */
  filenameBase: string;
  thumbnailUrl: string | null;
  thumbnailSmallUrl: string | null;
  /** Scene is showing the lesson image because it has no override. */
  inherited: boolean;
};

export function slugifyFilenamePart(input: string): string {
  const slug = input
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 60);
  return slug || "untitled";
}

export function thumbnailCaption(input: {
  kind: LessonThumbnailKind;
  sceneNumber: number | null;
  title: string;
}): string {
  if (input.kind === "lesson") {
    return `Lesson \u00b7 ${input.title}`;
  }
  return `Scene ${input.sceneNumber ?? "?"} \u00b7 ${input.title}`;
}

export function thumbnailFilenameBase(input: {
  collectionId: string;
  kind: LessonThumbnailKind;
  sceneNumber: number | null;
  title: string;
  slug?: string | null;
}): string {
  const lesson = slugifyFilenamePart(input.collectionId);
  const titlePart = slugifyFilenamePart(input.title);
  const slugPart = input.slug ? slugifyFilenamePart(input.slug) : "";
  const namePart =
    titlePart !== "untitled" ? titlePart : slugPart || "untitled";
  if (input.kind === "lesson") {
    return `${lesson}-lesson-${namePart}`;
  }
  const n = String(input.sceneNumber ?? 0).padStart(2, "0");
  return `${lesson}-${n}-${namePart}`;
}

export function buildLessonThumbnailItems(input: {
  collectionId: string;
  lessonTitle: string;
  lessonThumbnailUrl: string | null;
  lessonThumbnailSmallUrl: string | null;
  scenarios: LessonThumbnailScenarioInput[];
}): LessonThumbnailItem[] {
  const items: LessonThumbnailItem[] = [];

  if (input.lessonThumbnailUrl) {
    items.push(
      finalizeItem(
        {
          id: "lesson",
          kind: "lesson",
          slug: null,
          sceneNumber: null,
          title: input.lessonTitle,
          thumbnailUrl: input.lessonThumbnailUrl,
          thumbnailSmallUrl:
            input.lessonThumbnailSmallUrl ?? input.lessonThumbnailUrl,
          inherited: false,
        },
        input.collectionId
      )
    );
  }

  const scenarios = [...input.scenarios].sort(
    (a, b) => a.orderIndex - b.orderIndex
  );
  for (const [index, scenario] of scenarios.entries()) {
    const ownUrl = scenario.thumbnailUrl;
    const url = ownUrl ?? input.lessonThumbnailUrl;
    const smallUrl = ownUrl
      ? (scenario.thumbnailSmallUrl ?? ownUrl)
      : (input.lessonThumbnailSmallUrl ?? input.lessonThumbnailUrl);
    items.push(
      finalizeItem(
        {
          id: scenario.id,
          kind: "scene",
          slug: scenario.id.slice(scenario.collectionId.length + 1),
          sceneNumber: index + 1,
          title: scenario.menuTitle,
          thumbnailUrl: url,
          thumbnailSmallUrl: smallUrl,
          inherited: !ownUrl && !!input.lessonThumbnailUrl,
        },
        input.collectionId
      )
    );
  }

  return items;
}

export function hasDownloadableThumbnails(
  items: Array<{ thumbnailUrl: string | null }>
): boolean {
  return items.some((item) => !!item.thumbnailUrl);
}

function finalizeItem(
  item: Omit<LessonThumbnailItem, "caption" | "filenameBase">,
  collectionId: string
): LessonThumbnailItem {
  return {
    ...item,
    caption: thumbnailCaption(item),
    filenameBase: thumbnailFilenameBase({
      collectionId,
      kind: item.kind,
      sceneNumber: item.sceneNumber,
      title: item.title,
      slug: item.slug,
    }),
  };
}
