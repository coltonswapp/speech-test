/**
 * Grant or remove the `staff` custom claim on a Firebase user.
 *
 *   npx tsx scripts/set-staff-claim.ts you@example.com
 *   npx tsx scripts/set-staff-claim.ts you@example.com --remove
 *   npx tsx scripts/set-staff-claim.ts --list
 *
 * Credentials: Application Default Credentials for project shizen-b453f
 * (`gcloud auth application-default login`), or GOOGLE_APPLICATION_CREDENTIALS.
 *
 * Staff accounts see `model` and `usage` in gateway responses, can read /v1/usage*, and can send Studio QA notes/check-offs
 * from Release builds. The app picks up the claim on its next ID-token refresh
 * (within an hour, or sign out and back in).
 */
import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";

const projectId = process.env.FIREBASE_PROJECT_ID?.trim() || "shizen-b453f";
initializeApp({ projectId });
const auth = getAuth();

async function list(): Promise<void> {
  let pageToken: string | undefined;
  do {
    const page = await auth.listUsers(1000, pageToken);
    for (const user of page.users) {
      if (user.customClaims?.staff === true) console.log(`${user.email ?? "(no email)"}  ${user.uid}`);
    }
    pageToken = page.pageToken;
  } while (pageToken);
}

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  if (args[0] === "--list") return list();

  const email = args.find((a) => !a.startsWith("--"));
  if (!email) {
    console.error("usage: set-staff-claim.ts <email> [--remove] | --list");
    process.exit(1);
  }
  const remove = args.includes("--remove");
  const user = await auth.getUserByEmail(email);
  const claims = { ...(user.customClaims ?? {}) };
  if (remove) delete claims.staff;
  else claims.staff = true;
  await auth.setCustomUserClaims(user.uid, claims);
  console.log(`${remove ? "Removed" : "Granted"} staff for ${email} (${user.uid}). Claims: ${JSON.stringify(claims)}`);
}

main().catch((err) => {
  console.error(err instanceof Error ? err.message : err);
  process.exit(1);
});
