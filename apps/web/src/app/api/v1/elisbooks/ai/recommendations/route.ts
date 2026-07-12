import { getAuth, hasRole } from "@/server/auth/auth";
import { ok, fail, unauthorized, forbidden } from "@/server/http/respond";
import { hasOpenAI, openaiChat, parseJsonLoose } from "@/server/elisbooks/openai";

// Personalisierte Buchempfehlungen (OpenAI) auf Basis der Bibliothek. Ohne OPENAI_API_KEY → 501.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 60;

const TIMEFRAME_DE: Record<string, string> = {
  "6-months": "den letzten 6 Monaten", "12-months": "dem letzten Jahr",
  "24-months": "den letzten 2 Jahren", "all-time": "allen Zeiten",
};

export async function POST(req: Request): Promise<Response> {
  const auth = getAuth(req);
  if (!hasRole(auth, "agent")) return auth ? forbidden() : unauthorized();
  if (!hasOpenAI()) return fail("not_configured", "KI-Empfehlungen benötigen OPENAI_API_KEY im Backend (Coolify).", 501);

  let body: Record<string, unknown>;
  try { body = (await req.json()) as Record<string, unknown>; } catch { return fail("bad_json", "Ungültiger JSON-Body.", 400); }
  const count = Math.min(Math.max(Number(body.count ?? 5) || 5, 1), 10);
  const timeframe = TIMEFRAME_DE[String(body.timeframe ?? "12-months")] ?? "dem letzten Jahr";
  const custom = String(body.customPrompt ?? "").slice(0, 500);
  const lib = Array.isArray(body.books) ? (body.books as Record<string, unknown>[]) : [];
  if (!lib.length) return fail("empty_library", "Bibliothek ist leer.", 400);

  const sample = lib.slice(0, 60).map((b) => {
    const authors = Array.isArray(b.authors) ? (b.authors as unknown[]).join(", ") : String(b.authors ?? "");
    const cats = Array.isArray(b.categories) ? (b.categories as unknown[]).join(", ") : "";
    return `- ${String(b.title ?? "")}${authors ? ` (${authors})` : ""}${cats ? ` [${cats}]` : ""}`;
  }).join("\n");

  const system = "Du bist ein Buchempfehlungs-Experte. Antworte NUR mit JSON, auf Deutsch.";
  const prompt = `Basierend auf dieser Bibliothek empfiehl ${count} NEUE Bücher (nicht in der Liste) aus ${timeframe}.` +
    (custom ? ` Zusätzliche Anforderung: ${custom}.` : "") +
    `\n\nBibliothek:\n${sample}\n\n` +
    `Gib JSON zurück: {"recommendations":[{"title":"","authors":["",""],"isbn":"","publisher":"","description":"","categories":["",""],"publishedDate":"","reason":"kurze Begründung auf Deutsch"}]}.`;
  try {
    const text = await openaiChat(prompt, { system, model: "gpt-4o", maxTokens: 2000 });
    const parsed = parseJsonLoose<{ recommendations?: unknown[] }>(text);
    return ok({ recommendations: parsed?.recommendations ?? [] });
  } catch (e) {
    return fail("openai_error", "Empfehlungen fehlgeschlagen.", 502, { detail: String((e as Error)?.message ?? e) });
  }
}
