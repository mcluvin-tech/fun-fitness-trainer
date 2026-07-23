#!/usr/bin/env bash
# Writes FunFitnessTrainer/FunFitnessTrainer/Secrets.plist from env vars or prompts.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SECRETS="$ROOT/FunFitnessTrainer/FunFitnessTrainer/Secrets.plist"

read_val() {
  local key="$1" prompt="$2" default="${3:-}"
  if [[ -n "${!key:-}" ]]; then
    echo "${!key}"
    return
  fi
  if [[ -t 0 ]]; then
    read -r -p "$prompt${default:+ [$default]}: " val
    echo "${val:-$default}"
  else
    echo "$default"
  fi
}

SUPABASE_URL="$(read_val SUPABASE_URL "Supabase Project URL (https://xxx.supabase.co)" "https://YOUR_PROJECT.supabase.co")"
SUPABASE_ANON_KEY="$(read_val SUPABASE_ANON_KEY "Supabase anon or publishable key" "${SUPABASE_PUBLISHABLE_KEY:-YOUR_ANON_KEY}")"
REVENUECAT_API_KEY="$(read_val REVENUECAT_API_KEY "RevenueCat public API key (optional)" "appl_YOUR_REVENUECAT_KEY")"

cat > "$SECRETS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>SUPABASE_URL</key>
	<string>${SUPABASE_URL}</string>
	<key>SUPABASE_ANON_KEY</key>
	<string>${SUPABASE_ANON_KEY}</string>
	<key>REVENUECAT_API_KEY</key>
	<string>${REVENUECAT_API_KEY}</string>
</dict>
</plist>
PLIST

echo "Wrote $SECRETS"
if [[ "$SUPABASE_URL" == *YOUR_PROJECT* ]]; then
  echo "Tip: Create a free project at https://supabase.com/dashboard then re-run:"
  echo "  SUPABASE_URL=... SUPABASE_ANON_KEY=... ./scripts/configure-secrets.sh"
fi
