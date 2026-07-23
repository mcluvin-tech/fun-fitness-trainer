#!/usr/bin/env bash
# Archive Fun Fitness Trainer for App Store Connect / TestFlight upload.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/FunFitnessTrainer/FunFitnessTrainer.xcodeproj"
SCHEME="FunFitnessTrainer"
ARCHIVE="${ARCHIVE_PATH:-$HOME/Desktop/FunFitnessTrainer.xcarchive}"

echo "Archiving to: $ARCHIVE"
echo "Open the archive in Xcode Organizer to upload: Product → Organizer → Distribute App"
echo ""

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  archive

echo ""
echo "✓ Archive succeeded: $ARCHIVE"
echo "Next: open Xcode → Window → Organizer → select archive → Distribute App → App Store Connect → Upload"
