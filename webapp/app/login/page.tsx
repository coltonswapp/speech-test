import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { GoogleSignInButton } from "@/components/google-sign-in-button";
import { isGoogleAuthConfigured } from "@/lib/studio-auth";

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ next?: string; error?: string }>;
}) {
  const { next, error } = await searchParams;
  const google = isGoogleAuthConfigured();
  const dest = next && next.startsWith("/") ? next : "/";

  return (
    <div className="flex min-h-full flex-1 items-center justify-center px-6">
      <Card className="w-full max-w-sm">
        <CardHeader>
          <CardTitle>Shizen Studio</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-col gap-4">
          {error && (
            <p className="text-sm text-destructive">
              {error === "AccessDenied"
                ? "That Google account isn’t on the Studio allowlist."
                : "Couldn’t sign in."}
            </p>
          )}
          {google && <GoogleSignInButton next={dest} />}
          {!google && (
            <p className="text-sm text-muted-foreground">
              Google sign-in isn’t configured. Set GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET, and
              NEXTAUTH_SECRET, or STUDIO_AUTH_BYPASS=1 for local dev.
            </p>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
