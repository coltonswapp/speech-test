# Plan: clip feedback → agent attempts

Status: building, 2026-11-20, on `feat/clip-agent-attempts` off `origin/main`. This is the slimmed plan: it drops the ticket header, the event log and the six-state machine from the first draft.

## Goal

An agent fixes the clips learners flag, and every fix can be checked afterwards.

Two ways in, both started by a person:
- **Chat:** "check on current flagged clips". The agent calls `list_clip_feedback`, then for each report: `claim_clip_feedback`, fix it (re-run a step, add lines, fix a reading), `finish_clip_feedback`. One report at a time.
- **Studio:** **Send to agent ▾** on an open report in the feedback inbox or the clip editor. It posts a webhook to Grok Bot (Cursor automation) or OpenBot. The bot then claims the report and follows the same flow.

## Attempt

Table `clip_agent_attempt`: one row per try at one report. A second try, or the other agent, gets a new row, so earlier snapshots are kept.

| column | notes |
|---|---|
| `id` | `att_<random>` |
| `feedback_id`, `clip_id` | |
| `agent` | `grokbot`, `openbot`, or whatever name the claiming agent gives (`claude`) |
| `dispatched_by` | Studio session email, or `agent-token` for a claim from chat |
| `instructions` | optional text typed when dispatching |
| `status` | `dispatched` (webhook sent, not claimed yet), `working`, `done`, or `failed` (the webhook failed) |
| `delivery` | jsonb: HTTP status, error, time |
| `run_url` | the agent's session link, set at claim |
| `before` / `after` | jsonb clip snapshots, taken by the server at claim and at finish |
| `outcome` | `fixed` \| `no_change_needed` \| `needs_review` \| `could_not_fix` |
| `summary` | the agent's note: cause and what it changed |
| `created_at`, `started_at`, `finished_at`, `updated_at` | |

- **Snapshot** (`lib/clip-agent/snapshot.ts`, pure): for each line, `ja`, `en`, start and end, and tokens with readings. Plus `shiftSec`, the feed verdict, `jlptLevel` and `deprecated`.
- **Diff** (`lib/clip-agent/diff.ts`, pure, tested): lines are matched by `ja` (LCS). It reports added and removed lines, English and reading changes, timing moves over 0.25 s, and clip field changes.
- **Runs:** the clip's own `usage` entries between `started_at` and `finished_at` show which steps the agent re-ran, and their cost. A human edit during the window also shows up, so the UI labels it "changes while the attempt was open".

## Outcomes

- `fixed` / `no_change_needed`: the report is resolved with the note "<Agent> · att_… · <first line of summary>".
- `needs_review`: the report stays open with a **Needs review** badge. You look at the diff and the summary, then **Accept**, which resolves the report with the agent's note. There's no Revert.
- `could_not_fix`: the report stays open.

## API (behind the Studio gate)

- `GET /api/experiments/clip-feedback`:
  - Each row gets its attempts, each with a computed diff and runs.
  - `?id=` returns one report.
  - The response also lists the configured agent targets.
- `POST /api/experiments/clip-feedback/[id]/dispatch {agent, instructions?}`:
  - Refused if the report isn't open, or if it already has a `dispatched` or `working` attempt.
  - Inserts the attempt, then sends the webhook with an 8 s timeout and records `delivery`. A failed delivery marks the attempt `failed`.
- `POST /api/experiments/clip-feedback/[id]/claim {agent?, runUrl?}`:
  - Takes over that report's `dispatched` attempt, or creates a new one.
  - Takes the `before` snapshot and sets the attempt to `working`.
  - Returns the attempt id, the report, the clip and the playbook for the report's reason.
  - Refused if the report already has a `working` attempt.
- `POST /api/experiments/clip-agent-attempts/[id]/finish {outcome, summary}`: takes the `after` snapshot, sets `done`, and resolves the report for `fixed` or `no_change_needed`.
- `POST /api/experiments/clips/[id]/asr-compare {models?}`: re-transcribes the stored audio with each model on the server. Returns each model's lines, the saved transcript, and where they differ. Cloud agents use it for timing reports.

## Webhooks (`lib/clip-agent/dispatch.ts`)

| target | env | auth |
|---|---|---|
| Grok Bot | `CLIP_AGENT_GROKBOT_WEBHOOK_URL`, `CLIP_AGENT_GROKBOT_WEBHOOK_KEY` | `Authorization: Bearer` and `X-Automation-Key` (as `auto-stamp-review-webhook.ts`) |
| OpenBot | `CLIP_AGENT_OPENBOT_WEBHOOK_URL`, `CLIP_AGENT_OPENBOT_WEBHOOK_SECRET` | `{type, occurredAt, data}` envelope; HMAC-SHA256 over `timestamp.id.body` in `X-OpenBot-Signature: sha256=<hex>`, as CSFeedbackKit's `RequestSigner` does |

- A target without env is hidden in Studio.
- The payload (`type: "clip-feedback.attempt"`, under 64 KiB) has the attempt id, the report, the clip and its links, the instructions, the playbook section, and what to call: `claim_clip_feedback`, then `finish_clip_feedback`, using the shizen-studio MCP with `STUDIO_BASE_URL` set to prod.
- The payload carries no tokens.

## Playbook (`lib/clip-agent/playbook.ts`)

One section per report reason, plus rules. `claim` returns it and the webhook payload carries it, so agents without the repo get it too.

## MCP (`studio-mcp/src/feedback.ts`)

- `list_clip_feedback {status?, reason?, clipId?}`: reports, each with its attempts.
- `claim_clip_feedback {feedbackId, agent?, runUrl?}`: returns the attempt id, report, clip and playbook.
- `finish_clip_feedback {attemptId, outcome, summary}`.
- `compare_clip_asr`: uses the server route when `STUDIO_BASE_URL` isn't localhost, or when `server: true`.

## Studio UI

- **Send to agent ▾**, one entry per configured target, with optional instructions.
- Attempt cards under each report:
  - agent, status, outcome, times, run link, summary
  - an expandable diff, plus the runs and their cost
- The **Needs review** badge and **Accept**.

## Setup outside the repo

1. Vercel env: the four `CLIP_AGENT_*` vars.
2. The Cursor automation and the OpenBot routine. Each prompt says to call `claim_clip_feedback` with the payload's `feedbackId` and its own run URL, follow the playbook, then call `finish_clip_feedback`. Both need `STUDIO_BASE_URL` and a Studio agent token (`STUDIO_AGENT_TOKEN`): a named per-agent token from Settings → Agent tokens, or the shared env token during migration.
3. Create the table before merging, because merging deploys prod: `pnpm exec dotenv -e .env.local -- tsx scripts/clip-agent-attempt-table.ts --write`.
