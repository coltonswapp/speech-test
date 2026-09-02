import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { GoogleSignInButton } from "@/components/google-sign-in-button";
import { isGoogleAuthConfigured } from "@/lib/studio-auth";
import { getAppPassphrase } from "@/lib/secrets";

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ next?: string; error?: string }>;
}) {
  const { next, error } = await searchParams;
  const google = isGoogleAuthConfigured();
  const passphraseEnabled = Boolean(getAppPassphrase());
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
                : error === "1"
                  ? "Incorrect passphrase."
                  : "Couldn’t sign in."}
            </p>
          )}
          {google && <GoogleSignInButton next={dest} />}
          {google && passphraseEnabled && (
            <p className="text-center text-xs text-muted-foreground">or</p>
          )}
          {passphraseEnabled && (
            <form action="/api/login" method="POST" className="flex flex-col gap-4">
              <input type="hidden" name="next" value={dest} />
              <div className="flex flex-col gap-2">
                <Label htmlFor="passphrase">Passphrase</Label>
                <Input
                  id="passphrase"
                  name="passphrase"
                  type="password"
                  autoFocus={!google}
                  required
                />
              </div>
              <Button type="submit" className="w-full" variant={google ? "outline" : "default"}>
                Continue
              </Button>
            </form>
          )}
          {!google && !passphraseEnabled && (
            <p className="text-sm text-muted-foreground">
              Auth isn’t configured. Set Google or APP_PASSPHRASE, or leave them unset for local.
            </p>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
