# The Pack (minimal friends)

There is **no Friends tab**. One rule:

**A friend is anyone in your pack — i.e. anyone who joined the same invite code as you.**

## How it works

1. Sign in (Settings → Apple / Google / phone).
2. Open **The pack** on the home screen.
3. Your **6-character pack code** is created automatically. Share it (text, group chat, etc.).
4. Friends tap **Join pack**, enter your code, and they’re in.
5. When anyone in the pack logs food, **interesting weekly stats** show up in **Pack eats** — absurd counts like “Luke had eight eggs this week” or “logged twelve cups of ground beef.” Individual meal logs still sync in the background for now; the feed filters to the good stuff until the pack tab is fully built out.

You can join multiple codes over time (e.g. gym crew + family); you’ll see meals from everyone who shares **any** pack with you.

## Backend

- Tables: `packs`, `pack_members`, `pack_meal_posts`
- RPC: `ensure_my_pack()`, `join_pack(code)`
- Deploy: run `./scripts/deploy-supabase.sh` (applies migration)

## Demo mode

Without sign-in or before migration deploy, the app shows sample pack activity plus your local log for today.
