# Studio auth

Published iOS JSON (`/api/public/*`) stays open. Everything else is gated when any of Google, `STUDIO_AGENT_TOKEN`, or `APP_PASSPHRASE` is set.

## Humans (Google)

1. Google Cloud Console → OAuth client (Web).
2. Authorized redirect URIs:
   - `http://localhost:3000/api/auth/callback/google`
   - `https://shizen-studio.vercel.app/api/auth/callback/google`
3. Vercel env:
   - `NEXTAUTH_URL=https://shizen-studio.vercel.app`
   - `NEXTAUTH_SECRET` (random 32+ chars)
   - `GOOGLE_CLIENT_ID`
   - `GOOGLE_CLIENT_SECRET`
   - `STUDIO_ALLOWED_EMAILS` (comma-separated, e.g. `coltonbswapp@gmail.com`)

Off-list Google accounts get AccessDenied.

## Agents / MCP

Set `STUDIO_AGENT_TOKEN` on Vercel and in the Studio MCP env. Requests send `Authorization: Bearer …`.

## Local

Leave those unset (or `STUDIO_AUTH_BYPASS=1` in non-production) so localhost MCP keeps working. `APP_PASSPHRASE` remains a fallback login if you still have it on production.
