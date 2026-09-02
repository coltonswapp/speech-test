import NextAuth from "next-auth";
import type { NextAuthOptions } from "next-auth";
import GoogleProvider from "next-auth/providers/google";
import {
  authSecret,
  googleClientId,
  googleClientSecret,
  isEmailAllowed,
} from "@/lib/studio-auth";

export const authOptions: NextAuthOptions = {
  secret: authSecret() || undefined,
  providers: googleClientId()
    ? [
        GoogleProvider({
          clientId: googleClientId(),
          clientSecret: googleClientSecret(),
        }),
      ]
    : [],
  pages: {
    signIn: "/login",
    error: "/login",
  },
  callbacks: {
    async signIn({ user }) {
      return isEmailAllowed(user.email);
    },
  },
};

const handler = NextAuth(authOptions);

export { handler as GET, handler as POST };
