#!/usr/bin/env bash
# Build (if needed), install, and launch Fun Fitness Trainer on Luka iPhone.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/FunFitnessTrainer/FunFitnessTrainer.xcodeproj"
DERIVED="$ROOT/FunFitnessTrainer/build/DeviceDerivedData"
APP="$DERIVED/Build/Products/Debug-iphoneos/FunFitnessTrainer.app"
UDID="${DEVICE_UDID:-DFA7AA9C-6BC6-5F6C-B8D8-AC5E94F453C2}"
BUNDLE="com.lukeeidsvold.funfitnesstrainer"
TEAM="${DEVELOPMENT_TEAM:-3WNFLLTU4W}"

echo "Looking for Luka iPhone..."
if ! xcrun devicectl list devices 2>/dev/null | grep -Eq "available \(paired\)|connected"; then
  echo ""
  echo "Phone is not online in Xcode."
  echo "1. Plug in USB (or same Wi‑Fi with Connect via network)."
  echo "2. Unlock the iPhone → tap Trust if asked."
  echo "3. Xcode → Window → Devices and Simulators → confirm Luka iPhone is green/connected."
  echo "4. Re-run: ./scripts/install-on-iphone.sh"
  exit 1
fi

echo "Building for device (generic iOS — avoids DDI destination timeouts)..."
xcodebuild \
  -project "$PROJECT" \
  -scheme FunFitnessTrainer \
  -configuration Debug \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$DERIVED" \
  DEVELOPMENT_TEAM="$TEAM" \
  -allowProvisioningUpdates \
  build

if [[ ! -d "$APP" ]]; then
  echo "Build finished but app not found at: $APP"
  exit 1
fi

echo "Built CFBundleVersion=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist" 2>/dev/null || echo '?')"

echo "Installing..."
xcrun devicectl device install app --device "$UDID" "$APP"

echo "Launching..."
xcrun devicectl device process launch --terminate-existing --device "$UDID" "$BUNDLE" || true

echo ""
echo "✓ Installed. On the iPhone:"
echo "  • If prompted: Settings → General → VPN & Device Management → trust developer."
echo "  • Open Larry McQuade Macro Tracker from the home screen."
echo "  • Confirm Settings → About (or Xcode Devices) shows build 2+."
