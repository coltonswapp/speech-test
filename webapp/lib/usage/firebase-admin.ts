import "server-only";

import { cert, getApps, initializeApp, type App } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

/**
 * Server-only Firebase Admin for Studio Usage reads.
 *
 * Required env (Vercel / local — never expose these to the browser):
 * - `FIREBASE_PROJECT_ID` — e.g. `shizen-b453f`
 *
 * Credentials (one of):
 * - Application Default Credentials (Cloud Run / GCE / `gcloud auth
 *   application-default login`), optionally via `GOOGLE_APPLICATION_CREDENTIALS`
 * - `FIREBASE_SERVICE_ACCOUNT_JSON` — full service-account JSON string
 * - `FIREBASE_CLIENT_EMAIL` + `FIREBASE_PRIVATE_KEY` — split fields
 *   (`FIREBASE_PRIVATE_KEY` may contain escaped `\n`)
 *
 * The service account only needs Firestore **read** on `llmUsage/**`,
 * `llmFeedbackStats/**`, and `llmFeedback/**` (vote docs for the Usage
 * feedback browser). Configure IAM for the Studio service account. Do not
 * grant or rely on client SDK access — security rules deny the iOS app for
 * these collections.
 */

const DEFAULT_PROJECT_ID = "shizen-b453f";

export type FirebaseAdminStatus =
  | { ok: true; projectId: string; credentialSource: string }
  | { ok: false; reason: string };

function projectId(): string {
  return (
    process.env.FIREBASE_PROJECT_ID?.trim() ||
    process.env.GCLOUD_PROJECT?.trim() ||
    process.env.GOOGLE_CLOUD_PROJECT?.trim() ||
    DEFAULT_PROJECT_ID
  );
}

function parseServiceAccountJson(): {
  projectId?: string;
  clientEmail: string;
  privateKey: string;
} | null {
  const raw = process.env.FIREBASE_SERVICE_ACCOUNT_JSON?.trim();
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw) as {
      project_id?: string;
      client_email?: string;
      private_key?: string;
    };
    if (!parsed.client_email || !parsed.private_key) return null;
    return {
      projectId: parsed.project_id,
      clientEmail: parsed.client_email,
      privateKey: parsed.private_key,
    };
  } catch {
    return null;
  }
}

function splitCredential(): {
  clientEmail: string;
  privateKey: string;
} | null {
  const clientEmail = process.env.FIREBASE_CLIENT_EMAIL?.trim();
  const privateKeyRaw = process.env.FIREBASE_PRIVATE_KEY?.trim();
  if (!clientEmail || !privateKeyRaw) return null;
  return {
    clientEmail,
    privateKey: privateKeyRaw.replace(/\\n/g, "\n"),
  };
}

export function getFirebaseAdminStatus(): FirebaseAdminStatus {
  const id = projectId();
  if (parseServiceAccountJson()) {
    return { ok: true, projectId: id, credentialSource: "FIREBASE_SERVICE_ACCOUNT_JSON" };
  }
  if (splitCredential()) {
    return {
      ok: true,
      projectId: id,
      credentialSource: "FIREBASE_CLIENT_EMAIL+FIREBASE_PRIVATE_KEY",
    };
  }
  if (process.env.GOOGLE_APPLICATION_CREDENTIALS?.trim()) {
    return {
      ok: true,
      projectId: id,
      credentialSource: "GOOGLE_APPLICATION_CREDENTIALS",
    };
  }
  // ADC may still work in GCP without an env path; we only know at first read.
  if (
    process.env.K_SERVICE ||
    process.env.FUNCTION_TARGET ||
    process.env.GCE_METADATA_HOST
  ) {
    return { ok: true, projectId: id, credentialSource: "ADC (GCP runtime)" };
  }
  return {
    ok: false,
    reason:
      "No Firebase credentials found. Set FIREBASE_SERVICE_ACCOUNT_JSON, or FIREBASE_CLIENT_EMAIL + FIREBASE_PRIVATE_KEY, or GOOGLE_APPLICATION_CREDENTIALS / ADC.",
  };
}

function getAdminApp(): App {
  const existing = getApps()[0];
  if (existing) return existing;

  const id = projectId();
  const jsonCred = parseServiceAccountJson();
  if (jsonCred) {
    return initializeApp({
      credential: cert({
        projectId: jsonCred.projectId ?? id,
        clientEmail: jsonCred.clientEmail,
        privateKey: jsonCred.privateKey,
      }),
      projectId: jsonCred.projectId ?? id,
    });
  }

  const split = splitCredential();
  if (split) {
    return initializeApp({
      credential: cert({
        projectId: id,
        clientEmail: split.clientEmail,
        privateKey: split.privateKey,
      }),
      projectId: id,
    });
  }

  // Application Default Credentials (incl. GOOGLE_APPLICATION_CREDENTIALS).
  return initializeApp({ projectId: id });
}

export function getUsageFirestore() {
  return getFirestore(getAdminApp());
}
