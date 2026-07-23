#!/usr/bin/env bash
# Build and launch Fun Fitness Trainer on iPhone 17 simulator.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/FunFitnessTrainer/FunFitnessTrainer.xcodeproj"
SCHEME="FunFitnessTrainer"
SIMULATOR_NAME="${SIMULATOR_NAME:-iPhone 17}"
DERIVED="$ROOT/FunFitnessTrainer/build/DerivedData"

echo "Building for $SIMULATOR_NAME..."
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,name=$SIMULATOR_NAME" \
  -derivedDataPath "$DERIVED" \
  build

APP="$DERIVED/Build/Products/Debug-iphonesimulator/FunFitnessTrainer.app"
if [[ ! -d "$APP" ]]; then
  echo "Build succeeded but app not found at $APP"
  exit 1
fi

echo "Booting simulator..."
xcrun simctl boot "$SIMULATOR_NAME" 2>/dev/null || true
open -a Simulator

echo "Installing app..."
xcrun simctl install booted "$APP"

BUNDLE_ID="com.lukeeidsvold.funfitnesstrainer"
echo "Launching $BUNDLE_ID..."
xcrun simctl launch booted "$BUNDLE_ID"

echo "Done — Fun Fitness Trainer should be open in the simulator."
