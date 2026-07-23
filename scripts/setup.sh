#!/usr/bin/env bash
# One-shot local setup for Fun Fitness Trainer.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "=== Fun Fitness Trainer setup ==="

# 1. Secrets
if [[ ! -f FunFitnessTrainer/FunFitnessTrainer/Secrets.plist ]]; then
  cp FunFitnessTrainer/Config/Secrets.example.plist FunFitnessTrainer/FunFitnessTrainer/Secrets.plist
fi
echo "[1/4] Secrets.plist present at FunFitnessTrainer/FunFitnessTrainer/Secrets.plist"
echo "      Run ./scripts/configure-secrets.sh when you have Supabase credentials."

# 2. Xcode
if [[ -d /Applications/Xcode.app ]]; then
  echo "[2/4] Opening Xcode project..."
  open FunFitnessTrainer/FunFitnessTrainer.xcodeproj
  echo "      In Xcode: select your Team under Signing & Capabilities."
else
  echo "[2/4] Xcode.app not found. Install from the Mac App Store, then run:"
  echo "      open FunFitnessTrainer/FunFitnessTrainer.xcodeproj"
fi

# 3. Supabase CLI hint
echo "[3/4] Backend (when ready):"
echo "      export SUPABASE_PROJECT_REF=your_ref"
echo "      export OPENAI_API_KEY=sk-..."
echo "      ./scripts/deploy-supabase.sh"

# 4. Checklist
echo "[4/4] See NEXT_STEPS.md for Apple Developer + TestFlight checklist."
echo "=== Setup script finished ==="
