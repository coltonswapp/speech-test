// Shared ambience-bed helpers. Keep this file free of Node-only imports so
// Studio client components can use the same gain/offset math as publish.

export const AMBIENCE_KINDS = [
  "street",
  "city",
  "crowd",
  "ocean",
  "cafe",
  "station",
  "other",
] as const;

export type AmbienceKind = (typeof AMBIENCE_KINDS)[number];

export const MAX_AMBIENCE_KIND_LENGTH = 40;

export const AMBIENCE_KIND_LABELS: Record<AmbienceKind, string> = {
  street: "Street",
  city: "City",
  crowd: "Crowd",
  ocean: "Ocean",
  cafe: "Cafe",
  station: "Station",
  other: "Other",
};

export const DEFAULT_AMBIENCE_GAIN_DB = -22;
export const MIN_AMBIENCE_GAIN_DB = -36;
export const MAX_AMBIENCE_GAIN_DB = -6;
export const AMBIENCE_FADE_SECONDS = 0.4;
export const AMBIENCE_OFFSET_STEP_SECONDS = 2;
export const AMBIENCE_DUCK = true;
export const MAX_AMBIENCE_LAYERS = 6;
export const MIN_AMBIENCE_WINDOW_SECONDS = 0.4;

export type AmbienceLayer = {
  id: string;
  assetId: string;
  gainDb: number;
  offsetSeconds: number;
  startSeconds: number;
  endSeconds: number | null;
};

/** Pause the take waveform so mix preview is not doubled. */
export const STUDIO_PAUSE_TAKE_AUDIO = "studio:pause-take-audio";
/** Waveform started playing — stop the separate mix preview. */
export const STUDIO_STOP_AMBIENCE_PREVIEW = "studio:stop-ambience-preview";
/** Space / transport should play the encoded mix, not the dry take. */
export const STUDIO_TOGGLE_MARRIED_MIX = "studio:toggle-married-mix";
/** Restart the encoded mix from the top. */
export const STUDIO_RESTART_MARRIED_MIX = "studio:restart-married-mix";

export function isAmbienceKind(value: string): value is AmbienceKind {
  return (AMBIENCE_KINDS as readonly string[]).includes(value);
}

