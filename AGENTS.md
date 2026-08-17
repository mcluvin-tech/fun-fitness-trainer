# AGENTS.md

## Cursor Cloud specific instructions

This repo has two parts:

- **iOS app** (`FunFitnessTrainer/`, Swift/SwiftUI, Xcode) — requires macOS + Xcode. It **cannot be built or run on the Linux Cloud Agent VM** (no `swift`/`xcodebuild`). Treat it as read-only here; use a Mac for `scripts/run-simulator.sh`, signing, and TestFlight (`docs/XCODE_MVP_RUN.md`).
- **Supabase backend** (`supabase/functions/`) — two Deno/TypeScript Edge Functions (`analyze-food`, `trainer-chat`) plus SQL migrations. This is the part that runs and is testable on Linux.

### Running / testing the Edge Functions (backend scope)

The Cloud Agent environment already has **Deno** installed (on `PATH` as `deno`), which is the same runtime Supabase Edge Runtime uses, so functions run directly without Docker:

- Lint: `cd supabase/functions && deno lint`
- Type-check: `deno check analyze-food/index.ts` and `deno check trainer-chat/index.ts`
- Run a function locally: `deno run --allow-net --allow-env trainer-chat/index.ts` (serves on `http://localhost:8000`). Only one function can bind `:8000` at a time — stop one before starting the other.
- The functions import `_shared/*` via relative paths, so run them from `supabase/functions/`.

### Non-obvious gotchas

- Both functions call OpenAI. Without `OPENAI_API_KEY` in the environment they still start, pass CORS, and validate input, but any request that reaches the model returns `{"error":"OPENAI_API_KEY is not configured"}`. Set `OPENAI_API_KEY` (as a secret / env var) to exercise the actual macro-estimation and coaching replies end-to-end.
- The core response-parsing logic lives in `supabase/functions/_shared/structuredReply.ts` (`extractStructuredBlock`), which pulls `MEAL_JSON` / `GOAL_JSON` / `EXERCISE_JSON` blocks out of Larry's reply. It is pure and can be exercised without any API key via `deno eval`.
- `supabase start` / `npx supabase functions serve` (the "official" local stack in `supabase/README.md` and `docs/SETUP.md`) require **Docker**, which is not installed by default here. Running functions directly with `deno run` is the lightweight path and does not need Docker.
- `scripts/deploy-supabase.sh` and other `npx supabase` deploy commands need `supabase login` + `link` (user credentials) and a real project ref — they are not runnable unattended in this VM.
