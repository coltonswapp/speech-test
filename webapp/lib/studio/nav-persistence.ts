/**
 * Studio navigation persistence (localStorage).
 * Mirrors scenario-editor collapsed-sections: survive Review ↔ editor ↔ Curriculum.
 */

const CURRICULUM_EXPANDED_KEY = "studio:curriculum:expanded";
const CURRICULUM_JLPT_KEY = "studio:curriculum:jlpt";
const REVIEW_EXPANDED_KEY = "studio:review-queue:expanded";
const REVIEW_DISMISSED_KEY = "studio:review-queue:dismissed";

function readJson<T>(key: string, fallback: T): T {
  if (typeof window === "undefined") return fallback;
  try {
    const raw = window.localStorage.getItem(key);
    if (!raw) return fallback;
    return JSON.parse(raw) as T;
  } catch {
    return fallback;
  }
}

function writeJson(key: string, value: unknown) {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.setItem(key, JSON.stringify(value));
  } catch {
    // private mode / quota — keep in-memory only
  }
}

export function readCurriculumExpanded(): Set<string> {
  const parsed = readJson<unknown>(CURRICULUM_EXPANDED_KEY, []);
  if (!Array.isArray(parsed)) return new Set();
  return new Set(parsed.filter((id): id is string => typeof id === "string"));
}

export function writeCurriculumExpanded(expanded: Set<string>) {
  writeJson(CURRICULUM_EXPANDED_KEY, [...expanded]);
}

/** Last Curriculum JLPT track (5/4/3). Used when `/content/curriculum` has no `?jlpt=`. */
export function readCurriculumJlpt(): 5 | 4 | 3 | null {
  const n = Number(readJson<unknown>(CURRICULUM_JLPT_KEY, null));
  if (n === 5 || n === 4 || n === 3) return n;
  return null;
}

export function writeCurriculumJlpt(level: 5 | 4 | 3) {
  writeJson(CURRICULUM_JLPT_KEY, level);
}

export function readReviewExpanded(): Set<string> | null {
  const parsed = readJson<unknown>(REVIEW_EXPANDED_KEY, null);
  if (!Array.isArray(parsed)) return null;
  return new Set(parsed.filter((id): id is string => typeof id === "string"));
}

export function writeReviewExpanded(expanded: Set<string>) {
  writeJson(REVIEW_EXPANDED_KEY, [...expanded]);
}

/** Soft-dismissed review takes: variantId → ISO timestamp. */
export type ReviewDismissals = Record<string, string>;

export function readReviewDismissals(): ReviewDismissals {
  const parsed = readJson<unknown>(REVIEW_DISMISSED_KEY, {});
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return {};
  const out: ReviewDismissals = {};
  for (const [id, at] of Object.entries(parsed as Record<string, unknown>)) {
    if (typeof id === "string" && typeof at === "string") out[id] = at;
  }
  return out;
}

export function writeReviewDismissals(dismissals: ReviewDismissals) {
  writeJson(REVIEW_DISMISSED_KEY, dismissals);
}

export function dismissReviewTake(
  variantId: string,
  dismissals: ReviewDismissals = readReviewDismissals(),
): ReviewDismissals {
  const next = { ...dismissals, [variantId]: new Date().toISOString() };
  writeReviewDismissals(next);
  return next;
}

export function undismissReviewTake(
  variantId: string,
  dismissals: ReviewDismissals = readReviewDismissals(),
): ReviewDismissals {
  const next = { ...dismissals };
  delete next[variantId];
  writeReviewDismissals(next);
  return next;
}
