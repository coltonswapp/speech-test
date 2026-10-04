import { formatApiError } from "@/lib/api-error";
import type {
  LessonFeedbackOverview,
  ScenarioFeedback,
} from "@/lib/lesson-feedback/types";

type ConfigFields = { configured: boolean; configError: string | null };

export type ScenarioFeedbackResponse = ConfigFields & {
  scene?: ScenarioFeedback;
};

export type LessonFeedbackOverviewResponse = ConfigFields & {
  overview?: LessonFeedbackOverview;
};

async function request<T>(params: URLSearchParams): Promise<T> {
  const res = await fetch(`/api/lesson-feedback?${params.toString()}`);
  const body = await res.json().catch(() => null);
  if (!res.ok) {
    throw new Error(formatApiError(body, res.status));
  }
  return body as T;
}

export const lessonFeedbackApi = {
  getScene(collectionId: string, scenarioId: string) {
    return request<ScenarioFeedbackResponse>(
      new URLSearchParams({ collectionId, scenarioId }),
    );
  },
  getOverview(limit = 25) {
    return request<LessonFeedbackOverviewResponse>(
      new URLSearchParams({ limit: String(limit) }),
    );
  },
};
