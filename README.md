# Fun Fitness Trainer

Personality-first iOS fitness companion: silly AI morning coach, food photo / barcode / nutrition-label macros, and daily tracking.

## Requirements

- Xcode 16+ (iOS 17+ deployment target)
- Apple Developer Program ($99/yr) for TestFlight and App Store
- Supabase project (Auth + Edge Functions)
- OpenAI API key (server-side only)

## Quick start

**→ Follow [NEXT_STEPS.md](NEXT_STEPS.md)** for the ordered checklist.

```bash
./scripts/setup.sh                    # open Xcode, verify secrets
./scripts/configure-secrets.sh        # after you create Supabase project
./scripts/deploy-supabase.sh          # needs OPENAI_API_KEY + SUPABASE_PROJECT_REF
```

1. **iOS**: Open `FunFitnessTrainer/FunFitnessTrainer.xcodeproj` in Xcode, set your Team, Run on iPhone.
2. **Supabase**: See [docs/SETUP.md](docs/SETUP.md) for full backend setup.
3. **Demo mode** works without Supabase (local phrases + mock macro estimates).

## Project structure

```
FunFitnessTrainer/          # Xcode app
supabase/functions/         # analyze-food, trainer-chat
docs/                       # Setup, privacy, trainer voice template
```

## App Store checklist

See [docs/APP_STORE.md](docs/APP_STORE.md).

## License

Proprietary — all rights reserved.
