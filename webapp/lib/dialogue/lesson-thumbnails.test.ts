import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  buildLessonThumbnailItems,
  hasDownloadableThumbnails,
  slugifyFilenamePart,
  thumbnailCaption,
  thumbnailFilenameBase,
} from "./lesson-thumbnails";

function scene(
  extras: Partial<{
    id: string;
    collectionId: string;
    orderIndex: number;
    menuTitle: string;
    thumbnailUrl: string | null;
    thumbnailSmallUrl: string | null;
  }> = {}
) {
  return {
    id: "campus-club/lost-outside",
    collectionId: "campus-club",
    orderIndex: 0,
    menuTitle: "Lost Outside the Lecture Hall",
    thumbnailUrl: "https://cdn.example.com/scene-1.webp",
    thumbnailSmallUrl: "https://cdn.example.com/scene-1-512.webp",
    ...extras,
  };
}

describe("slugifyFilenamePart", () => {
  it("kebabs titles and strips punctuation", () => {
    assert.equal(
      slugifyFilenamePart("Lost Outside the Lecture Hall"),
      "lost-outside-the-lecture-hall"
    );
    assert.equal(slugifyFilenamePart("  Hello, World!  "), "hello-world");
  });

  it("falls back when nothing remains", () => {
    assert.equal(slugifyFilenamePart("講義"), "untitled");
    assert.equal(slugifyFilenamePart(""), "untitled");
  });
});

describe("thumbnailCaption", () => {
  it("matches the iOS Scene N · Title format", () => {
    assert.equal(
      thumbnailCaption({
        kind: "scene",
        sceneNumber: 1,
        title: "Lost Outside the Lecture Hall",
      }),
      "Scene 1 \u00b7 Lost Outside the Lecture Hall"
    );
    assert.equal(
      thumbnailCaption({
        kind: "lesson",
        sceneNumber: null,
        title: "Campus Club",
      }),
      "Lesson \u00b7 Campus Club"
    );
  });
});

describe("thumbnailFilenameBase", () => {
  it("uses lesson slug, scene number, and title", () => {
    assert.equal(
      thumbnailFilenameBase({
        collectionId: "campus-club",
        kind: "scene",
        sceneNumber: 1,
        title: "Lost Outside the Lecture Hall",
        slug: "lost-outside",
      }),
      "campus-club-01-lost-outside-the-lecture-hall"
    );
    assert.equal(
      thumbnailFilenameBase({
        collectionId: "campus-club",
        kind: "lesson",
        sceneNumber: null,
        title: "Campus Club",
      }),
      "campus-club-lesson-campus-club"
    );
  });

  it("falls back to the scenario slug when the title is not latin", () => {
    assert.equal(
      thumbnailFilenameBase({
        collectionId: "campus-club",
        kind: "scene",
        sceneNumber: 2,
        title: "迷子",
        slug: "lost-outside",
      }),
      "campus-club-02-lost-outside"
    );
  });
});

describe("buildLessonThumbnailItems", () => {
  it("puts the lesson card first, then every scene in order", () => {
    const items = buildLessonThumbnailItems({
      collectionId: "campus-club",
      lessonTitle: "Campus Club",
      lessonThumbnailUrl: "https://cdn.example.com/lesson.webp",
      lessonThumbnailSmallUrl: "https://cdn.example.com/lesson-512.webp",
      scenarios: [
        scene({
          id: "campus-club/cafe",
          orderIndex: 2,
          menuTitle: "Cafe Chat",
          thumbnailUrl: null,
          thumbnailSmallUrl: null,
        }),
        scene({ orderIndex: 0 }),
        scene({
          id: "campus-club/no-art",
          orderIndex: 1,
          menuTitle: "No Art Yet",
          thumbnailUrl: null,
          thumbnailSmallUrl: null,
        }),
      ],
    });

    assert.equal(items.length, 4);
    assert.equal(items[0]?.id, "lesson");
    assert.equal(items[0]?.caption, "Lesson \u00b7 Campus Club");
    assert.equal(items[1]?.sceneNumber, 1);
    assert.equal(items[1]?.caption, "Scene 1 \u00b7 Lost Outside the Lecture Hall");
    assert.equal(items[1]?.inherited, false);
    assert.equal(items[2]?.id, "campus-club/no-art");
    assert.equal(items[2]?.inherited, true);
    assert.equal(items[2]?.thumbnailUrl, "https://cdn.example.com/lesson.webp");
    assert.equal(items[3]?.id, "campus-club/cafe");
    assert.equal(items[3]?.sceneNumber, 3);
    assert.equal(items[3]?.inherited, true);
  });

  it("skips the lesson card when the lesson has no thumbnail", () => {
    const items = buildLessonThumbnailItems({
      collectionId: "campus-club",
      lessonTitle: "Campus Club",
      lessonThumbnailUrl: null,
      lessonThumbnailSmallUrl: null,
      scenarios: [
        scene({ thumbnailUrl: null, thumbnailSmallUrl: null }),
      ],
    });
    assert.equal(items.length, 1);
    assert.equal(items[0]?.kind, "scene");
    assert.equal(items[0]?.thumbnailUrl, null);
    assert.equal(items[0]?.inherited, false);
    assert.equal(hasDownloadableThumbnails(items), false);
  });

  it("keeps scene placeholders so the viewer filmstrip stays complete", () => {
    const items = buildLessonThumbnailItems({
      collectionId: "campus-club",
      lessonTitle: "Campus Club",
      lessonThumbnailUrl: "https://cdn.example.com/lesson.webp",
      lessonThumbnailSmallUrl: null,
      scenarios: [scene({ thumbnailUrl: null, thumbnailSmallUrl: null })],
    });
    assert.equal(items[1]?.thumbnailUrl, "https://cdn.example.com/lesson.webp");
    assert.equal(items[1]?.thumbnailSmallUrl, "https://cdn.example.com/lesson.webp");
    assert.equal(hasDownloadableThumbnails(items), true);
  });
});
