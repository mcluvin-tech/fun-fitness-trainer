const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");

export function requireOpenAI(): string {
  if (!OPENAI_API_KEY) {
    throw new Error("OPENAI_API_KEY is not configured");
  }
  return OPENAI_API_KEY;
}

export async function chatCompletion(
  messages: { role: string; content: string | unknown[] }[],
  options: { model?: string; json?: boolean; temperature?: number; maxTokens?: number } = {},
): Promise<string> {
  const apiKey = requireOpenAI();
  const body: Record<string, unknown> = {
    model: options.model ?? "gpt-4o-mini",
    messages,
    temperature: options.temperature ?? 0.8,
  };
  if (options.json) {
    body.response_format = { type: "json_object" };
  }
  if (options.maxTokens) {
    body.max_tokens = options.maxTokens;
  }

  const res = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const err = await res.text();
    throw new Error(`OpenAI error: ${res.status} ${err}`);
  }

  const data = await res.json();
  return data.choices[0].message.content as string;
}
