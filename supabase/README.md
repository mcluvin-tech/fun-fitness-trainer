# Supabase backend

## Deploy

```bash
npx supabase functions deploy analyze-food --no-verify-jwt
npx supabase functions deploy trainer-chat --no-verify-jwt
```

For production, keep `verify_jwt = true` in `config.toml` and ensure the iOS app sends the user's JWT (already implemented in `SupabaseService`).

## Local test

```bash
npx supabase start
npx supabase functions serve analyze-food --env-file .env.local
```

Example `.env.local`:

```
OPENAI_API_KEY=sk-...
```

## Functions

| Function | Purpose |
|----------|---------|
| `analyze-food` | Vision macro estimate (gpt-4o) |
| `trainer-chat` | Larry chat, including diet / gains guidance (prompt version 17). Redeploy after prompt edits. |
