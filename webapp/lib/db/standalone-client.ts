// Plain Drizzle client for use in standalone scripts (migrations, seeds) run
// outside the Next.js runtime — lib/db/client.ts imports "server-only",
// which throws when required from a plain Node process via tsx.
import { drizzle } from "drizzle-orm/postgres-js";
import postgres from "postgres";
import * as schema from "./schema";

const connectionString = process.env.DATABASE_URL;
if (!connectionString) {
  throw new Error("DATABASE_URL is not set");
}

const queryClient = postgres(connectionString);
export const db = drizzle(queryClient, { schema });

let ended = false;

/** Close the postgres-js pool so standalone scripts can exit. */
export async function closeStandaloneDb(): Promise<void> {
  if (ended) return;
  ended = true;
  await queryClient.end({ timeout: 5 });
}
