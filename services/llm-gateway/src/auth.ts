import { getAuth } from "firebase-admin/auth";
import { createMiddleware } from "hono/factory";

import { log } from "./log.js";

export type AuthVariables = { uid: string };

export const requireFirebaseUser = createMiddleware<{ Variables: AuthVariables }>(
  async (c, next) => {
    const header = c.req.header("Authorization") ?? "";
    const match = /^Bearer\s+(.+)$/i.exec(header);
    if (!match) {
      return c.json({ error: "unauthorized" }, 401);
    }

    try {
      const decoded = await getAuth().verifyIdToken(match[1].trim());
      if (decoded.firebase?.sign_in_provider === "anonymous") {
        return c.json({ error: "unauthorized" }, 401);
      }
      c.set("uid", decoded.uid);
    } catch (err) {
      log("WARNING", "verifyIdToken failed", { code: (err as { code?: string }).code ?? String(err) });
      return c.json({ error: "unauthorized" }, 401);
    }

    await next();
  },
);
