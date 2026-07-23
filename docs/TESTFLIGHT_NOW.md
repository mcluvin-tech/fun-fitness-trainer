# TestFlight on your iPhone (today)

## No USB cable?

| Goal | Workaround |
|------|------------|
| Test on **real iPhone** without cable | **TestFlight** (paid Developer Program) — build on Mac, install over Wi‑Fi/cellular. No Mac↔phone cable. |
| Test **UI + flows** on Mac | **iPhone Simulator** in Xcode (⌘R with a simulator selected). Camera is limited; use manual food log or drag photos into Simulator. |
| Install from Xcode **without cable** | **Maybe**: same Wi‑Fi, iPhone **Developer Mode** on, Mac and phone on same Apple ID — Xcode → **Window → Devices and Simulators** → select phone → ✓ **Connect via network**. Often still needs **one** USB pairing first; if the phone was never paired to this Mac, wireless may not appear. |
| Register device UDID for archive | App Store Connect → **Users and Access → Devices** → **+** → add UDID manually (find UDID on iPhone: no native UI; use a one-time web tool, Apple Configurator at a library/friend’s Mac, or any brief USB borrow). |

**Practical pick:** enroll in the Developer Program → Archive on Mac → **TestFlight** on your phone. That’s the standard no-cable path.

---

## If you only have a free Personal Team

**TestFlight is not available** on a free Apple ID. You can still run the app on your phone today:

1. Plug in your iPhone → unlock → trust the Mac if prompted.
2. Open `FunFitnessTrainer/FunFitnessTrainer.xcodeproj`.
3. Top bar: select **your iPhone** (not Simulator).
4. **Signing & Capabilities** → Team **Luke Eidsvold** → ✓ Automatically manage signing.
5. **⌘R** (Run). First install may ask you to enable **Developer Mode** on the iPhone (Settings → Privacy & Security).

The build uses your local `Secrets.plist` (Supabase). Photo AI needs deployed backend + OpenAI key; until then use **Log manually**.

---

## TestFlight (requires Apple Developer Program — $99/yr)

### 1. Enroll (if not done)

[developer.apple.com/programs](https://developer.apple.com/programs/) → enroll → wait for approval (often same day).

### 2. App Store Connect app

1. [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → **Apps** → **+** → New App.
2. **Bundle ID**: `com.lukeeidsvold.funfitnesstrainer` (must match Xcode).
3. Name: **Fun Fitness Trainer**.

### 3. Xcode signing

1. Open the project → target **FunFitnessTrainer** → **Signing & Capabilities**.
2. Team: your **paid** team (not “Personal Team” only).
3. Bundle ID: `com.lukeeidsvold.funfitnesstrainer`.

### 4. Register your iPhone (fixes “no devices” archive error)

1. Plug in your iPhone (USB or same Wi‑Fi with **Connect via network** in Xcode).
2. Unlock the phone → tap **Trust** if asked.
3. In Xcode’s device menu, select **your iPhone** once so Xcode registers its UDID with your team.

### 5. Archive & upload

1. Destination: **Any iOS Device (arm64)** (not Simulator).
2. **Product → Archive** (wait for Organizer to open).
3. **Distribute App** → **App Store Connect** → **Upload**.
4. Fix any errors (missing icon, signing) and retry.

Or from Terminal (after paid team is selected in Xcode):

```bash
./scripts/archive-testflight.sh
```

### 6. Install on your phone

1. App Store Connect → your app → **TestFlight**.
2. Wait for **Processing** (5–30 min).
3. Install **TestFlight** from the App Store on your iPhone.
4. Accept the invite (internal testing: you as App Store Connect user are auto-eligible) → install **Fun Fitness Trainer**.

### 7. Sign in with Apple (optional, after paid enroll)

1. Developer portal → App ID → enable **Sign in with Apple**.
2. In Xcode Release build settings, set entitlements to `FunFitnessTrainer.entitlements` (not `.dev`).
3. In `AppConfig.swift`, set `supportsSignInWithApple = true`.
4. Supabase → Authentication → Apple provider.

---

## Quick checklist

| Error | Fix |
|-------|-----|
| Sign in with Apple / Personal Team | Release build already uses empty entitlements until you enroll (see step 7). |
| No devices on team | Plug in iPhone; select it once in Xcode. |
| TestFlight not available | Enroll in paid Developer Program (free Personal Team cannot use TestFlight). |

| Step | Done? |
|------|-------|
| Paid Apple Developer Program | |
| iPhone registered (plugged in once in Xcode) | |
| App created in App Store Connect (matching bundle ID) | |
| Archive succeeds in Xcode | |
| Build processed in TestFlight | |
| TestFlight app installed on iPhone | |

Questions? Say where you’re stuck (e.g. “Archive failed”, “Processing forever”).
