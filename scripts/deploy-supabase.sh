#!/usr/bin/env bash
# Deploy DB migration + edge functions. Requires: npx, supabase login, supabase link.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -f supabase/.env.local ]]; then
  set -a
  # shellcheck disable=SC1091
  source supabase/.env.local
  set +a
fi

if [[ -z "${SUPABASE_PROJECT_REF:-}" ]]; then
  echo "Set SUPABASE_PROJECT_REF (from Supabase Dashboard → Project Settings → General)."
  echo "Example: export SUPABASE_PROJECT_REF=abcdefghijklmnop"
  exit 1
fi

if [[ -z "${OPENAI_API_KEY:-}" ]]; then
  echo "Set OPENAI_API_KEY for edge functions."
  echo "Example: export OPENAI_API_KEY=sk-..."
  exit 1
fi

echo "Linking project $SUPABASE_PROJECT_REF..."
npx supabase link --project-ref "$SUPABASE_PROJECT_REF"

echo "Setting OpenAI secret..."
npx supabase secrets set "OPENAI_API_KEY=$OPENAI_API_KEY"

echo "Pushing database migration..."
npx supabase db push

echo "Deploying edge functions..."
npx supabase functions deploy analyze-food
npx supabase functions deploy trainer-chat

echo "Done. Copy Project URL + anon key into Secrets.plist:"
echo "  ./scripts/configure-secrets.sh"
