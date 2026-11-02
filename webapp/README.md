This is a [Next.js](https://nextjs.org) project bootstrapped with [`create-next-app`](https://nextjs.org/docs/app/api-reference/cli/create-next-app).

## Getting Started

First, run the development server:

```bash
npm run dev
# or
yarn dev
# or
pnpm dev
# or
bun dev
```

Open [http://localhost:3000](http://localhost:3000) with your browser to see the result.

You can start editing the page by modifying `app/page.tsx`. The page auto-updates as you edit the file.

This project uses [`next/font`](https://nextjs.org/docs/app/building-your-application/optimizing/fonts) to automatically optimize and load [Geist](https://vercel.com/font), a new font family for Vercel.

## Gemini models

- **Text** (dialogue generation and revision, grammar generation):
  `GEMINI_TEXT_MODEL`, default `gemini-3.5-flash-lite`, thinking level `low`.
- **Tokenize + readings**: `GEMINI_TOKENIZE_MODEL`, default `gemini-3.8-flash`
  (provisional), thinking level `low`. The prompt and thinking level live in
  `lib/dialogue/tokenize-prompt.ts`; results are cached per line text.
- **TTS**: chosen in Settings → Voices (3.8 Flash TTS by default, or 3.8
  Flash-Lite TTS).

Gemini 3+ ignores `temperature`/`topP`/`topK` and rejects `candidateCount`, so
requests send only `thinkingConfig.thinkingLevel` (adapted per model in
`lib/gemini/text-model.ts`). Published per-1M-token rates, including the
2027-01-01 rate changes, live in `lib/gemini/models.ts`. See `.env.example`.

## Learn More

To learn more about Next.js, take a look at the following resources:

- [Next.js Documentation](https://nextjs.org/docs) - learn about Next.js features and API.
- [Learn Next.js](https://nextjs.org/learn) - an interactive Next.js tutorial.

You can check out [the Next.js GitHub repository](https://github.com/vercel/next.js) - your feedback and contributions are welcome!

## Deploy on Vercel

The easiest way to deploy your Next.js app is to use the [Vercel Platform](https://vercel.com/new?utm_medium=default-template&filter=next.js&utm_source=create-next-app&utm_campaign=create-next-app-readme) from the creators of Next.js.

Check out our [Next.js deployment documentation](https://nextjs.org/docs/app/building-your-application/deploying) for more details.
