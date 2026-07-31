import { config } from "@/server/config";

// Dünner Perplexity-Client (fetch, kein SDK) für die Wein-Recherche — bewusst ein ZWEITER Anbieter
// neben OpenAI: „sonar-pro" durchsucht bei jeder Anfrage LIVE das Web (aktuelle Händlerpreise,
// Weingut, Lage, Auszeichnungen). Das kann ein reines Sprachmodell nicht. Das Antwortformat ist
// OpenAI-kompatibel, die Quellenangaben liefert Perplexity zusätzlich neben dem Text.
// Token-gated: ohne PERPLEXITY_API_KEY läuft die KI-Kette ohne Recherche weiter (Teilergebnis +
// Klartext-Hinweis) — sie scheitert nie hart.

export function hasPerplexity(): boolean { return !!config.perplexityApiKey; }

export interface PerplexityAnswer { text: string; citations: string[] }

interface AskOpts { model?: string; system?: string; maxTokens?: number }

/** Live-Websuche dauert deutlich länger als ein normaler Chat-Call. */
const TIMEOUT_MS = 45000;

interface PerplexityBody {
  choices?: { message?: { content?: string; citations?: unknown[] } }[];
  citations?: unknown[];
  search_results?: unknown[];
}

/**
 * Sammelt Quellen-URLs aus allen Formen, in denen Perplexity sie liefert: `citations` als reine
 * String-Liste (klassisch), `search_results[].url` (neuer) oder Objekte mit `url`. Dedupliziert.
 */
function collectUrls(...groups: unknown[]): string[] {
  const out: string[] = [];
  for (const group of groups) {
    if (!Array.isArray(group)) continue;
    for (const entry of group) {
      const url =
        typeof entry === "string" ? entry
          : entry && typeof entry === "object" ? String((entry as Record<string, unknown>).url ?? "")
            : "";
      if (/^https?:\/\//i.test(url) && !out.includes(url)) out.push(url);
    }
  }
  return out;
}

/** Fragt Perplexity und gibt Antworttext + gefundene Quellen zurück. Wirft bei Netz-/HTTP-Fehler. */
export async function perplexityAsk(prompt: string, opts: AskOpts = {}): Promise<PerplexityAnswer> {
  const messages: unknown[] = [];
  if (opts.system) messages.push({ role: "system", content: opts.system });
  messages.push({ role: "user", content: prompt });

  const r = await fetch("https://api.perplexity.ai/chat/completions", {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${config.perplexityApiKey}` },
    body: JSON.stringify({
      model: opts.model ?? "sonar-pro",
      messages,
      max_tokens: opts.maxTokens ?? 1200,
      temperature: 0.2,
    }),
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  if (!r.ok) throw new Error(`Perplexity ${r.status}: ${(await r.text()).slice(0, 200)}`);
  const data = (await r.json()) as PerplexityBody;
  const message = data.choices?.[0]?.message;
  return {
    text: message?.content ?? "",
    citations: collectUrls(data.citations, data.search_results, message?.citations),
  };
}