/** Slug used in the DB / grouping. Presets stay as-is; custom types kebab-case. */
export function normalizeAmbienceKind(value: string): string {
  const slug = value
    .trim()
    .toLowerCase()
    .replace(/['’]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, MAX_AMBIENCE_KIND_LENGTH)
    .replace(/-+$/g, "");
  return slug || "other";
}

export function ambienceKindLabel(kind: string): string {
  if (isAmbienceKind(kind)) return AMBIENCE_KIND_LABELS[kind];
  const trimmed = kind.trim();
  if (!trimmed) return AMBIENCE_KIND_LABELS.other;
  return trimmed
    .split(/[-_\s]+/)
    .filter(Boolean)
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(" ");
}

export function groupAmbienceAssets<T extends { kind: string }>(
  assets: T[]
): Array<{ kind: string; label: string; assets: T[] }> {
  const extras = [
    ...new Set(
      assets.map((asset) => asset.kind).filter((kind) => !isAmbienceKind(kind))
    ),
  ].sort((a, b) => ambienceKindLabel(a).localeCompare(ambienceKindLabel(b)));
  return [...AMBIENCE_KINDS, ...extras]
    .map((kind) => ({
      kind,
      label: ambienceKindLabel(kind),
      assets: assets.filter((asset) => asset.kind === kind),
    }))
    .filter((group) => group.assets.length > 0);
}

export function formatAmbienceSeconds(seconds: number): string {
  if (!Number.isFinite(seconds) || seconds < 0) return "0s";
  if (seconds < 10) return `${seconds.toFixed(1)}s`;
  return `${Math.round(seconds)}s`;
}

export function clampAmbienceGainDb(gainDb: number): number {
  if (!Number.isFinite(gainDb)) return DEFAULT_AMBIENCE_GAIN_DB;
  return Math.min(MAX_AMBIENCE_GAIN_DB, Math.max(MIN_AMBIENCE_GAIN_DB, gainDb));
}

export function wrapAmbienceOffset(
  offsetSeconds: number,
  durationSeconds: number
): number {
  if (!Number.isFinite(offsetSeconds) || offsetSeconds === 0) return 0;
  if (!Number.isFinite(durationSeconds) || durationSeconds <= 0) {
    return Math.max(0, offsetSeconds);
  }
  const wrapped = offsetSeconds % durationSeconds;
  return wrapped < 0 ? wrapped + durationSeconds : wrapped;
}

export function randomAmbienceOffset(durationSeconds: number): number {
  if (!Number.isFinite(durationSeconds) || durationSeconds <= 0) return 0;
  return Math.random() * durationSeconds;
}

export function gainDbToLinear(gainDb: number): number {
  const db = clampAmbienceGainDb(gainDb);
  return 10 ** (db / 20);
}

export function clampAmbienceWindow(
  startSeconds: number,
  endSeconds: number | null,
  takeDuration: number
): { startSeconds: number; endSeconds: number | null } {
  const take = Math.max(0.05, takeDuration);
  const start = Math.min(Math.max(0, startSeconds || 0), Math.max(0, take - MIN_AMBIENCE_WINDOW_SECONDS));
  if (endSeconds == null || !Number.isFinite(endSeconds)) {
    return { startSeconds: start, endSeconds: null };
  }
  const end = Math.min(take, Math.max(start + MIN_AMBIENCE_WINDOW_SECONDS, endSeconds));
  return { startSeconds: start, endSeconds: end >= take - 0.02 ? null : end };
}

export function normalizeAmbienceLayer(
  raw: Partial<AmbienceLayer> & { assetId: string },
  takeDuration = 0
): AmbienceLayer {
  const window = clampAmbienceWindow(
    raw.startSeconds ?? 0,
    raw.endSeconds ?? null,
    takeDuration || Number.POSITIVE_INFINITY
  );
  return {
    id: raw.id && raw.id.trim() ? raw.id : "legacy",
    assetId: raw.assetId,
    gainDb: clampAmbienceGainDb(raw.gainDb ?? DEFAULT_AMBIENCE_GAIN_DB),
    offsetSeconds: Number.isFinite(raw.offsetSeconds) ? Math.max(0, raw.offsetSeconds ?? 0) : 0,
    startSeconds: window.startSeconds,
    endSeconds: window.endSeconds,
  };
}

export function normalizeAmbienceLayers(
  raw: unknown,
  takeDuration = 0
): AmbienceLayer[] {
  if (!Array.isArray(raw)) return [];
  const layers: AmbienceLayer[] = [];
  for (const item of raw) {
    if (!item || typeof item !== "object") continue;
    const assetId = (item as { assetId?: unknown }).assetId;
    if (typeof assetId !== "string" || !assetId) continue;
    layers.push(normalizeAmbienceLayer({ ...(item as AmbienceLayer), assetId }, takeDuration));
    if (layers.length >= MAX_AMBIENCE_LAYERS) break;
  }
  return layers;
}

export function layersFromScenario(scenario: {
  ambienceAssetId?: string | null;
  ambienceGainDb?: number | null;
  ambienceOffsetSeconds?: number | null;
  ambienceLayers?: unknown;
}): AmbienceLayer[] {
  const fromJson = normalizeAmbienceLayers(scenario.ambienceLayers);
  if (fromJson.length > 0) return fromJson;
  if (!scenario.ambienceAssetId) return [];
  return [
    normalizeAmbienceLayer({
      id: "legacy",
      assetId: scenario.ambienceAssetId,
      gainDb: scenario.ambienceGainDb ?? DEFAULT_AMBIENCE_GAIN_DB,
      offsetSeconds: scenario.ambienceOffsetSeconds ?? 0,
      startSeconds: 0,
      endSeconds: null,
    }),
  ];
}

export function createAmbienceLayer(params: {
  assetId: string;
  bedDuration: number;
  takeDuration?: number;
  playheadSeconds?: number;
  full?: boolean;
}): AmbienceLayer {
  const take = params.takeDuration ?? 0;
  const playhead = Math.max(0, params.playheadSeconds ?? 0);
  if (params.full || take <= 0) {
    return normalizeAmbienceLayer({
      id: crypto.randomUUID(),
      assetId: params.assetId,
      gainDb: DEFAULT_AMBIENCE_GAIN_DB,
      offsetSeconds: randomAmbienceOffset(params.bedDuration),
      startSeconds: 0,
      endSeconds: null,
    });
  }
  const start = Math.min(playhead, Math.max(0, take - MIN_AMBIENCE_WINDOW_SECONDS));
  const end = Math.min(take, start + Math.min(6, take));
  return normalizeAmbienceLayer(
    {
      id: crypto.randomUUID(),
      assetId: params.assetId,
      gainDb: DEFAULT_AMBIENCE_GAIN_DB,
      offsetSeconds: randomAmbienceOffset(params.bedDuration),
      startSeconds: start,
      endSeconds: end >= take - 0.02 ? null : end,
    },
    take
  );
}

/** Canonical string hashed into the published object key / stale check. */
export function ambienceMixKeyParts(params: {
  assetId: string;
  gainDb: number;
  offsetSeconds: number;
  startSeconds?: number;
  endSeconds?: number | null;
}): string {
  const end =
    params.endSeconds == null || !Number.isFinite(params.endSeconds)
      ? ""
      : params.endSeconds.toFixed(3);
  return [
    params.assetId,
    clampAmbienceGainDb(params.gainDb).toFixed(2),
    params.offsetSeconds.toFixed(3),
    (params.startSeconds ?? 0).toFixed(3),
    end,
  ].join("|");
}

export function ambienceLayersMixKeyParts(layers: AmbienceLayer[]): string {
  return layers
    .map((layer) =>
      ambienceMixKeyParts({
        assetId: layer.assetId,
        gainDb: layer.gainDb,
        offsetSeconds: layer.offsetSeconds,
        startSeconds: layer.startSeconds,
        endSeconds: layer.endSeconds,
      })
    )
    .join(";");
}

export function ambienceMixFilterComplex(opts: {
  durationSeconds: number;
  gainDb?: number;
  offsetSeconds?: number;
  fadeSeconds?: number;
  duck?: boolean;
  layers?: Array<{
    gainDb: number;
    offsetSeconds: number;
    startSeconds?: number;
    endSeconds?: number | null;
  }>;
}): string {
  const duration = Math.max(0.05, opts.durationSeconds);
  const duck = opts.duck ?? AMBIENCE_DUCK;
  const fadeDefault = opts.fadeSeconds ?? AMBIENCE_FADE_SECONDS;
  const layers =
    opts.layers && opts.layers.length > 0
      ? opts.layers
      : [
          {
            gainDb: opts.gainDb ?? DEFAULT_AMBIENCE_GAIN_DB,
            offsetSeconds: opts.offsetSeconds ?? 0,
            startSeconds: 0,
            endSeconds: null,
          },
        ];

  const fullSpan =
    layers.length === 1 &&
    (layers[0].startSeconds ?? 0) <= 0.001 &&
    layers[0].endSeconds == null;

  if (fullSpan) {
    const layer = layers[0];
    const fadeCap = Math.min(fadeDefault, duration / 2);
    const fadeOutStart = Math.max(0, duration - fadeCap);
    const offset = Math.max(0, layer.offsetSeconds);
    const volume = gainDbToLinear(layer.gainDb);
    const bedFilters = [
      `atrim=start=${offset}:duration=${duration}`,
      "asetpts=PTS-STARTPTS",
      "aformat=sample_fmts=fltp:channel_layouts=mono",
      `volume=${volume}`,
    ];
    if (fadeCap > 0) {
      bedFilters.push(`afade=t=in:st=0:d=${fadeCap}`);
      bedFilters.push(`afade=t=out:st=${fadeOutStart}:d=${fadeCap}`);
    }
    const bed = `[1:a]${bedFilters.join(",")}[bed]`;
    const speechFmt = "[0:a]aformat=sample_fmts=fltp:channel_layouts=mono";
    const mix =
      "amix=inputs=2:duration=first:dropout_transition=0:normalize=0[out]";
    if (!duck) {
      return `${bed};${speechFmt}[speech];[speech][bed]${mix}`;
    }
    return `${bed};${speechFmt},asplit=2[speech][sc];[bed][sc]sidechaincompress=threshold=0.04:ratio=6:attack=40:release=280:level_sc=1[ducked];[speech][ducked]${mix}`;
  }

  const bedLabels: string[] = [];
  const bedGraphs = layers.map((layer, index) => {
    const input = index + 1;
    const label = `b${index}`;
    bedLabels.push(`[${label}]`);
    const window = clampAmbienceWindow(
      layer.startSeconds ?? 0,
      layer.endSeconds ?? null,
      duration
    );
    const end = window.endSeconds ?? duration;
    const windowDur = Math.max(MIN_AMBIENCE_WINDOW_SECONDS, end - window.startSeconds);
    const fadeCap = Math.min(fadeDefault, windowDur / 2);
    const fadeOutStart = Math.max(0, windowDur - fadeCap);
    const delayMs = Math.round(window.startSeconds * 1000);
    const filters = [
      `atrim=start=${Math.max(0, layer.offsetSeconds)}:duration=${windowDur.toFixed(4)}`,
      "asetpts=PTS-STARTPTS",
      "aformat=sample_fmts=fltp:channel_layouts=mono",
      `volume=${gainDbToLinear(layer.gainDb)}`,
    ];
    if (fadeCap > 0) {
      filters.push(`afade=t=in:st=0:d=${fadeCap.toFixed(4)}`);
      filters.push(`afade=t=out:st=${fadeOutStart.toFixed(4)}:d=${fadeCap.toFixed(4)}`);
    }
    if (delayMs > 0) {
      filters.push(`adelay=${delayMs}:all=1`);
    }
    filters.push(`apad=whole_dur=${duration.toFixed(4)}`);
    return `[${input}:a]${filters.join(",")}[${label}]`;
  });

  const beds =
    layers.length === 1
      ? `${bedGraphs[0].replace("[b0]", "[beds]")}`
      : `${bedGraphs.join(";")};${bedLabels.join("")}amix=inputs=${layers.length}:duration=first:dropout_transition=0:normalize=0[beds]`;
  const speechFmt = "[0:a]aformat=sample_fmts=fltp:channel_layouts=mono";
  const mix =
    "amix=inputs=2:duration=first:dropout_transition=0:normalize=0[out]";
  if (!duck) {
    return `${beds};${speechFmt}[speech];[speech][beds]${mix}`;
  }
  return `${beds};${speechFmt},asplit=2[speech][sc];[beds][sc]sidechaincompress=threshold=0.04:ratio=6:attack=40:release=280:level_sc=1[ducked];[speech][ducked]${mix}`;
}
