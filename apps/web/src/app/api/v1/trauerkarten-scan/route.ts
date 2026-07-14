import { getAuth, hasRole } from "@/server/auth/auth";
import { ok, fail, unauthorized, forbidden } from "@/server/http/respond";
import { hasOpenAI, openaiChat, parseJsonLoose } from "@/server/elisbooks/openai";

// Trauerkarten-KI-Scan: Foto einer Trauerkarte → { name, trauertext, geldbetrag } via OpenAI Vision
// (gpt-4o). Prompt 1:1 aus der Original-App (Lovable memories-app / Edge Function
// extract-text-from-image). Token-gated: ohne OPENAI_API_KEY → 501 (iOS zeigt „nicht verfügbar").
// Eigenes Segment `trauerkarten-scan`, damit es NICHT die generische /trauerkarten/[id]-CRUD-Route verdeckt.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 60;

const SYSTEM = `Du bist ein Experte für die Texterkennung von deutschen Trauerkarten und Handschriften.

WICHTIGE ANWEISUNGEN:
- Analysiere das Bild sehr sorgfältig und erkenne auch unleserliche oder schwer lesbare Handschrift
- Achte auf deutsche Namen, Familiennamen und typische Beileidswünsche
- Erkenne handgeschriebene Geldbeträge auch wenn sie unleserlich sind (schätze wenn nötig)
- Falls Text auf Russisch ist, übersetze ins Deutsche
- Antworte IMMER mit reinem JSON ohne Code-Blöcke oder Markdown

Extrahiere folgende Informationen:
1. Den Namen des Absenders/der Familie (auch bei unleserlicher Handschrift versuchen)
2. Den Trauertext/Beileidswunsch (vollständig, auch handgeschrieben)
3. Einen Geldbetrag falls sichtbar (auch handgeschriebene Zahlen erkennen)
4. Die erkannte Sprache

ANTWORT-FORMAT (reines JSON):
{
  "name": "Name oder Familie",
  "trauertext": "Der komplette Beileidswunsch",
  "trauertext_original": "Originaltext falls übersetzt",
  "sprache": "deutsch/russisch/andere",
  "geldbetrag": 50,
  "confidence": "hoch/mittel/niedrig",
  "raw_analysis": "Was genau auf dem Bild zu sehen ist"
}

Falls unleserlich: Verwende beste Schätzung. Falls kein Betrag: 0.`;

const USER = "Analysiere diese deutsche Trauerkarte sehr genau. Achte besonders auf handgeschriebene Texte und Geldbeträge. Erkenne auch unleserliche Handschrift so gut wie möglich:";

interface ScanResult {
  name?: string;
  trauertext?: string;
  trauertext_original?: string;
  sprache?: string;
  geldbetrag?: number | string;
  confidence?: string;
}

export async function POST(req: Request): Promise<Response> {
  const auth = getAuth(req);
  if (!hasRole(auth, "agent")) return auth ? forbidden() : unauthorized();
  if (!hasOpenAI()) return fail("not_configured", "KI-Scan benötigt OPENAI_API_KEY im Backend (Coolify).", 501);

  let body: Record<string, unknown>;
  try { body = (await req.json()) as Record<string, unknown>; } catch { return fail("bad_json", "Ungültiger JSON-Body.", 400); }
  const image = String(body.image ?? "");
  if (!image.startsWith("data:")) return fail("no_image", "Feld 'image' (data-URL) erforderlich.", 400);

  try {
    const text = await openaiChat(USER, { imageDataUrl: image, system: SYSTEM, model: "gpt-4o", maxTokens: 1200 });
    const parsed = parseJsonLoose<ScanResult>(text);
    if (!parsed) return fail("parse_error", "Antwort konnte nicht gelesen werden.", 502);
    const betrag = typeof parsed.geldbetrag === "string" ? parseFloat(parsed.geldbetrag.replace(",", ".")) : parsed.geldbetrag;
    return ok({
      name: (parsed.name ?? "").trim(),
      trauertext: (parsed.trauertext ?? "").trim(),
      trauertext_original: (parsed.trauertext_original ?? "").trim(),
      sprache: parsed.sprache ?? "deutsch",
      geldbetrag: Number.isFinite(betrag) ? Math.max(0, betrag as number) : 0,
      confidence: parsed.confidence ?? "niedrig",
    });
  } catch (e) {
    return fail("openai_error", "KI-Analyse fehlgeschlagen.", 502, { detail: String((e as Error)?.message ?? e) });
  }
}
