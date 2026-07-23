# Next steps (start here)

Your app scaffold is ready. Work through this list in order.

## Supabase project (configured)

| Item | Status |
|------|--------|
| Project URL | `https://oidzizeeveglgqsmowaz.supabase.co` |
| iOS `Secrets.plist` | Updated locally (gitignored) |
| Project ref | `oidzizeeveglgqsmowaz` |
| Edge functions + DB migration | **You still need to deploy** (includes **The Pack** tables — see [docs/THE_PACK.md](docs/THE_PACK.md)) |
| OpenAI API key | **Not set yet** — required for food photo AI |
| Food data (OFF / USDA) | Voice logging uses **Open Food Facts name search**; see [docs/FOOD_DATA_SOURCES.md](docs/FOOD_DATA_SOURCES.md) |
| Google (Gmail) sign-in | **Not enabled yet** — [docs/GOOGLE_SIGNIN.md](docs/GOOGLE_SIGNIN.md) |

## Run MVP in Xcode now

**→ [docs/XCODE_MVP_RUN.md](docs/XCODE_MVP_RUN.md)** — simulator steps, MVP test flow, troubleshooting.

```bash
open FunFitnessTrainer/FunFitnessTrainer.xcodeproj
# Destination: iPhone 17 Simulator → ⌘R
```

---

## Today (≈30 min)

### 1. Install Xcode (if needed)
- Mac App Store → **Xcode** → install
- Terminal: `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`

### 2. Open the project
```bash
cd "/Users/lukeeidsvold/Social Media Guru/exports/Fun Fitness Trainer"
./scripts/setup.sh
```
Or double-click `FunFitnessTrainer/FunFitnessTrainer.xcodeproj`.

### 3. Run on your iPhone (demo mode)
- Xcode → select your **iPhone** as destination (not Simulator, for camera later)
- **Signing & Capabilities** → choose your **Team**
- Press **Run** (⌘R)
- Complete onboarding — app works offline with sample phrases (no Supabase yet)

## This week — backend (≈45 min)

### 4. Create Supabase project
1. [supabase.com/dashboard](https://supabase.com/dashboard) → New project
2. **Settings → API** → copy **Project URL** and **anon public** key
3. **Settings → General** → copy **Reference ID**

### 5. Configure the app
```bash
export SUPABASE_URL="https://YOUR_REF.supabase.co"
export SUPABASE_ANON_KEY="eyJ..."
./scripts/configure-secrets.sh
```

### 6. Deploy backend
```bash
export SUPABASE_PROJECT_REF="YOUR_REF"
export OPENAI_API_KEY="sk-..."
./scripts/deploy-supabase.sh
```

### 7. Enable Sign in with Apple (when you add accounts)
- [developer.apple.com](https://developer.apple.com) → Identifiers → `com.funfitnesstrainer.app` → Sign in with Apple
- Supabase Dashboard → **Authentication → Providers → Apple**

## TestFlight on your iPhone

**→ [docs/TESTFLIGHT_NOW.md](docs/TESTFLIGHT_NOW.md)** — run on device today (free team) or upload to TestFlight (paid program).

```bash
./scripts/archive-testflight.sh   # after paid Developer Program + App Store Connect app
```

## Next week — TestFlight

### 8. Apple Developer Program ($99/yr)
- Enroll → create App ID `com.funfitnesstrainer.app`
- App Store Connect → **Fun Fitness Trainer**

### 9. Archive & TestFlight
- Xcode → **Product → Archive** → Distribute → TestFlight
- Invite 5–10 friends; test photo log + morning ritual

### 10. Before App Store submit
- Host [docs/privacy-policy.md](docs/privacy-policy.md) and [docs/terms.md](docs/terms.md) (replace support email)
- Add 1024×1024 app icon in Assets
- Create subscriptions `fft_pro_monthly` / `fft_pro_yearly` in App Store Connect
- Full checklist: [docs/APP_STORE.md](docs/APP_STORE.md)

## Quick commands

| Task | Command |
|------|---------|
| Open Xcode | `open FunFitnessTrainer/FunFitnessTrainer.xcodeproj` |
| Set API keys | `./scripts/configure-secrets.sh` |
| Deploy Supabase | `./scripts/deploy-supabase.sh` |
| Set up Gmail sign-in | `./scripts/setup-google-auth.sh` |
| Trainer voice ideas | [docs/trainer-voice-template.md](docs/trainer-voice-template.md) |

## What you need to provide

| Item | Where it goes |
|------|----------------|
| Supabase URL + anon key | `Secrets.plist` via `configure-secrets.sh` |
| OpenAI API key | Supabase secrets (`deploy-supabase.sh`) |
| Apple Developer Team ID | Xcode Signing |
| Privacy/Terms URLs | App Store Connect + Settings links |

Questions or blockers? Say which step you're on (e.g. “Supabase deploy failed”) and we can fix it.
