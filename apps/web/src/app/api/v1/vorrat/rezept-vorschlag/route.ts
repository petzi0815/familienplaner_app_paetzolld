import { getDb } from "@/server/db/connection";
import { getAuth, hasRole } from "@/server/auth/auth";
import { unauthorized, forbidden, fail, ok } from "@/server/http/respond";
import { hasOpenAI, openaiChat, parseJsonLoose } from "@/server/elisbooks/openai";

// KI-Rezeptvorschlag (OpenAI) aus den bald ablaufenden Lebensmitteln — One-Click, verbraucht gezielt
// die zuerst ablaufenden Zutaten. Ohne OPENAI_API_KEY → 501 (die App behandelt das sauber).
export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 60;

interface Rezept {
  titel: string;
  beschreibung?: string;
  portionen?: number;
  dauer_minuten?: number;
  verwendete_zutaten?: string[];
  zutaten?: { menge?: string; zutat?: string }[];
  schritte?: string[];
  tipp?: string;
}

export async function POST(req: Request): Promise<Response> {
  const auth = getAuth(req);
  if (!hasRole(auth, "agent")) return auth ? forbidden() : unauthorized();
  if (!hasOpenAI()) return fail("not_configured", "KI-Rezepte benötigen OPENAI_API_KEY im Backend (Coolify).", 501);

  const days = Math.max(1, Math.min(Number(new URL(req.url).searchParams.get("days") ?? "14") || 14, 60));
  const db = getDb();
  const rows = db.prepare(
    "SELECT name, menge, mhd, kategorie FROM vorrat_lebensmittel WHERE mhd IS NOT NULL AND mhd<>'' " +
    "AND mhd<=date('now','+' || ? || ' days') AND COALESCE(status,'')<>'verbraucht' ORDER BY mhd ASC LIMIT 20",
  ).all(days) as { name: string; menge?: string; mhd: string; kategorie?: string }[];
  if (!rows.length) return fail("no_items", "Keine bald ablaufenden Lebensmittel gefunden.", 422);

  const liste = rows.map((r) => `- ${r.name}${r.menge ? ` (${r.menge})` : ""} — MHD ${r.mhd}`).join("\n");

  const system =
    "Du bist ein erfahrener, praktischer Familienkoch. Erstelle EIN vollständiges, alltagstaugliches Rezept auf " +
    "Deutsch, das gezielt die genannten bald ablaufenden Zutaten verbraucht — priorisiere die zuerst ablaufenden und " +
    "nutze möglichst viele davon. Du darfst übliche Vorratsstandards als vorhanden voraussetzen (Salz, Pfeffer, Zucker, " +
    "Öl, Butter, Zwiebeln, Knoblauch, Mehl, Eier, Milch, gängige Gewürze, Nudeln, Reis, Brühe) und im Rezept verwenden, " +
    "ohne dass sie gekauft werden müssen. Das Rezept muss vollständig, realistisch und nachkochbar sein (echte Mengen, " +
    "klare Schritte). Antworte AUSSCHLIESSLICH als JSON, kein weiterer Text.";

  const user =
    `Bald ablaufende Zutaten (zuerst ablaufende oben):\n${liste}\n\n` +
    "Erstelle ein vollständiges Rezept, das möglichst viele dieser ablaufenden Zutaten verbraucht. " +
    "Gib es als JSON in genau diesem Schema zurück:\n" +
    '{\n' +
    '  "titel": string,\n' +
    '  "beschreibung": string (1-2 Sätze),\n' +
    '  "portionen": number,\n' +
    '  "dauer_minuten": number,\n' +
    '  "verwendete_zutaten": string[] (welche der oben genannten ablaufenden Zutaten verwendet werden),\n' +
    '  "zutaten": [{ "menge": string, "zutat": string }] (vollständige Zutatenliste inkl. Standardzutaten),\n' +
    '  "schritte": string[] (klare Schritt-für-Schritt-Anleitung),\n' +
    '  "tipp": string (kurzer, praktischer Tipp)\n' +
    '}';

  let text: string;
  try {
    text = await openaiChat(user, { system, json: true, temperature: 0.7, maxTokens: 1800, model: "gpt-4o" });
  } catch (e) {
    return fail("openai_error", "Rezept-Generierung fehlgeschlagen.", 502, { detail: String((e as Error).message).slice(0, 200) });
  }
  const rezept = parseJsonLoose<Rezept>(text);
  if (!rezept || !rezept.titel) return fail("parse_error", "Die KI-Antwort konnte nicht gelesen werden.", 502);

  try {
    db.prepare("INSERT INTO event_log (actor, action, domain, entity_id) VALUES (?,?,?,?)")
      .run(auth.actor, "rezept_generate", "vorratskammer", String(rows.length));
  } catch { /* audit best effort */ }

  return ok({ rezept, verwendet: rows.map((r) => r.name), model: "gpt-4o" });
}
