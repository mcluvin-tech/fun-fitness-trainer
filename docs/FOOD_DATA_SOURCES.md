# Food nutrition data sources

## Tracking methodology

`MacroTrackingEngine` is the source of truth for portion math, daily totals, remaining macros, and display rounding.

| Rule | Behavior |
|------|----------|
| Source priority | User label / typed macros → restaurant or manufacturer → database match → USDA staple → generic estimate |
| Quantity | Convert consumed amount into the reference unit, then `multiplier = consumed / reference` |
| Official calories | Keep labeled/database calories. Do **not** replace them with 4/4/9 Atwater math |
| Raw vs cooked | Not interchangeable. Unspecified chicken ounces assume cooked and are marked medium confidence |
| Daily totals | Sum of stored meal values. Previous foods are not recalculated unless the user edits them |
| Remaining | `target − consumed` (negative means over) |
| Percent of target | Uncapped (204g / 185g = 110%) |
| Rounding | Full precision internally; nearest kcal / gram on display only |
| Confidence | High = label/manufacturer/user; medium = USDA/database; low = visual or generic estimate |

## What the app uses today

| Source | When | Confidence |
|--------|------|------------|
| **User-typed macros** | Manual log / confirmed label values | High |
| **On-device barcode** → **Open Food Facts** | Photo contains a barcode, or Scan barcode | High |
| **On-device Nutrition Facts OCR** | Photo shows a nutrition label panel | High |
| **Restaurant / brand staples** | Big Mac, Dave's bread, Fairlife, etc. | High |
| **Open Food Facts** name search | Voice/text logging (background) | Medium |
| **USDA-style staples** (`StapleNutritionDatabase`) | Eggs, cooked chicken per 100g, banana, butter, oils, plant milks | Medium |
| **GPT** (`analyze-food`, `trainer-chat`) | Plate photos / chat when backend is configured | Low until reconciled against staples |

### Quantity / portion rules (critical)

Macros are stored as **totals for the logged portion**, with quantity + unit on the meal.

- `6 oz cooked chicken` → 170.1g / 100g × USDA cooked breast (165 kcal, 31g protein) ≈ **281 kcal / 53g protein**.
- Weight ounces (chicken) and fluid ounces (milk) are not interchangeable.
- GPT `MEAL_JSON` is reconciled on insert for known staples so `"3 Eggs"` cannot save as one egg.
- Natural-language lists split on commas, and, plus, and `with` so butter/sauces are not dropped.
- Dashboard **does not** rewrite stored macros on appear (except a one-time plant-milk ×ounce corruption repair).

### Photo logging order

1. Detect barcode on-device → OFF product lookup (small request; no AI upload)
2. OCR Nutrition Facts on-device (works offline / on flaky cellular)
3. Cloud `analyze-food` with a compressed JPEG (~250KB). Vision returns **foods + portions** (`line_items`). The app calculates macros from staples / labels. GPT's own calorie guess is kept only as a debug fallback.
4. Offline estimate so you can still Save while waiting

Photo saves go through the same `MealLogging.insert` path as voice/text. Bare `"chicken"` is never 1 count against a 100g reference — it uses an assumed 6 oz cooked portion and records that assumption.

Voice logging: Larry replies first (GPT or local estimate). **Open Food Facts name search** may replace a single-item estimate with label data. Quantity corrections ("actually that was 8 oz, not 6") update the existing row.

## Open Food Facts

- Barcode: `GET /api/v2/product/{code}` (12s timeout on cellular-friendly paths)
- Name search: legacy `GET /cgi/search.pl?search_terms=...&json=1`
- Parsing prefers `energy-kcal_serving` / `*_serving`; otherwise scales from `*_100g`

The app does **not** query USDA FoodData Central live; common foods use embedded USDA-style values.

## Staple reference values

| Food | Reference | Notes |
|------|-----------|--------|
| Large egg | 72 kcal / egg | USDA |
| Dave's Killer Bread 21 Whole Grains | **110** kcal / slice | Label. Barcode `013764005043` |
| Dave's Thin-Sliced | 60 kcal / slice | Only when the user says "thin" |
| Cooked chicken breast | 165 kcal / 31g protein per 100g | USDA; 6 oz ≈ 280 kcal / 53g |
| Raw chicken breast | 120 kcal / 22.5g protein per 100g | USDA |
| Banana, medium | 105 kcal | USDA |
| Butter | 102 kcal / tbsp | USDA |
| Olive oil | 119 kcal / tbsp | USDA |
| Big Mac | 590 kcal | McDonald's published |

Branded staples are never replaced by a generic equivalent.

## USDA FoodData Central (future)

Suggested merge order if you add a live USDA API later:

`User label` → `barcode / manufacturer` → `restaurant` → `USDA branded search` → `OFF text search` → `local USDA staples` → `generic estimate`

## Deploy note

OFF lookups and cloud AI need network. On-device barcode + Nutrition Facts OCR work without uploading the photo. Larry cloud replies still need `./scripts/deploy-supabase.sh` with `OPENAI_API_KEY`.
