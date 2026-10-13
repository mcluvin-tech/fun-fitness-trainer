import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { chatCompletion } from "../_shared/openai.ts";

const PROMPT_VERSION = 6;

const SYSTEM = `You are looking at a photo of food. Identify what is on the plate and estimate portions. You are NOT the nutrition database — the app will calculate calories and macros from your line items.

Return ONLY valid JSON:
{
  "label_detected": boolean,
  "items": string[],
  "line_items": [
    {
      "name": string,
      "quantity": number,
      "unit": "oz" | "g" | "cup" | "tbsp" | "tsp" | "ml" | "fl oz" | "slice" | "piece" | "serving",
      "preparation": "raw" | "cooked" | "unknown",
      "confidence": number,
      "calories": number,
      "protein_g": number,
      "carbs_g": number,
      "fat_g": number
    }
  ],
  "calories": number,
  "protein_g": number,
  "carbs_g": number,
  "fat_g": number,
  "confidence": number,
  "overall_confidence": number,
  "assumptions": string[]
}

Top-level calories / protein_g / carbs_g / fat_g are your own rough guess for debugging only. Prefer honest portions over fake precision.

If ANY nutrition label, calories line, kcal, or Supplement Facts is visible:
- Set label_detected=true.
- Transcribe the EXACT printed per-serving Calories, Protein (g), Total Carbohydrate (g), Total Fat (g) into the top-level fields.
- 0-calorie and 5-calorie products are real. Do NOT replace a printed 5 with a typical-food guess.
- "<5" or "less than 5" calories → 5.
- 0g protein / carbs / fat is valid when that is what the label shows.
- Use gram amounts, never Daily Value percentages.
- Use the serving size printed on the label unless the user hint says they ate more/less.
- Put the product name in items when the package shows one.

If there is no readable label (a plate, bowl, restaurant dish, homemade food):
- Set label_detected=false.
- One line_items row per distinct visible food, with quantity and unit.
- Meat and fish: estimate ounces or grams; set preparation to cooked or raw when it matters.
- Rice, grains, yogurt: estimate cups.
- Include oil, butter, sauce, cheese, or dressing as its OWN line item ONLY when you can see it or the user hint names it.
- If cooking fat is possible but not visible, mention it in assumptions. Do NOT invent a 1 tbsp oil line item and do NOT silently add 119 calories.
- Lower overall_confidence when portions are guessed.
- If it is a known restaurant item, name it clearly so the app can match published nutrition.

Never give medical advice.`;

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { image_base64, user_hint, ocr_text } = await req.json();
    if (!image_base64) {
      return jsonResponse({ error: "image_base64 required" }, 400);
    }

    const hint = user_hint ? `\nUser hint: ${user_hint}` : "";
    const ocr = typeof ocr_text === "string" && ocr_text.trim()
      ? `\nOn-device OCR (may be messy; trust the photo if they disagree):\n${ocr_text.trim().slice(0, 2500)}`
      : "";

    const content = await chatCompletion(
      [
        { role: "system", content: SYSTEM },
        {
          role: "user",
          content: [
            {
              type: "text",
              text: `Look at this photo and return nutrition JSON.${hint}${ocr}\nIf a label is readable, copy the printed numbers exactly. If it is a meal with no label, return line_items with foods, quantities, and units. Do not treat your calorie guess as authoritative. prompt_version=${PROMPT_VERSION}`,
            },
            {
              type: "image_url",
              image_url: {
                url: image_base64.startsWith("data:")
                  ? image_base64
                  : `data:image/jpeg;base64,${image_base64}`,
                detail: "high",
              },
            },
          ],
        },
      ],
      { model: "gpt-4o", json: true, temperature: 0, maxTokens: 800 },
    );

    const parsed = JSON.parse(content);
    const num = (value: unknown, fallback = 0): number => {
      if (typeof value === "number" && Number.isFinite(value)) return value;
      const n = parseFloat(String(value ?? "").replace(/[^\d.-]/g, ""));
      return Number.isFinite(n) ? n : fallback;
    };
    parsed.calories = Math.max(0, num(parsed.calories));
    parsed.protein_g = Math.max(0, num(parsed.protein_g));
    parsed.carbs_g = Math.max(0, num(parsed.carbs_g));
    parsed.fat_g = Math.max(0, num(parsed.fat_g));
    parsed.label_detected = Boolean(parsed.label_detected);
    if (!Array.isArray(parsed.items) || parsed.items.length === 0) {
      parsed.items = Array.isArray(parsed.line_items)
        ? parsed.line_items.map((item: { name?: string }) => item?.name).filter(Boolean)
        : ["Meal"];
      if (!parsed.items.length) parsed.items = ["Meal"];
    }
    if (!Array.isArray(parsed.line_items)) parsed.line_items = [];
    parsed.line_items = parsed.line_items.map((item: Record<string, unknown>) => ({
      ...item,
      calories: Math.max(0, num(item.calories)),
      protein_g: Math.max(0, num(item.protein_g)),
      carbs_g: Math.max(0, num(item.carbs_g)),
      fat_g: Math.max(0, num(item.fat_g)),
      quantity: item.quantity == null ? undefined : Math.max(0, num(item.quantity)),
    }));
    if (!Array.isArray(parsed.assumptions)) parsed.assumptions = [];
    parsed.overall_confidence = Math.min(1, Math.max(0, num(parsed.overall_confidence ?? parsed.confidence, 0.5)));
    parsed.confidence = parsed.overall_confidence;
    return jsonResponse(parsed);
  } catch (e) {
    console.error(e);
    return jsonResponse(
      { error: e instanceof Error ? e.message : "Unknown error" },
      500,
    );
  }
});
