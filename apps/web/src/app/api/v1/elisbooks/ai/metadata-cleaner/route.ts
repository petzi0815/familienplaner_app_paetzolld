import { getAuth, hasRole } from "@/server/auth/auth";
import { ok, fail, unauthorized, forbidden } from "@/server/http/respond";
import { hasOpenAI, openaiChat, parseJsonLoose } from "@/server/elisbooks/openai";

// KI-Metadaten-Bereinigung: schlägt Feld-Korrekturen für Bücher vor. Ohne OPENAI_API_KEY → 501.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 60;

export async function POST(req: Request): Promise<Response> {
  const auth = getAuth(req);
  if (!hasRole(auth, "agent")) return auth ? forbidden() : unauthorized();
  if (!hasOpenAI()) return fail("not_configured", "KI-Bereinigung benötigt OPENAI_API_KEY im Backend (Coolify).", 501);

  let body: Record<string, unknown>;
  try { body = (await req.json()) as Record<string, unknown>; } catch { return fail("bad_json", "Ungültiger JSON-Body.", 400); }
  const books = Array.isArray(body.books) ? (body.books as Record<string, unknown>[]).slice(0, 20) : [];
  if (!books.length) return fail("empty", "Keine Bücher angegeben.", 400);

  const list = books.map((b) => JSON.stringify({
    id: b.id, title: b.title, authors: b.authors, publisher: b.publisher,
    description: b.description, categories: b.categories, isbn: b.isbn,
    pageCount: b.pageCount ?? b.page_count, publishedDate: b.publishedDate ?? b.published_date,
  })).join("\n");

  const system = "Du bereinigst Buch-Metadaten (Deutsch). Korrigiere Tippfehler, falsche Verlage, fehlende Autoren, unsaubere Kategorien. Antworte NUR mit JSON.";
  const prompt = `Prüfe diese Bücher und schlage NUR sinnvolle Korrekturen vor (keine erfundenen Daten).\n${list}\n\n` +
    `Gib JSON zurück: {"improvements":[{"bookId":"<id>","originalTitle":"","changes":[{"field":"authors|publisher|description|categories|page_count|published_date|isbn","oldValue":"","newValue":"","confidence":0-100,"reasoning":"kurz, Deutsch"}]}]}. Nur Bücher mit Änderungen.`;
  try {
    const text = await openaiChat(prompt, { system, model: "gpt-4o", maxTokens: 2500 });
    const parsed = parseJsonLoose<{ improvements?: unknown[] }>(text);
    return ok({ improvements: parsed?.improvements ?? [] });
  } catch (e) {
    return fail("openai_error", "Bereinigung fehlgeschlagen.", 502, { detail: String((e as Error)?.message ?? e) });
  }
}
