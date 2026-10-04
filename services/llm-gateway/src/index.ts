import { serve } from "@hono/node-server";
import { initializeApp } from "firebase-admin/app";
import { Hono, type Context } from "hono";
import { bodyLimit } from "hono/body-limit";

import { requireFirebaseUser, type AuthVariables } from "./auth.js";
import { FEATURE_NAMES, featureNamed, modelFor } from "./features/index.js";
import { FeedbackError, newRequestId, recordFeedback } from "./feedback.js";
import { feedbackExpiry, requireFeedbackHmacKey, retentionDays, signFeedbackToken } from "./feedback-token.js";
import { createGeminiClient, UpstreamError } from "./gemini.js";
import { recordLessonFeedback } from "./lesson-feedback.js";
import { log, userHash } from "./log.js";
import { featuresRanked, isUsagePeriod, readUsage, recordUsage } from "./usage.js";
import { InputError, isObject, type Body } from "./validate.js";

function requireEnv(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) {
    console.error(`Missing required env var ${name}`);
    process.exit(1);
  }
  return value;
}

const firebaseProjectId = requireEnv("FIREBASE_PROJECT_ID");
const gemini = createGeminiClient(requireEnv("GEMINI_API_KEY"));
const feedbackHmacKey = requireFeedbackHmacKey();
const feedbackRetentionDays = retentionDays();
const port = Number(process.env.PORT) || 8080;

initializeApp({ projectId: firebaseProjectId });

type Env = { Variables: AuthVariables };
const app = new Hono<Env>();

app.get("/health", (c) => c.json({ ok: true }));

async function generate(c: Context<Env>) {
  let body: Body;
  try {
    const parsed: unknown = await c.req.json();
    if (!isObject(parsed)) throw new Error("not an object");
    body = parsed;
  } catch {
    return c.json({ error: "invalid_json" }, 400);
  }

  const featureName = body.feature;
  const feature = featureNamed(featureName);
  if (!feature || typeof featureName !== "string") {
    return c.json({ error: "unknown_feature" }, 400);
  }

  let input: unknown;
  try {
    input = feature.parseInput(body);
  } catch (err) {
    if (err instanceof InputError) {
      return c.json({ error: "invalid_request", detail: err.message }, 400);
    }
    throw err;
  }

  const model = modelFor(featureName);
  const logContext = { feature: featureName, user: userHash(c.get("uid")), model, request: input };
  const startedAt = Date.now();

  let json: string;
  let usage;
  try {
    ({ json, usage } = await gemini.generateJSON(model, feature.build(input)));
  } catch (err) {
    if (err instanceof UpstreamError) {
      log("ERROR", "llm upstream error", {
        ...logContext,
        latencyMs: Date.now() - startedAt,
        error: err.message,
        cause: err.cause instanceof Error ? err.cause.message : err.cause ? String(err.cause) : undefined,
      });
      return c.json({ error: "upstream_error" }, 502);
    }
    throw err;
  }

  let result;
  try {
    result = feature.parseResult(json, input);
  } catch (err) {
    log("ERROR", "llm bad model output", {
      ...logContext,
      latencyMs: Date.now() - startedAt,
      error: (err as Error).message,
      rawOutput: json.slice(0, 1000),
    });
    return c.json({ error: "upstream_error" }, 502);
  }

  const requestId = newRequestId();
  const uid = c.get("uid");
  const feedbackToken = signFeedbackToken(feedbackHmacKey, {
    uid,
    exp: feedbackExpiry(),
    requestId,
    feature: featureName,
    model,
    input,
    result,
  });

  log("INFO", "llm ok", {
    ...logContext,
    requestId,
    latencyMs: Date.now() - startedAt,
    tokens: usage.totalTokenCount,
    result,
  });
  recordUsage(uid, featureName, model, usage);
  return c.json({ feature: featureName, requestId, feedbackToken, result, model, usage });
}

const generateMiddleware = [
  requireFirebaseUser,
  bodyLimit({
    maxSize: 32 * 1024,
    onError: (c) => c.json({ error: "invalid_request", detail: "body too large" }, 413),
  }),
] as const;

app.post("/v1/generate", ...generateMiddleware, generate);
// First Common Uses builds call /v1/gloss; same handler.
app.post("/v1/gloss", ...generateMiddleware, generate);

const feedbackMiddleware = [
  requireFirebaseUser,
  bodyLimit({
    maxSize: 64 * 1024,
    onError: (c) => c.json({ error: "invalid_request", detail: "body too large" }, 413),
  }),
] as const;

app.post("/v1/feedback", ...feedbackMiddleware, async (c) => {
  let body: unknown;
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: "invalid_json" }, 400);
  }
  try {
    await recordFeedback(c.get("uid"), body, feedbackHmacKey, feedbackRetentionDays);
    return c.json({ ok: true });
  } catch (err) {
    if (err instanceof FeedbackError) {
      return c.json({ error: err.code, detail: err.detail }, err.status);
    }
    throw err;
  }
});

/** 1–5 ratings for a finished dialogue scene. Not tied to a generate call. */
app.post("/v1/lesson-feedback", ...feedbackMiddleware, async (c) => {
  let body: unknown;
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: "invalid_json" }, 400);
  }
  try {
    await recordLessonFeedback(c.get("uid"), body, feedbackRetentionDays);
    return c.json({ ok: true });
  } catch (err) {
    if (err instanceof FeedbackError) {
      return c.json({ error: err.code, detail: err.detail }, err.status);
    }
    throw err;
  }
});

/** Signed-in user's rollup for the current UTC day / ISO week / month. */
app.get("/v1/usage", requireFirebaseUser, async (c) => {
  const period = c.req.query("period") ?? "week";
  if (!isUsagePeriod(period)) {
    return c.json({ error: "invalid_request", detail: "period must be day, week, or month" }, 400);
  }
  return c.json(await readUsage(c.get("uid"), period));
});

/**
 * Product-wide rollup. Feature mix answers "what people find valuable";
 * estimatedCostUSD is the Gemini estimate for that window.
 */
app.get("/v1/usage/features", requireFirebaseUser, async (c) => {
  const period = c.req.query("period") ?? "week";
  if (!isUsagePeriod(period)) {
    return c.json({ error: "invalid_request", detail: "period must be day, week, or month" }, 400);
  }
  const report = await readUsage("_product", period);
  return c.json({
    period: report.period,
    periodKey: report.periodKey,
    calls: report.calls,
    promptTokens: report.promptTokens,
    outputTokens: report.outputTokens,
    estimatedCostUSD: report.estimatedCostUSD,
    hasUnpriced: report.hasUnpriced,
    features: featuresRanked(report),
  });
});

app.notFound((c) => c.json({ error: "not_found" }, 404));
app.onError((err, c) => {
  log("ERROR", "unhandled error", { error: err.message, stack: err.stack });
  return c.json({ error: "internal_error" }, 500);
});

const server = serve({ fetch: app.fetch, port }, (info) => {
  const models = FEATURE_NAMES.map((name) => `${name}=${modelFor(name)}`).join(", ");
  console.log(`shizen-llm-gateway listening on :${info.port} (${models})`);
});

process.on("SIGTERM", () => {
  server.close(() => process.exit(0));
});
