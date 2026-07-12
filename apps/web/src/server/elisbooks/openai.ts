import { config } from "@/server/config";

// Dünner OpenAI-Chat-Client (fetch, kein SDK) für die ElisBooks-KI-Features. Token-gated:
// ohne OPENAI_API_KEY liefern die Routen 501 (die iOS-App behandelt das sauber).

export function hasOpenAI(): boolean { return !!config.openaiApiKey; }

interface ChatOpts { model?: string; system?: string; imageDataUrl?: string; maxTokens?: number }

/** Ruft OpenAI Chat Completions (optional mit Bild) und gibt den Text-Inhalt zurück. */
export async function openaiChat(userPrompt: string, opts: ChatOpts = {}): Promise<string> {
  const model = opts.model ?? "gpt-4o";
  const content: unknown[] = [{ type: "text", text: userPrompt }];
  if (opts.imageDataUrl) content.push({ type: "image_url", image_url: { url: opts.imageDataUrl } });
  const messages: unknown[] = [];
  if (opts.system) messages.push({ role: "system", content: opts.system });
  messages.push({ role: "user", content: opts.imageDataUrl ? content : userPrompt });

  const r = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${config.openaiApiKey}` },
    body: JSON.stringify({ model, messages, max_tokens: opts.maxTokens ?? 1500, temperature: 0.3 }),
  });
  if (!r.ok) throw new Error(`OpenAI ${r.status}: ${(await r.text()).slice(0, 200)}`);
  const data = (await r.json()) as { choices?: { message?: { content?: string } }[] };
  return data.choices?.[0]?.message?.content ?? "";
}

/** Extrahiert ein JSON-Objekt/Array aus einer LLM-Antwort (toleriert ```json-Fences). */
export function parseJsonLoose<T>(text: string): T | null {
  const fence = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  const raw = (fence ? fence[1] : text).trim();
  const start = raw.search(/[[{]/);
  if (start < 0) return null;
  try { return JSON.parse(raw.slice(start)) as T; } catch { return null; }
}
