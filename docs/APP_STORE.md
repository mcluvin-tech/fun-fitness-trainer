# App Store Submission Checklist

## Metadata (App Store Connect)

- **Name**: Fun Fitness Trainer
- **Subtitle**: Your silly coach for macros & meals
- **Category**: Health & Fitness
- **Age rating**: 4+ (no restricted content)
- **Privacy Policy URL**: (host docs/privacy-policy.md)
- **Terms URL**: (host docs/terms.md)

## Screenshots (6.7" iPhone)

1. Dashboard with macro rings + trainer quip
2. Food photo → confirm macros screen
3. Morning ritual chat
4. Phrase library / Trainer Voice settings
5. Meal log list

## App Privacy (Nutrition Labels)

| Data type | Linked to user | Purpose |
|-----------|----------------|---------|
| Photos | Yes | Food analysis |
| Health & fitness | Yes | Macro tracking |
| User content | Yes | Trainer phrases, chat |
| Identifiers | Yes | Account |

## Review notes

- Demo account: create a test user in Supabase or use Sign in with Apple sandbox.
- Explain that plate-photo macros are **estimates**; barcode / nutrition-label photos prefer on-device reading + Open Food Facts.
- Camera is required for photo logging; manual entry works without camera.

## Pre-submission

- [ ] TestFlight external beta (10+ testers)
- [ ] Restore purchases tested
- [ ] Delete account flow tested
- [ ] Offline dashboard works
- [ ] All Info.plist usage strings present
- [ ] Challenge invite links ready for people who don't have the app yet (see below)

## Challenge invite links (required before public launch)

Shared challenges must not rely on `funfitnesstrainer://…` alone — that only opens if the app is already installed.

1. **App Store product page** — In `Secrets.plist` set either:
   - `APP_STORE_URL` = `https://apps.apple.com/app/idXXXXXXXXX`, or
   - `APP_STORE_ID` = `XXXXXXXXX` (numeric Apple ID from App Store Connect)
   - Challenge share text then includes this download link automatically when the invite is still a custom-scheme URL.
2. **Universal Links (recommended)** — Own a host, host `/.well-known/apple-app-site-association`, add Associated Domains `applinks:YOUR_HOST`, then set `CHALLENGE_LINK_HOST` to that host. Invites become `https://YOUR_HOST/challenge/{token}` (one tap opens the app or your landing page → App Store).
3. **Landing page on that host** — For `/challenge/{token}`, open the app when installed; otherwise redirect to the App Store URL from step 1.

## Subscription products (App Store Connect)

| Product ID | Type |
|------------|------|
| `fft_pro_monthly` | Auto-renewable monthly |
| `fft_pro_yearly` | Auto-renewable yearly |

Entitlement in RevenueCat: `pro`
