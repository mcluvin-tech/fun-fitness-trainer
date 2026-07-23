# Food nutrition data sources

## What the app uses today

| Source | When | Accuracy |
|--------|------|----------|
| **Open Food Facts** (OFF) | Barcode scan; **voice/text name search** (new) | Label-based for packaged foods; crowd-sourced |
| **On-device rules** (`FoodAnalysisService`) | OFF miss, offline mode | Hand-tuned / USDA-style defaults for a few staples |
| **GPT** (`trainer-chat`, `analyze-food`) | Supabase + OpenAI deployed | Model estimate — not a live database lookup |

Voice logging flow: Larry replies first (GPT or instant local estimate). **Open Food Facts name search runs in the background** (~2.5s cap) when the meal is saved — local rules if OFF misses.

## Open Food Facts

- Barcode: `GET /api/v2/product/{code}`
- Name search: legacy `GET /cgi/search.pl?search_terms=...&json=1` (documented as legacy; best available full-text search today)
- No API key; set a descriptive `User-Agent` / contact per [OFF API terms](https://openfoodfacts.github.io/openfoodfacts-server/api/)

Many OFF products trace to brand labels; some entries include USDA-related metadata in the database, but the app does **not** query USDA directly.

## USDA FoodData Central (future / dataset)

To add **official USDA** branded or generic foods:

1. **API** (recommended for search-by-name later)  
   - Register at [FoodData Central API guide](https://fdc.nal.usda.gov/api-guide.html)  
   - Endpoints: `/foods/search`, `/food/{fdcId}`  
   - Returns Foundation, SR Legacy, Branded, etc.

2. **Bulk download** (for offline dataset / Supabase table)  
   - [FoodData Central downloads](https://fdc.nal.usda.gov/download-datasets.html)  
   - Import `Branded Food` or `Foundation Foods` JSON into Postgres (e.g. `usda_foods` with `description`, `fdc_id`, nutrients per 100g / per serving)  
   - App queries your API instead of (or after) OFF

3. **Suggested merge order** (if you add USDA later)  
   `Barcode OFF` → `USDA branded search` → `OFF text search` → `local rules` → `GPT`

## Deploy note

OFF and USDA lookups require network on the device. Larry cloud replies still need `./scripts/deploy-supabase.sh` with `OPENAI_API_KEY`.
