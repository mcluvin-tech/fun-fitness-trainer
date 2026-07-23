#!/usr/bin/env bash
# Deploy only the trainer-chat edge function (Larry prompt updates).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -f supabase/.env.local ]]; then
  set -a
  # shellcheck disable=SC1091
  source supabase/.env.local
  set +a
fi

PROJECT_REF="${SUPABASE_PROJECT_REF:-oidzizeeveglgqsmowaz}"
SUPABASE="npx --yes supabase@2.104.0"

if ! $SUPABASE projects list &>/dev/null; then
  echo "Not logged in to Supabase yet."
  echo "Run this first (opens browser):"
  echo "  $SUPABASE login"
  exit 1
fi

echo "Deploying trainer-chat to $PROJECT_REF..."
$SUPABASE functions deploy trainer-chat --no-verify-jwt --project-ref "$PROJECT_REF"
echo "Done — Larry prompt v11 is live."
