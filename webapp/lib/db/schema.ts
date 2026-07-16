import {
  boolean,
  integer,
  jsonb,
  pgTable,
  real,
  text,
  timestamp,
  uniqueIndex,
  uuid,
} from "drizzle-orm/pg-core";

// --- TTS Studio ---

export const ttsDialogueGroup = pgTable("tts_dialogue_group", {
  id: text("id").primaryKey(), // slug
  title: text("title").notNull(),
});

export const ttsProject = pgTable(
  "tts_project",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
    updatedAt: timestamp("updated_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
    promptText: text("prompt_text").notNull().default(""),
    instructions: text("instructions"),
    provider: text("provider").notNull(), // openai | elevenlabs | gemini
    voice: text("voice").notNull(),
    model: text("model").notNull(),
    selectedVariantId: uuid("selected_variant_id"),
    compositionMode: text("composition_mode").notNull().default("narration"), // narration | conversation
    speaker1Voice: text("speaker1_voice"),
    speaker2Voice: text("speaker2_voice"),
    speaker1Name: text("speaker1_name"),
    speaker2Name: text("speaker2_name"),
    trackName: text("track_name"),
    groupId: text("group_id").references(() => ttsDialogueGroup.id),
    // Scenario-backed projects read their lines from dialogue_scenario.lines
    // at generation time; tts_dialogue_line only backs ad-hoc tracks.
    sourceScenarioId: text("source_scenario_id").references(
      () => dialogueScenario.id,
      { onDelete: "cascade" }
    ),
    groupOrderIndex: integer("group_order_index"),
  },
  (t) => [
    uniqueIndex("tts_project_source_scenario_idx").on(t.sourceScenarioId),
  ]
);

export const ttsDialogueLine = pgTable("tts_dialogue_line", {
  id: uuid("id").primaryKey().defaultRandom(),
  projectId: uuid("project_id")
    .notNull()
    .references(() => ttsProject.id, { onDelete: "cascade" }),
  speaker: text("speaker").notNull(), // speaker1 | speaker2
  text: text("text").notNull(),
  orderIndex: integer("order_index").notNull(),
});

export const ttsVariant = pgTable("tts_variant", {
  id: uuid("id").primaryKey().defaultRandom(),
  projectId: uuid("project_id")
    .notNull()
    .references(() => ttsProject.id, { onDelete: "cascade" }),
  createdAt: timestamp("created_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
  audioObjectKey: text("audio_object_key").notNull(), // R2 key, WAV
  sampleRate: real("sample_rate").notNull(),
  audioByteCount: integer("audio_byte_count").notNull(),
  trimSampleLower: integer("trim_sample_lower"),
  trimSampleUpper: integer("trim_sample_upper"),
  dialogueLineSwitchSamples: integer("dialogue_line_switch_samples").array(),
  notes: text("notes"),
  rating: integer("rating"),
  isSelected: boolean("is_selected").notNull().default(false),
  voice: text("voice").notNull(),
  provider: text("provider").notNull(),
  // sha256 of the spoken content (mapped speaker + text sequence) at
  // generation time; null on takes generated before this column existed.
  contentHash: text("content_hash"),
});

export const ttsVariantSentence = pgTable("tts_variant_sentence", {
  id: uuid("id").primaryKey().defaultRandom(),
  variantId: uuid("variant_id")
    .notNull()
    .references(() => ttsVariant.id, { onDelete: "cascade" }),
  index: integer("index").notNull(),
  text: text("text").notNull(),
  sampleLower: integer("sample_lower").notNull(),
  sampleUpper: integer("sample_upper").notNull(),
  peaks: real("peaks").array(),
});

export const voicePreview = pgTable(
  "voice_preview",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
    provider: text("provider").notNull(), // openai | gemini
    voice: text("voice").notNull(),
    audioObjectKey: text("audio_object_key").notNull(), // R2 key, WAV
    sampleRate: real("sample_rate").notNull(),
  },
  (t) => [uniqueIndex("voice_preview_provider_voice_idx").on(t.provider, t.voice)]
);

