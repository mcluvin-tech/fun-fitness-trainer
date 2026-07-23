# Supabase setup (Dashboard fallback)

Use this if `deploy-supabase.sh` fails before you're logged into the CLI.

## 1. Run database migration

Supabase Dashboard → **SQL Editor** → New query → paste contents of:

`supabase/migrations/20250601000000_profiles.sql`

→ **Run**.

## 2. Set OpenAI secret

Dashboard → **Edge Functions** → Secrets → add:

- `OPENAI_API_KEY` = your OpenAI key (`sk-...`)

## 3. Deploy functions (CLI)

```bash
npx supabase login
cd "/Users/lukeeidsvold/Social Media Guru/exports/Fun Fitness Trainer"
export SUPABASE_PROJECT_REF=oidzizeeveglgqsmowaz
export OPENAI_API_KEY=sk-...
./scripts/deploy-supabase.sh
```

## 4. Enable Gmail / Google sign-in (required for “Continue with Gmail”)

See **[GOOGLE_SIGNIN.md](GOOGLE_SIGNIN.md)** or run:

```bash
chmod +x scripts/setup-google-auth.sh
./scripts/setup-google-auth.sh
```

## 5. Enable Apple auth (optional)

Dashboard → **Authentication** → **Providers** → Apple.

## 6. Enable Phone sign-in (required for “Continue with Phone Number”)

1. Dashboard → **Authentication** → **Providers** → **Phone** → enable.
2. Configure an SMS provider (e.g. **Twilio**): Account SID, Auth Token, and a sending phone number.
3. In the app, enter numbers in E.164 format (e.g. `+1 555 123 4567`). US 10-digit numbers are auto-prefixed with `+1`.

## Keys for this project

- **URL**: `https://oidzizeeveglgqsmowaz.supabase.co`
- **Client key**: Dashboard → **Settings → API** → use **publishable** or **anon** key in the iOS app (already in local `Secrets.plist`).

**Never** put the database password in the iOS app — it is only for CLI/direct Postgres.
