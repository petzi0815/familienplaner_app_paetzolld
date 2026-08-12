import { getDb } from "@/server/db/connection";
import { getAuth, hasRole } from "@/server/auth/auth";
import { unauthorized, forbidden, fail, ok } from "@/server/http/respond";
import { hasOpenAI } from "@/server/elisbooks/openai";
import { enrichWine, type GetraenkeArt, type WeinPreis } from "@/server/wein/enrich";

// Einkaufs-Scan im Laden: „Kennen wir die Flasche — und wie fanden wir sie?"
// EAN (Barcode) oder Name → bekannter Wein inkl. beider Bewertungen + Schnitt.
// Unbekannt + EAN vorhanden → optional ein KI-Vorschlag (damit man ihn direkt anlegen kann);
// `?enrich=0` schaltet das ab, wenn nur die schnelle Kennen-wir-den-schon-Antwort gebraucht wird.
// Zum Vorschlag gehört dasselbe Beiwerk wie bei `/wein-scan` (`preise`, `quellen`, `confidence`,
// `hinweise`) — die App baut aus beiden Routen denselben Vorschlag und zeigt Bestpreis und
// Vertrauensgrad; ohne diese Felder wäre im Laden immer „Unsicher, bitte prüfen" zu lesen.
// Lesen reicht (readonly), weil hier nichts geschrieben wird.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 120;

interface Bewertung { owner: string; sterne: number; kommentar: string }

/**
 * Hinweis des Aufrufers auf die Getränkeart (`?art=`). Ungültige Werte werden still ignoriert — der
 * Hinweis steuert nur die Prompts der KI-Kette, erkannt wird die Art ohnehin am Etikett bzw. an den
 * Kategorien der Produktdatenbank.
 */
function leseArt(v: string | null): GetraenkeArt | undefined {
  const s = (v ?? "").trim().toLowerCase();
  return s === "wein" || s === "spirituose" ? s : undefined;
}

/** Durchschnitt der Bewertungen (auf eine Nachkommastelle), NULL wenn niemand bewertet hat. */
function schnittVon(bewertungen: Bewertung[]): number | null {
  if (!bewertungen.length) return null;
  const summe = bewertungen.reduce((acc, b) => acc + Number(b.sterne || 0), 0);
  return Math.round((summe / bewertungen.length) * 10) / 10;
}

export async function GET(req: Request): Promise<Response> {
  const auth = getAuth(req);
  if (!hasRole(auth, "readonly")) return auth ? forbidden() : unauthorized();

  const params = new URL(req.url).searchParams;
  const ean = (params.get("ean") ?? "").trim();
  const name = (params.get("name") ?? "").trim();
  const mitKi = (params.get("enrich") ?? "1") !== "0";
  const artHinweis = leseArt(params.get("art"));
  if (!ean && !name) return fail("no_input", "Parameter 'ean' oder 'name' erforderlich.", 400);

  const db = getDb();
  let wein: Record<string, unknown> | undefined;
  try {
    // Weder EAN- noch Namenssuche werden auf `art` eingegrenzt: der Barcode ist eindeutig, und im
    // Laden soll der Scan auch dann „kennen wir schon" melden, wenn die Flasche unter der anderen
    // Art erfasst wurde. Der Hinweis dient nur der KI-Kette weiter unten.
    if (ean) {
      wein = db.prepare(
        "SELECT * FROM weine WHERE TRIM(COALESCE(ean,'')) <> '' AND TRIM(ean) = ? ORDER BY id DESC LIMIT 1",
      ).get(ean) as Record<string, unknown> | undefined;
    }
    if (!wein && name) {
      // Erst exakt (case-/whitespace-unabhängig), dann unscharf über Weingut + Name.
      wein = db.prepare(
        "SELECT * FROM weine WHERE LOWER(TRIM(name)) = LOWER(?) ORDER BY id DESC LIMIT 1",
      ).get(name) as Record<string, unknown> | undefined;
      if (!wein) {
        wein = db.prepare(
          "SELECT * FROM weine WHERE INSTR(LOWER(TRIM(weingut) || ' ' || TRIM(name)), LOWER(?)) > 0 ORDER BY id DESC LIMIT 1",
        ).get(name) as Record<string, unknown> | undefined;
      }
    }
  } catch (e) {
    return fail("db_error", "Weinsuche fehlgeschlagen.", 500, { detail: String((e as Error)?.message ?? e).slice(0, 200) });
  }

  if (wein) {
    const bewertungen = db.prepare(
      "SELECT owner, sterne, kommentar FROM wein_bewertungen WHERE wein_id=? ORDER BY owner",
    ).all(wein.id) as Bewertung[];
    return ok({ known: true, wein, bewertungen, schnitt: schnittVon(bewertungen), vorschlag: null });
  }

  // Unbekannt: mit EAN können wir direkt einen Anlege-Vorschlag liefern (best effort, nie hart scheitern).
  // Das Beiwerk der Recherche gehört mit in die Antwort — es ist bereits bezahlt und die App zeigt
  // Bestpreis/Vertrauensgrad direkt in der Scan-Karte (identische Feldnamen wie bei `/wein-scan`).
  let vorschlag: Record<string, unknown> | null = null;
  let preise: WeinPreis[] = [];
  let quellen: string[] = [];
  let hinweise: string[] = [];
  let confidence = "niedrig";
  if (ean && mitKi && hasOpenAI()) {
    try {
      const roh = await enrichWine({ ean, art: artHinweis });
      const felder = roh.felder ?? {};
      if (Object.keys(felder).length) {
        vorschlag = { ...felder, ean: String(felder.ean ?? "").trim() || ean };
        preise = roh.preise ?? [];
        quellen = roh.quellen ?? [];
        hinweise = roh.hinweise ?? [];
        confidence = roh.confidence || "niedrig";
      }
    } catch {
      vorschlag = null; // KI nicht erreichbar → einfach ohne Vorschlag antworten
    }
  }

  return ok({ known: false, wein: null, bewertungen: [], schnitt: null, vorschlag, preise, quellen, confidence, hinweise });
}
