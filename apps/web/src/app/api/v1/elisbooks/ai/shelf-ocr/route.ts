import { getAuth, hasRole } from "@/server/auth/auth";
import { ok, fail, unauthorized, forbidden } from "@/server/http/respond";
import { hasOpenAI, openaiChat, parseJsonLoose } from "@/server/elisbooks/openai";

// Regal-Foto → erkannte Buchtitel (OpenAI Vision). Ohne OPENAI_API_KEY → 501.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 60;

export async function POST(req: Request): Promise<Response> {
  const auth = getAuth(req);
  if (!hasRole(auth, "agent")) return auth ? forbidden() : unauthorized();
  if (!hasOpenAI()) return fail("not_configured", "Regal-Scan benötigt OPENAI_API_KEY im Backend (Coolify).", 501);

  let body: Record<string, unknown>;
  try { body = (await req.json()) as Record<string, unknown>; } catch { return fail("bad_json", "Ungültiger JSON-Body.", 400); }
  const image = String(body.image ?? "");
  if (!image.startsWith("data:")) return fail("no_image", "Feld 'image' (data-URL) erforderlich.", 400);

  const system = "Du erkennst Buchrücken/Buchtitel auf einem Foto eines Bücherregals. Antworte NUR mit JSON.";
  const prompt = "Analysiere das Foto und liste die erkennbaren Buchtitel. Gib JSON zurück: {\"detectedBooks\":[{\"title\":\"<Titel ggf. mit Autor>\",\"confidence\":0.0-1.0}]}. Nur Bücher mit confidence>=0.5, maximal 25.";
  try {
    const text = await openaiChat(prompt, { imageDataUrl: image, system, model: "gpt-4o", maxTokens: 1500 });
    const parsed = parseJsonLoose<{ detectedBooks?: { title?: string; confidence?: number }[] }>(text);
    const books = (parsed?.detectedBooks ?? [])
      .filter((b) => b.title)
      .map((b, i) => ({ id: `d${i}`, title: String(b.title), confidence: typeof b.confidence === "number" ? b.confidence : 0.7, status: "pending" }));
    return ok({ detectedBooks: books, count: books.length });
  } catch (e) {
    return fail("openai_error", "Analyse fehlgeschlagen.", 502, { detail: String((e as Error)?.message ?? e) });
  }
}
