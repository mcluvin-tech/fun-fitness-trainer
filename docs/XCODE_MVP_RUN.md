# Run the MVP in Xcode (5 minutes)

## 1. Open the project

```bash
open "/Users/lukeeidsvold/Social Media Guru/exports/Fun Fitness Trainer/FunFitnessTrainer/FunFitnessTrainer.xcodeproj"
```

## 2. Select the simulator (important)

Top toolbar, **center-right**:

| Must be | Must NOT be |
|---------|-------------|
| **iPhone 17** (or any iPhone **Simulator**) | **Any iOS Device** |
| | **My Mac** |

Signing errors about "no devices" are normal for **Any iOS Device** — ignore them when using the simulator.

## 3. Signing (one time)

1. Click blue **FunFitnessTrainer** project (left sidebar).
2. Target **FunFitnessTrainer** → **Signing & Capabilities**.
3. **Automatically manage signing** ✓
4. **Team** → **Luke Eidsvold (Personal Team)**
5. Bundle ID: `com.lukeeidsvold.funfitnesstrainer` (already set)

Yellow warnings on Signing are OK for simulator runs.

## 4. Run

**Product → Clean Build Folder** (⇧⌘K) once, then **⌘R**.

First launch takes 1–3 minutes. The **Simulator** app opens with **Fun Fitness Trainer**.

## 5. MVP walkthrough (test in 3 min)

1. **Onboarding** → Continue through welcome, body stats, optional trainer voice → **Let's go!**
2. **Morning ritual** → chat or tap **Skip** (top right).
3. **Today** tab → macro rings (empty until you log).
4. **Log** tab → **Pick a food photo** (simulator) or **Log manually** → enter calories/protein → Save.
5. **Today** → see rings update + trainer quip.
6. **Settings** → phrase library, trainer voice.

### Simulator food photos

- Drag an image from your Mac onto the simulator window, or
- In Simulator menu: **File → Open Simulator Data** … easier: use **Photos** app in simulator and add a sample image, then **Pick a food photo** in the app.

Photo AI needs **OpenAI + deployed Supabase functions**; until then you get **demo estimates** or manual entry.

## 6. Optional: run from Terminal

```bash
./scripts/run-simulator.sh
```

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Build fails | Issue navigator (⚠️) → send first red error |
| Signing / no devices | Switch destination to **iPhone 17 Simulator** |
| Blank simulator | Wait for build to finish; check Xcode status bar |
| Reset app | Simulator → Device → Erase All Content and Settings |
