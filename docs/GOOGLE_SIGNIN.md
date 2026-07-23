# Gmail / Google sign-in setup

Your app uses Supabase OAuth with a deep link back to the app (`funfitnesstrainer://auth-callback`).

**Project:** `oidzizeeveglgqsmowaz`  
**Dashboard:** [Authentication → Providers → Google](https://supabase.com/dashboard/project/oidzizeeveglgqsmowaz/auth/providers?provider=Google)

If you see `Unsupported provider: provider is not enabled`, Google is not configured in Supabase yet. Follow the steps below (~15 min).

---

## 1. Google Cloud Console

1. Open [Google Cloud Console → Credentials](https://console.cloud.google.com/apis/credentials).
2. Create or select a project.
3. **OAuth consent screen** → configure (app name, support email, scopes: `email`, `profile`, `openid`).
4. **Create credentials → OAuth client ID → Web application** (Supabase uses the web client for the OAuth callback).

   | Field | Value |
   |-------|--------|
   | **Authorized redirect URIs** | `https://oidzizeeveglgqsmowaz.supabase.co/auth/v1/callback` |

5. Copy the **Client ID** and **Client secret**.

Optional: create an **iOS** OAuth client with bundle ID `com.lukeeidsvold.funfitnesstrainer` if Google asks for it later.

---

## 2. Supabase Dashboard

1. [Providers → Google](https://supabase.com/dashboard/project/oidzizeeveglgqsmowaz/auth/providers?provider=Google)
2. **Enable** Google.
3. Paste **Client ID** and **Client secret** from step 1.
4. Save.

---

## 3. Redirect URLs in Supabase

1. [Authentication → URL Configuration](https://supabase.com/dashboard/project/oidzizeeveglgqsmowaz/auth/url-configuration)
2. Set **Site URL** to: `funfitnesstrainer://auth-callback`
3. Under **Redirect URLs**, add:
   - `funfitnesstrainer://auth-callback`
   - `funfitnesstrainer://**` (wildcard, if available)

Save.

---

## 4. Test in the app

1. Rebuild and run in Xcode (no code change needed after dashboard setup).
2. Onboarding → **Continue with Gmail**.
3. Sign in with your Google account in the browser sheet.
4. You should return to the app with **Signed in** shown.

---

## Quick open (Terminal)

```bash
./scripts/setup-google-auth.sh
```

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `provider is not enabled` | Complete steps 1–2 above |
| `redirect_uri_mismatch` | Redirect URI in Google Cloud must be exactly `https://oidzizeeveglgqsmowaz.supabase.co/auth/v1/callback` |
| App doesn’t return after Google login | Add `funfitnesstrainer://auth-callback` to Supabase redirect URLs (step 3) |
| Blank browser / JSON error | Google provider still disabled or wrong Client ID/Secret |
