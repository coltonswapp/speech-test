import { formatApiError } from "@/lib/api-error";

export type PointSummary = {
  id: string;
  orderIndex: number;
  title: string;
  headlineEnglish: string;
  pattern: string | null;
  status: "draft" | "needsRevision" | "approved";
  updatedAt: string;
};

export type TeachingBlock = { title: string; body: string };
export type UsageLevel = { japanese: string; register: string };
export type UsageLadder = { label: string; levels: UsageLevel[] };
export type ScenarioLine = {
  speaker: string;
  japanese: string;
  romaji?: string;
  english?: string;
  id?: string;
  grammarPointIDs?: string[];
};
export type Scenario = { setting?: string; lines: ScenarioLine[] };
export type Example = {
  japanese: string;
  romaji?: string;
  english: string;
  targetSubstring?: string;
  audioKey?: string | null;
  scenario?: Scenario;
  sourceScenarioId?: string;
};
export type Drill = {
  kind: string;
  instruction?: string;
  prompt?: string;
  exampleJapanese?: string;
  targetSubstring?: string;
  english?: string;
  choices?: string[];
  correctChoice?: string;
  contrastLabel?: string;
  buildComponents?: string[];
};
export type ContrastDrill = {
  contrastLabel: string;
  choices: string[];
  correctChoice: string;
  ruleTargeted?: string | null;
};

export type GrammarPoint = {
  id: string;
  orderIndex: number;
  title: string;
  headlineEnglish: string;
  blurb: string | null;
  forms: string[];
  formation: TeachingBlock[];
  formationExamples: string[] | null;
  usage: TeachingBlock[] | null;
  usageLadders: UsageLadder[] | null;
  relatedPointIds: string[];
  examples: Example[];
  drills: Drill[];
  pattern: string | null;
  reading: string | null;
  shortDefinition: string | null;
  structure: string | null;
  register: "casual" | "polite" | "formal" | null;
  contrastDrills: ContrastDrill[] | null;
  status: "draft" | "needsRevision" | "approved";
  reviewNotes: string | null;
  updatedAt: string;
};

async function request<T>(url: string, init?: RequestInit): Promise<T> {
  const res = await fetch(url, {
    ...init,
    headers: { "Content-Type": "application/json", ...init?.headers },
  });
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new Error(formatApiError(body, res.status));
  }
  return res.json();
}

export type CoverageScenarioRef = {
  scenarioId: string;
  menuTitle: string;
  collectionId: string;
  collectionTitle: string;
  unitId: string | null;
  unitTitle: string | null;
  jlptLevel: number | null;
  taggedLineCount: number;
};

export type CoveragePoint = {
  id: string;
  orderIndex: number;
  title: string;
  pattern: string | null;
  headlineEnglish: string;
  status: "draft" | "needsRevision" | "approved";
  coverage: CoverageScenarioRef[];
};

export type CoverageReport = {
  points: CoveragePoint[];
  totals: {
    pointCount: number;
    coveredCount: number;
    uncoveredCount: number;
    scenarioCount: number;
  };
  unknownTags: Array<{ tag: string; scenarioIds: string[] }>;
};


export type TeachingPatternRow = {
  id: string;
  form: string;
  gloss: string;
  jlptBand: number;
  category: string;
  status: string;
  notes: string | null;
  orderIndex: number;
  updatedAt: string;
  linkedScenarioCount: number;
};

export type TeachingPatternList = {
  patterns: TeachingPatternRow[];
};

export type TeachingPatternImportResult = {
  inserted: number;
  skipped: number;
  total: number;
};

export const contentApi = {
  getCoverage: () => request<CoverageReport>("/api/content/coverage"),
  listPoints: (params?: { status?: string; search?: string }) => {
    const qs = new URLSearchParams();
    if (params?.status) qs.set("status", params.status);
    if (params?.search) qs.set("search", params.search);
    const query = qs.toString();
    return request<{ points: PointSummary[] }>(
      `/api/content/points${query ? `?${query}` : ""}`
    );
  },
  getPoint: (id: string) =>
    request<{ point: GrammarPoint }>(`/api/content/points/${id}`),
  updatePoint: (id: string, body: Partial<GrammarPoint>) =>
    request<{ point: GrammarPoint }>(`/api/content/points/${id}`, {
      method: "PATCH",
      body: JSON.stringify(body),
    }),
  setStatus: (
    id: string,
    status: "draft" | "needsRevision" | "approved",
    reviewNotes?: string | null
  ) =>
    request<{ point: GrammarPoint }>(`/api/content/points/${id}/status`, {
      method: "POST",
      body: JSON.stringify({ status, reviewNotes }),
    }),
  generatePoint: (body: {
    pointID: string;
    title: string;
    headlineEnglish?: string;
    orderIndex: number;
  }) =>
    request<{ point: GrammarPoint; validationIssues: string[]; attemptCount: number }>(
      "/api/content/points/generate",
      { method: "POST", body: JSON.stringify(body) }
    ),
  regenerateSection: (
    id: string,
    body: {
      task: "overview" | "formation" | "usage" | "usageLadders" | "example" | "drills";
      customInstructions?: string;
    }
  ) =>
    request<{ point: GrammarPoint }>(
      `/api/content/points/${id}/regenerate-section`,
      { method: "POST", body: JSON.stringify(body) }
    ),
  listPatterns: () =>
    request<TeachingPatternList>("/api/content/patterns"),
  importPatterns: () =>
    request<TeachingPatternImportResult>("/api/content/patterns/import", {
      method: "POST",
    }),
};