export const ttsExport = pgTable("tts_export", {
  id: uuid("id").primaryKey().defaultRandom(),
  variantId: uuid("variant_id")
    .notNull()
    .references(() => ttsVariant.id, { onDelete: "cascade" }),
  createdAt: timestamp("created_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
  format: text("format").notNull(), // wav | mp3 | m4a
  objectKey: text("object_key").notNull(),
  byteCount: integer("byte_count").notNull(),
  durationSeconds: real("duration_seconds").notNull(),
  sourceByteCount: integer("source_byte_count").notNull(),
});

// --- Content Studio ---

export const grammarPoint = pgTable("grammar_point", {
  id: text("id").primaryKey(),
  orderIndex: integer("order_index").notNull(),
  title: text("title").notNull(),
  headlineEnglish: text("headline_english").notNull(),
  blurb: text("blurb"),
  forms: text("forms").array().notNull().default([]),
  formation: jsonb("formation").notNull().default([]),
  formationExamples: text("formation_examples").array(),
  usage: jsonb("usage"),
  usageLadders: jsonb("usage_ladders"),
  relatedPointIds: text("related_point_ids").array().notNull().default([]),
  examples: jsonb("examples").notNull().default([]),
  drills: jsonb("drills").notNull().default([]),
  pattern: text("pattern"),
  reading: text("reading"),
  shortDefinition: text("short_definition"),
  structure: text("structure"),
  register: text("register"), // casual | polite | formal
  contrastDrills: jsonb("contrast_drills"),
  status: text("status").notNull().default("draft"), // draft | needsRevision | approved
  reviewNotes: text("review_notes"),
  provenance: jsonb("provenance"),
  updatedAt: timestamp("updated_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
});

export const grammarCheckpoint = pgTable("grammar_checkpoint", {
  id: text("id").primaryKey(),
  orderIndex: integer("order_index").notNull(),
  title: text("title").notNull(),
  subtitle: text("subtitle"),
  pointIds: text("point_ids").array().notNull().default([]),
});

export const grammarCurriculumBundleSnapshot = pgTable(
  "grammar_curriculum_bundle_snapshot",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
    jlptLevel: integer("jlpt_level").notNull(),
    objectKey: text("object_key").notNull(), // backup JSON in R2
  }
);

export const recentPointView = pgTable("recent_point_view", {
  id: uuid("id").primaryKey().defaultRandom(),
  pointId: text("point_id")
    .notNull()
    .references(() => grammarPoint.id, { onDelete: "cascade" }),
  viewedAt: timestamp("viewed_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
});

// Shizen dialogue collections (e.g. train-station.json) — one row per
// collection plus one row per scenario. Scenario ids store the full slug
// ("train-station/buying-a-ticket") exactly as exported.
export const dialogueCollection = pgTable("dialogue_collection", {
  id: text("id").primaryKey(), // slug, immutable after create
  title: text("title").notNull(),
  subtitle: text("subtitle"),
  sceneImage: text("scene_image"), // optional bundled asset-catalog name (legacy / fallback)
  thumbnailUrl: text("thumbnail_url"), // public CDN URL for lesson card thumbnail
  orderIndex: integer("order_index").notNull().default(0),
  updatedAt: timestamp("updated_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
});

export const dialogueScenario = pgTable("dialogue_scenario", {
  id: text("id").primaryKey(), // "<collectionId>/<slug>"
  collectionId: text("collection_id")
    .notNull()
    .references(() => dialogueCollection.id, { onDelete: "cascade" }),
  orderIndex: integer("order_index").notNull(),
  menuTitle: text("menu_title").notNull(),
  menuSubtitle: text("menu_subtitle"),
  japanese: text("japanese").notNull(), // headline example
  romaji: text("romaji").notNull(),
  english: text("english").notNull(),
  targetSubstring: text("target_substring"),
  audioKey: text("audio_key"), // absent → on-device TTS fallback
  publishedAudioUrl: text("published_audio_url"),
  publishedVariantId: uuid("published_variant_id"),
  publishedContentHash: text("published_content_hash"),
  publishedAt: timestamp("published_at", { withTimezone: true }),
  grammarPointIds: text("grammar_point_ids").array().notNull().default([]),
  setting: text("setting"),
  lines: jsonb("lines").notNull().default([]),
  highlights: jsonb("highlights"),
  quiz: jsonb("quiz"),
  updatedAt: timestamp("updated_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
});

// --- Shared ---

export const appSettings = pgTable("app_settings", {
  key: text("key").primaryKey(),
  value: jsonb("value").notNull(),
});
