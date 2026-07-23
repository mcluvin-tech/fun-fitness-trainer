/** Extract PREFIX_JSON: {...} blocks with nested objects/arrays (e.g. line_items). */
export function extractStructuredBlock(
  text: string,
  prefix: string,
): { parsed: unknown; cleaned: string } | null {
  const marker = `${prefix}:`;
  const markerIndex = text.indexOf(marker);
  if (markerIndex === -1) return null;

  const braceStart = text.indexOf("{", markerIndex + marker.length);
  if (braceStart === -1) return null;

  let depth = 0;
  let inString = false;
  let escape = false;

  for (let i = braceStart; i < text.length; i++) {
    const ch = text[i];

    if (inString) {
      if (escape) {
        escape = false;
      } else if (ch === "\\") {
        escape = true;
      } else if (ch === '"') {
        inString = false;
      }
      continue;
    }

    if (ch === '"') {
      inString = true;
    } else if (ch === "{") {
      depth++;
    } else if (ch === "}") {
      depth--;
      if (depth === 0) {
        const jsonText = text.slice(braceStart, i + 1);
        try {
          const parsed = JSON.parse(jsonText);
          const before = text.slice(0, markerIndex).trimEnd();
          const after = text.slice(i + 1).trimStart();
          const cleaned = [before, after].filter(Boolean).join("\n").trim();
          return { parsed, cleaned };
        } catch {
          return null;
        }
      }
    }
  }

  return null;
}
