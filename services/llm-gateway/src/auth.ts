import { getAuth } from "firebase-admin/auth";
import { createMiddleware } from "hono/factory";

import { log } from "./log.js";

/**
 * `isStaff` comes from the `staff: true` custom claim, set with
 * `scripts/set-staff-claim.ts`. Clients cannot forge it: the ID token is
 * signed by Firebase.
 */
export type AuthVariables = { uid: string; isStaff: boolean };

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
      c.set("isStaff", decoded.staff === true);
    } catch (err) {
      log("WARNING", "verifyIdToken failed", { code: (err as { code?: string }).code ?? String(err) });
      return c.json({ error: "unauthorized" }, 401);
    }

    await next();
  },
);

/** Use after requireFirebaseUser. Internal dashboards (cost, model mix). */
export const requireStaff = createMiddleware<{ Variables: AuthVariables }>(async (c, next) => {
  if (!c.get("isStaff")) {
    return c.json({ error: "forbidden" }, 403);
  }
  await next();
});
