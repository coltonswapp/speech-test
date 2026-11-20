# Plan: send clip feedback to an agent, with tickets

Status: plan, 2026-11-20. Build on a branch off `origin/main`. `polish` is behind it and doesn't have the feedback inbox from #107/#108.

## Goal

From the Studio clip feedback inbox (`/experiments/clips/feedback`), press **Send to agent** on an open learner report. Grok Bot or OpenBot then diagnoses and fixes the clip, the way the `short-w-vcntpqxou` timing report was fixed by hand on 2026-11-19, and resolves the report.

Every dispatch creates a **ticket**. The ticket records what the agent changed: the server's own before/after snapshots of the clip and a log of every API call made under the ticket. Studio can then answer "what did the agent do to this clip?" without trusting the agent's summary.

Decisions so far:
- Both agents can be picked for each report. Each target is enabled by its own env vars, and a target without env is hidden.
- The agent may resolve the report itself. The ticket makes that reviewable, and Reopen still works.

## What the ticket holds

New table `clip_agent_ticket`. Add its DDL constant next to `CLIP_FEEDBACK_DDL`, and an idempotent `scripts/clip-agent-ticket-table.ts` modeled on `scripts/clip-feedback-table.ts` (dry run by default, `--write` to create).

| column | notes |
|---|---|
| `id` | `tkt_<random>` |
| `feedback_id` | `clip_feedback.id`. One report can have several tickets (retries, the other agent) |
| `clip_id` | |
| `agent` | `grokbot` \| `openbot` |
| `status` | `queued` → `sent` → `working` → `done` \| `failed` \| `cancelled`. `queued` means the webhook isn't sent yet; `sent` means delivered (2xx) |
| `dispatched_by` | Studio session email, or `agent-token` |
| `instructions` | optional free text the editor typed when dispatching |
| `delivery` | jsonb: HTTP status, error, attempt time |
| `run_url` | the agent's session link (Cursor run, OpenBot conversation), set by `start_ticket` |
| `before` | jsonb clip snapshot taken by the server at dispatch |
| `after` | jsonb clip snapshot taken by the server at finish |
| `events` | jsonb array: one entry per mutating API call made with this ticket (see below) |
| `outcome` | `fixed` \| `no_change_needed` \| `could_not_fix` |
| `summary` | the agent's note: cause and what it changed |
| `cost_usd` | sum of pipeline cost recorded during the ticket (from the clip's cost by step, after minus before) |
| `created_at`, `started_at`, `finished_at`, `updated_at` | |

**Snapshot shape** (`lib/clip-agent/snapshot.ts`, pure and testable): per line, `ja`, `en`, `start`/`end` (first and last token time), and its tokens with readings. Also `shiftSec`, `feedEligible`, `jlptLevel`, `deprecated`. Keep it small: no token scores or detailed timings past the line level. Skip `tokens` if the size gets out of hand.

**Diff** (`lib/clip-agent/diff.ts`, pure, unit-tested): align before and after lines by text (LCS on `ja`) and report:
- lines added or removed
- text and English changes
- reading changes
- timing moves over 0.25 s per line
- clip-level field changes

Studio renders this diff. Nothing stores it.

## Tying changes to the ticket

1. **MCP:** `studioFetch` in `webapp/studio-mcp/src/client.ts` adds `X-Agent-Ticket: <id>` when a ticket is active in the process. `start_ticket` sets it and `finish_ticket` clears it. Every existing tool (`patch_clip`, `run_clip_steps` → per-step routes) carries it automatically.
2. **Server:** a helper `recordTicketEvent(request, event)` in `lib/clip-agent/tickets.ts`.
   - If the header is present and names a ticket in `working` state for the **same clip id**, it appends `{at, route, method, clipId, fields | step, model?, ok, costUsd?}` to `events`.
   - A missing header does nothing. A wrong or closed ticket gets a `409`, so a stale agent can't keep editing after the ticket is closed.
3. Call it from:
   - `PATCH /api/experiments/clips/[id]`: record which fields were sent. For `sentences`/`english`, store counts only; the snapshot diff has the content.
   - The step routes under `clips/[id]/…`: `transcribe`, `tokenize`, `align`, `translate`, `level`, `tag`, `feed`, `video-info`.
   - `DELETE` is refused when the request carries a ticket. Agents deprecate clips instead of deleting them.
4. **Edits outside a ticket:** a human in the clip editor, or a plain MCP session without a ticket, is not logged. The before/after diff still shows the net change, so a human edit made during an open ticket appears in its diff. Label the diff "changes while the ticket was open".

## API

All routes sit behind the normal Studio gate (`proxy.ts`): a Google session or `STUDIO_AGENT_TOKEN`.

- `POST /api/experiments/clip-feedback/[id]/dispatch` `{agent, instructions?}`
  1. Requires an open report.
  2. Refuses if the report already has a `sent`/`working` ticket, unless `force`.
  3. Snapshots the clip into `before`, then inserts the ticket.
  4. Delivers the webhook (below) with an 8 s timeout and records `delivery`.
  5. Returns the ticket. The ticket is kept on delivery failure (`failed`, error shown) so it can be retried with `POST …/tickets/[id]/retry`.
- `GET /api/experiments/clip-agent-tickets?feedback_id=&clip_id=&status=`: lists tickets with a computed `diff` (only when `after` exists, or a live diff against the current clip while `working`).
- `GET /api/experiments/clip-agent-tickets/[id]`: one ticket. This is what the agent reads.
- `POST /api/experiments/clip-agent-tickets/[id]/start` `{runUrl?}`: `sent` → `working`, sets `started_at` and `run_url`. Idempotent.
- `POST /api/experiments/clip-agent-tickets/[id]/finish` `{outcome, summary}`:
  1. Snapshots `after` and computes `cost_usd`, then sets `done`, or `failed` for `could_not_fix`.
  2. For `fixed` or `no_change_needed`, also calls `setClipFeedbackStatus(feedbackId, "resolved", note)` with note `"<Agent> · tkt_… · <summary first line>"`.
  3. For `could_not_fix`, leaves the report open.
- `POST /api/experiments/clip-agent-tickets/[id]/cancel`: from Studio, while `sent`/`working`. Later calls carrying this ticket then get `409`.

## Webhook delivery (`lib/clip-agent/dispatch.ts`)

| target | env | auth |
|---|---|---|
| Grok Bot (Cursor automation) | `CLIP_AGENT_GROKBOT_WEBHOOK_URL`, `CLIP_AGENT_GROKBOT_WEBHOOK_KEY` | `Authorization: Bearer` and `X-Automation-Key`, same as `lib/dialogue/auto-stamp-review-webhook.ts` |
| OpenBot routine | `CLIP_AGENT_OPENBOT_WEBHOOK_URL`, `CLIP_AGENT_OPENBOT_WEBHOOK_SECRET` | `{type, occurredAt, data}` envelope, `X-OpenBot-Timestamp` / `X-OpenBot-Delivery-Id` / `X-OpenBot-Signature: sha256=<hex>` over `timestamp.id.body` (see CSFeedbackKit `RequestSigner.swift`). 64 KiB body cap |

`GET /api/experiments/clip-agent-tickets/targets` returns which targets are configured, so the menu hides the others.

Payload (`type: "clip-feedback.ticket"`), under 64 KiB:
- `ticketId`, `agent`
- `report`: reason, note, line snapshot, picked token, created at
- `clip`: id, title, YouTube link, Studio URL, current verdict
- `instructions`: the editor's free text
- `playbook`: see below
- `api`: Studio base URL; the ticket, start and finish URLs; a reminder to use the shizen-studio MCP with `STUDIO_BASE_URL` set to prod

The payload carries no tokens. Each agent's environment already holds `STUDIO_AGENT_TOKEN`.

## Playbook

`webapp/studio-mcp/playbooks/clip-feedback.md` holds one section per report reason. It's also sent inline in the payload (OpenBot may not have the repo) and served by an MCP tool `get_playbook`.

- **timing:**
  1. `get_clip` view `full`. Look for tokens stretched over several seconds or with scores near 0.
  2. ASR compare. If the transcript is missing text (title card, outro jingle, interjections), add those lines.
  3. If every line is off by the same amount, use `shiftSec` instead.
  4. Re-run with mode `missing`, then check the new times against the audio's loudness. See the 2026-11-19 `short-w-vcntpqxou` fix.
- **translation:** rewrite that line's English. Check the lines around it for the same mistake.
- **tokenization / reading:** `patch_clip.tokens` for the line, then re-align `onlyUntimed`.
- **video:** don't edit. Finish as `could_not_fix` with what was seen, or deprecate with a reason when the clip is clearly broken.
- **other:** read the note, diagnose, and fix only what the evidence supports.
- **Rules:**
  - Never `delete_clip`.
  - Write English by hand when changing lines.
  - Keep the edit to the reported problem.
  - Always call `finish_ticket`, including on failure.

## MCP (`webapp/studio-mcp/src/tickets.ts`)

- `start_ticket {ticketId, runUrl?}`: calls `/start`, sets the process-wide ticket header, and returns the report, clip summary and playbook section.
- `claim_clip_feedback {feedbackId, agent?, runUrl?}` and `list_clip_feedback {status?, reason?}`: for an agent asked in chat to take a report (see Settled).
- `get_clip_feedback {id | clipId}`: reads reports. This needs `GET /api/experiments/clip-feedback?id=` added to the existing route.
- `finish_ticket {outcome, summary}`: calls `/finish` and clears the header.
- `get_playbook {reason?}`
- **ASR compare without a local machine:** `compare_clip_asr` shells out to `pnpm clip:asr-compare` with `.env.local`, which cloud agents don't have. Add `POST /api/experiments/clips/[id]/asr-compare` `{models}` that runs the same comparison on the server and returns per-model text. Then switch `compare_clip_asr` to call it when `STUDIO_BASE_URL` isn't localhost.
- **Optional `GET /api/experiments/clips/[id]/loudness`:** a coarse RMS envelope (for example 128 ms windows) computed server-side from the clip audio. The agent can then check timings without ffmpeg. Nice-to-have; ship it if decoding the WAV in Node is easy, since the clip audio is 16 kHz mono PCM.

## Studio UI (`components/experiments/clips/clip-feedback.tsx` + new `clip-agent-ticket.tsx`)

- On open reports, a **Send to agent ▾** button (Grok Bot / OpenBot, configured targets only) opens a small popover with optional instructions → dispatch.
- Under each report, its tickets as compact cards:
  - agent, status badge, times, run link, summary
  - an expandable **Changes** diff and an **Events** list, with cost
  - Retry when failed, Cancel while `sent`/`working`
- The resolved note shows "Fixed by Grok Bot · tkt_…", linking to the ticket card.
- The clip editor's Learner feedback section shows the same cards. A banner "Agent working on this clip (tkt_…)" appears while a ticket is `working`, so a human doesn't edit at the same time.
- Inbox filter chip: "Agent working".

## Setup outside the repo (owner)

1. **Cursor automation (Grok Bot):** a new automation with a webhook trigger.
   - Repo `speech-test`.
   - Secrets `STUDIO_AGENT_TOKEN`, `STUDIO_BASE_URL=https://shizen-studio.vercel.app`.
   - Prompt: "You received a clip feedback ticket. Call start_ticket with ticketId and your run URL, follow the playbook, then finish_ticket." `.cursor/mcp.json` already registers shizen-studio; it needs those env values passed through.
2. **OpenBot routine:** webhook routine with the same prompt. It uses the shizen-studio MCP against prod (`STUDIO_BASE_URL`, `STUDIO_AGENT_TOKEN`).
3. **Vercel env:** the four `CLIP_AGENT_*` vars.
4. **Create the table:** run `scripts/clip-agent-ticket-table.ts --write` against prod.

## Build order

1. Schema, DDL script, snapshot + diff with tests.
2. Ticket store, the API routes (including `/claim`), and the `X-Agent-Ticket` logging in the clip PATCH and step routes.
3. Dispatch and webhook signing (tests for both signatures), plus the targets route.
4. MCP: header in `studioFetch`, ticket tools, playbook file, `get_clip_feedback`.
5. Server ASR compare route, and the MCP switch.
6. Studio UI.
7. Owner setup, then a dry run on a test report: dispatch → agent → diff → resolved. Create the test report with the `qa-client` token.

PR to `main`. Merging auto-deploys prod, so create the table before merging.

## Settled (2026-11-20)

- **OpenBot:** OpenBot routines (and most of our bots) can use the whole shizen-studio MCP, so OpenBot uses the same MCP flow as Grok Bot and ships together with it. The "OpenBot ships second" fallback is gone.
- **Token:** the shared `STUDIO_AGENT_TOKEN` is used, with no ticket-scoped token. The `409` on closed or cancelled tickets is the only guard.
- **Who starts a ticket:** it's always a person:
  - Dispatching from Studio.
  - Asking an agent in chat to grab a report ("take the open timing report on short-w-…"). For this, add an MCP tool `claim_clip_feedback {feedbackId, agent?, runUrl?}`. It calls a new `POST /api/experiments/clip-feedback/[id]/claim`, which creates the ticket with `dispatched_by: "agent-token"` (and the agent name if given). That ticket goes straight to `working` with its `before` snapshot, and no webhook is sent. The tool then sets the ticket header just like `start_ticket`. `list_clip_feedback {status?, reason?}` (open reports, ticket state included) lets the agent find what to grab.
  - Nothing is dispatched automatically.
