"use client";

import { signIn } from "next-auth/react";
import { Button } from "@/components/ui/button";

export function GoogleSignInButton({ next }: { next: string }) {
  return (
    <Button
      type="button"
      className="w-full"
      onClick={() => signIn("google", { callbackUrl: next || "/" })}
    >
      Continue with Google
    </Button>
  );
}
