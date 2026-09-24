# Food nutrition data sources

## What the app uses today

| Source | When | Accuracy |
|--------|------|----------|
| **Open Food Facts** (OFF) | Barcode scan; **voice/text name search** (new) | Label-based for packaged foods; crowd-sourced |
| **On-device rules** (`FoodAnalysisService`) | OFF miss, offline mode | Hand-tuned / USDA-style defaults for a few staples |
| **GPT** (`trainer-chat`, `analyze-food`) | Supabase + OpenAI deployed | Model estimate — not a live database lookup |

Voice logging flow: Larry replies first (GPT or instant local estimate). **Open Food Facts name search starts when the message is sent** so it overlaps the reply. Each food in the meal is matched on its own. A hit replaces that row only when the calories are in a plausible range; otherwise the estimate stays.

## Open Food Facts

- Barcode: `GET /api/v2/product/{code}` (about 10s, one retry). Successful lookups are cached on device. UPC-A is requested as EAN-13; UPC-E is expanded if the 8-digit code is not in OFF.
- Name search: legacy `GET /cgi/search.pl?search_terms=...&json=1` (documented as legacy; best available full-text search today). About 4s beside chat, 8s on the manual-entry form, one retry on a 5xx or timeout.
- Serving math uses `*_serving` keys when they exist, otherwise `*_100g` scaled by `serving_quantity`. Bare `energy-kcal` / `proteins` match the per-100 g figures and are not treated as a serving.
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

OFF and USDA lookups require network on the device. Larry's on-device diet answers (including gains) work with no key. Cloud phrasing that does not match those local detectors still needs `./scripts/deploy-supabase.sh` with `OPENAI_API_KEY` so `trainer-chat` prompt version 17 is what production runs. Photo estimates still need the `analyze-food` function and the same key.
