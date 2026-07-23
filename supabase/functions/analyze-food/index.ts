import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { chatCompletion } from "../_shared/openai.ts";

const PROMPT_VERSION = 4;

const SYSTEM = `You are a food nutrition analyst. Return ONLY valid JSON with this shape:
{
  "calories": number,
  "protein_g": number,
  "carbs_g": number,
  "fat_g": number,
  "items": string[],
  "confidence": number between 0 and 1,
  "assumptions": string[],
  "label_detected": boolean
}

Nutrition Facts labels (highest priority):
- If a Nutrition Facts / nutrition label panel is visible and readable, set label_detected=true.
- Transcribe the EXACT per-serving values printed on the label: Calories, Protein, Total Carbohydrate, Total Fat.
- Use gram amounts (e.g. "Protein 33g"), never Daily Value percentages.
- Do NOT guess typical product-category values when label text is readable.
- Cholesterol (mg), sodium (mg), and DV% are NOT protein — read the Protein line only.
- Use the serving size stated at the top of the label (e.g. "1 carton", "1 bottle") unless the user hint says otherwise.
- If only part of the label is visible, read what you can and note gaps in assumptions.

When no readable label:
- Estimate reasonable portions for visible food. Set label_detected=false.
- Lower confidence and list assumptions.

Never give medical advice.`;

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { image_base64, user_hint } = await req.json();
    if (!image_base64) {
      return jsonResponse({ error: "image_base64 required" }, 400);
    }

    const hint = user_hint ? ` User hint: ${user_hint}` : "";
    const content = await chatCompletion(
      [
        { role: "system", content: SYSTEM },
        {
          role: "user",
          content: [
            {
              type: "text",
              text: `Analyze this food image.${hint} If a nutrition facts label is visible, transcribe exact label values — do not estimate. prompt_version=${PROMPT_VERSION}`,
            },
            {
              type: "image_url",
              image_url: {
                url: image_base64.startsWith("data:")
                  ? image_base64
                  : `data:image/jpeg;base64,${image_base64}`,
                detail: "auto",
              },
            },
          ],
        },
      ],
      { model: "gpt-4o", json: true, temperature: 0.1 },
    );

    const parsed = JSON.parse(content);
    return jsonResponse(parsed);
  } catch (e) {
    console.error(e);
    return jsonResponse(
      { error: e instanceof Error ? e.message : "Unknown error" },
      500,
    );
  }
});
