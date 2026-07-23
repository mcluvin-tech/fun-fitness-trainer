# Setup Guide

## 1. Apple Developer Program

1. Enroll at [developer.apple.com](https://developer.apple.com/programs/).
2. In **Certificates, Identifiers & Profiles**, create App ID: `com.funfitnesstrainer.app`.
3. Enable **Sign in with Apple** capability for the App ID.
4. Create an App Store Connect app record (name: **Fun Fitness Trainer**).

## 2. Supabase

```bash
cd supabase
npx supabase login
npx supabase link --project-ref YOUR_PROJECT_REF
npx supabase secrets set OPENAI_API_KEY=sk-...
npx supabase db push   # applies migrations
npx supabase functions deploy analyze-food
npx supabase functions deploy trainer-chat
```

Copy **Project URL** and **anon public key** into secrets (from repo root):

```bash
./scripts/configure-secrets.sh
```

File written: `FunFitnessTrainer/FunFitnessTrainer/Secrets.plist` (gitignored).

### Database

Migrations in `supabase/migrations/` create `profiles` for trainer voice and phrase sync.

### Edge function secrets

| Secret | Required |
|--------|----------|
| `OPENAI_API_KEY` | Yes |
| `SUPABASE_SERVICE_ROLE_KEY` | Auto in Supabase |

## 3. iOS secrets

Never commit `Secrets.plist`. It is gitignored.

```xml
<key>SUPABASE_URL</key>
<string>https://xxxx.supabase.co</string>
<key>SUPABASE_ANON_KEY</key>
<string>eyJ...</string>
```

## 4. Google (Gmail) sign-in

1. [Google Cloud Console](https://console.cloud.google.com/) → APIs & Services → Credentials → **OAuth client ID** (iOS or Web).
2. Supabase Dashboard → **Authentication → Providers → Google** → enable, paste Client ID and Secret.
3. Supabase → **Authentication → URL Configuration** → add redirect URL:
   - `funfitnesstrainer://auth-callback`
4. Rebuild the app. **Continue with Gmail** opens a browser and returns to the app.

## 5. Sign in with Apple (paid Developer Program only)

Free **Personal Team** accounts cannot use Sign in with Apple. The default entitlements file is empty so you can run on Simulator.

When you enroll in the paid program ($99/yr):

1. Replace `FunFitnessTrainer.entitlements` with `FunFitnessTrainer.entitlements.production` (or copy its contents).
2. Set `AppConfig.supportsSignInWithApple = true`.
3. Enable Sign in with Apple on App ID `com.funfitnesstrainer.app` in the Developer portal.

## 6. RevenueCat (Phase 4)

1. Create project at [revenuecat.com](https://www.revenuecat.com).
2. Add iOS app with bundle ID `com.funfitnesstrainer.app`.
3. Create entitlement `pro` and products `fft_pro_monthly` / `fft_pro_yearly` in App Store Connect.
4. Add `REVENUECAT_API_KEY` to `Secrets.plist` (optional until subscriptions go live).

## 7. Privacy URLs

Host `docs/privacy-policy.md` and `docs/terms.md` on your site (GitHub Pages, Notion public page, etc.) and enter URLs in App Store Connect.
