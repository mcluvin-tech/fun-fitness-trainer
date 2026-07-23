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
- Explain that macro values from photos are **estimates**.
- Camera is required for photo logging; manual entry works without camera.

## Pre-submission

- [ ] TestFlight external beta (10+ testers)
- [ ] Restore purchases tested
- [ ] Delete account flow tested
- [ ] Offline dashboard works
- [ ] All Info.plist usage strings present

## Subscription products (App Store Connect)

| Product ID | Type |
|------------|------|
| `fft_pro_monthly` | Auto-renewable monthly |
| `fft_pro_yearly` | Auto-renewable yearly |

Entitlement in RevenueCat: `pro`
