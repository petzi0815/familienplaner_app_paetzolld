import { getAuth, hasRole } from "@/server/auth/auth";
import { ok, fail, unauthorized, forbidden } from "@/server/http/respond";
import { hasOpenAI, openaiChat, parseJsonLoose } from "@/server/elisbooks/openai";

// KI-Metadaten-Ergänzung: füllt fehlende Beschreibung/Kategorien (Cover-Vorschlag als Text). Ohne Key → 501.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 60;

export async function POST(req: Request): Promise<Response> {
  const auth = getAuth(req);
  if (!hasRole(auth, "agent")) return auth ? forbidden() : unauthorized();
  if (!hasOpenAI()) return fail("not_configured", "KI-Ergänzung benötigt OPENAI_API_KEY im Backend (Coolify).", 501);

  let body: Record<string, unknown>;
  try { body = (await req.json()) as Record<string, unknown>; } catch { return fail("bad_json", "Ungültiger JSON-Body.", 400); }
  const books = Array.isArray(body.books) ? (body.books as Record<string, unknown>[]).slice(0, 20) : [];
  if (!books.length) return fail("empty", "Keine Bücher angegeben.", 400);

  const list = books.map((b) => JSON.stringify({ id: b.id, title: b.title, authors: b.authors, isbn: b.isbn })).join("\n");
  const system = "Du ergänzt fehlende Buch-Metadaten (Deutsch): Beschreibung (2-4 Sätze) und passende Kategorien (max 4). Antworte NUR mit JSON.";
  const prompt = `Ergänze für diese Bücher nur FEHLENDE Beschreibung/Kategorien (keine Erfindungen bei Unsicherheit):\n${list}\n\n` +
    `Gib JSON zurück: {"enhancements":[{"bookId":"<id>","originalTitle":"","suggestions":{"description":"","categories":["",""]},"confidence":0-100}]}.`;
  try {
    const text = await openaiChat(prompt, { system, model: "gpt-4o", maxTokens: 2000 });
    const parsed = parseJsonLoose<{ enhancements?: unknown[] }>(text);
    return ok({ enhancements: parsed?.enhancements ?? [] });
  } catch (e) {
    return fail("openai_error", "Ergänzung fehlgeschlagen.", 502, { detail: String((e as Error)?.message ?? e) });
  }
}
