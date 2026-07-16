# Published R2 bucket setup

The webapp uses **two** Cloudflare R2 buckets:

| Bucket | Env var | Access |
|--------|---------|--------|
| Studio (existing) | `R2_BUCKET_NAME` | Private — TTS variants, WAVs, studio exports |
| Published (new) | `R2_PUBLISHED_BUCKET_NAME` | Public via custom domain — finalized `.m4a` for Shizen |

## One-time Cloudflare steps

1. Create a new R2 bucket (e.g. `shizen-published`).
2. Ensure your domain is a zone in the same Cloudflare account.
3. Open the new bucket → **Settings → Custom Domains → Connect Domain**.
4. Enter a subdomain such as `cdn.yourdomain.com` and confirm the DNS record.
5. Verify an object is reachable at `https://cdn.yourdomain.com/<key>` after publishing from the studio.

Prefer a custom domain over `*.r2.dev` for production (caching, WAF, branding).

## Webapp env vars

Add to `.env.local` / deployment:

```env
R2_PUBLISHED_BUCKET_NAME=shizen-published
R2_PUBLISHED_PUBLIC_BASE_URL=https://cdn.yourdomain.com
```

The same `R2_ENDPOINT`, `R2_ACCESS_KEY_ID`, and `R2_SECRET_ACCESS_KEY` used for the studio bucket can write to both buckets if the token has access to both.

## Object layout

Published dialogue audio:

```
dialogue/{collectionId}/{scenarioSlug}/{contentHash}.m4a
```

Only objects written by the **Publish** action in Content Studio appear here. Draft WAVs stay in the private studio bucket.
