import { getDb } from "@/server/db/connection";
import { getAuth, hasRole } from "@/server/auth/auth";
import { unauthorized, forbidden, fail, ok } from "@/server/http/respond";
import { log } from "@/server/observability/logger";
import { hasOpenAI } from "@/server/elisbooks/openai";
import type { GetraenkeArt } from "@/server/wein/enrich";
import { einreihen, verarbeiteEinen } from "@/server/wein/anreicherung";

// Schnellerfassung: Etikettenfoto (data-URL) oder EAN rein — Flasche steht SOFORT im Inventar.
// Anders als `/wein-scan` (interaktiv, Vorschlag zum Prüfen) wartet hier niemand auf die KI: die
// Zeile wird angelegt (`ki_status='offen'`) und die Anreicherung läuft im Hintergrund. Genau das
// macht den Serienmodus möglich — im Keller stehend eine Flasche nach der anderen fotografieren,
// ohne zwischen den Auslösungen auf eine Recherche zu warten.
//
// `maxDuration` ist deshalb bewusst KLEIN: die Antwort umfasst nur Bild-Ablage und einen INSERT.
// Die eigentliche Kette läuft nebenher (siehe unten) und notfalls über den Job `wein-anreicherung`.
// Eigenes Top-Level-Segment mit Bindestrich, damit es NICHT die generische [domain]-Route verdeckt.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 30;

/** Erlaubte Standorte — identisch zum CHECK aus Migration 0023 ('welches Gebäude', nicht 'welches Regal'). */
const STANDORTE = ["zuhause", "buero"] as const;

/**
 * Hinweis des Aufrufers auf die Getränkeart (der Umschalter in der App). Ungültige Werte werden
 * still ignoriert statt abgelehnt — wie in `/wein-scan`: erkennt die KI die Art am Etikett, gewinnt
 * ohnehin die Erkennung.
 */
function leseArt(v: unknown): GetraenkeArt | undefined {
  const s = String(v ?? "").trim().toLowerCase();
  return s === "wein" || s === "spirituose" ? s : undefined;
}

/** Bestand aus dem Body: nur eine nicht-negative ganze Zahl zählt, sonst entscheidet `einreihen` (Default 1). */
function leseBestand(v: unknown): number | undefined {
  if (v === undefined || v === null || v === "") return undefined;
  const n = Number(v);
  return Number.isInteger(n) && n >= 0 ? n : undefined;
}

export async function POST(req: Request): Promise<Response> {
  const auth = getAuth(req);
  if (!hasRole(auth, "agent")) return auth ? forbidden() : unauthorized();

  let body: Record<string, unknown>;
  try { body = (await req.json()) as Record<string, unknown>; } catch { return fail("bad_json", "Ungültiger JSON-Body.", 400); }

  const image = String(body.image ?? "").trim();
  const ean = String(body.ean ?? "").trim();
  const artHinweis = leseArt(body.art);
  const lagerort = String(body.lagerort ?? "").trim();
  const bestand = leseBestand(body.bestand);

  // Eingabeprüfung wie in `/wein-scan` — der Text-Weg fehlt hier bewusst: ohne Bild und ohne
  // Barcode gäbe es für die Hintergrund-Erkennung nichts zu erkennen, und eine leere Zeile in der
  // Warteschlange ist schlimmer als eine abgelehnte Anfrage.
  if (image && !image.startsWith("data:")) return fail("bad_image", "Feld 'image' muss eine data-URL sein.", 400);
  if (!image && !ean) return fail("no_input", "Mindestens eines der Felder 'image' oder 'ean' ist erforderlich.", 400);

  // Standort wird geprüft statt durchgereicht: der CHECK aus Migration 0023 würde sonst erst beim
  // INSERT zuschlagen (SQLITE_CONSTRAINT → 500). „Büro" mit Umlaut ist der wahrscheinliche Tippfehler,
  // deshalb nennt die Antwort die erlaubten Werte — dieselbe Form wie das generische CRUD.
  const standortRoh = String(body.standort ?? "").trim();
  if (standortRoh && !(STANDORTE as readonly string[]).includes(standortRoh)) {
    return fail("invalid_value", "Feld 'standort' hat einen unbekannten Wert.", 422, { column: "standort", allowed: [...STANDORTE] });
  }
  const standort = standortRoh || undefined;

  const db = getDb();
  let id: number;
  try {
    id = einreihen(db, {
      image: image || undefined,
      ean: ean || undefined,
      art: artHinweis,
      bestand,
      standort,
      lagerort: lagerort || undefined,
    }).id;
  } catch (e) {
    return fail("einreihen_error", "Flasche konnte nicht eingereiht werden.", 500, { detail: String((e as Error)?.message ?? e).slice(0, 200) });
  }

  try {
    db.prepare("INSERT INTO event_log (actor, action, domain, detail) VALUES (?,?,?,?)")
      .run(auth.actor, "wein_erfassen", "wein", JSON.stringify({ id, quelle: image ? "foto" : "ean", art: artHinweis ?? null }));
  } catch { /* Audit best effort — die Flasche steht bereits im Inventar */ }

  const hinweise: string[] = [];
  if (hasOpenAI()) {
    // Fire-and-forget: NICHT awaiten, sonst wäre der ganze Sinn dieser Route dahin.
    // Die Ablehnung MUSS trotzdem gefangen werden — eine unbehandelte Promise-Ablehnung beendet den
    // Node-Prozess (und damit den Server für alle). Der `.catch` ist hier also kein Feintuning,
    // sondern die Betriebssicherheit. Geht der Anstoß verloren (Container-Neustart mitten im Lauf),
    // holt der Job `wein-anreicherung` die Zeile alle 5 Minuten nach — nichts bleibt liegen.
    void verarbeiteEinen(db, id).catch((e) => {
      log.warn("Wein-Anreicherung im Hintergrund abgebrochen", { id, error: e instanceof Error ? e.message : String(e) });
    });
  } else {
    // Ohne Schlüssel wird gar nicht erst angestoßen: jeder Anlauf würde nur `ki_versuche` hochzählen
    // und die Zeile nach drei Fehlschlägen aus der automatischen Wiederholung nehmen. So bleibt sie
    // sauber auf „offen" und wird abgearbeitet, sobald der Schlüssel gesetzt ist.
    hinweise.push("Die Flasche ist erfasst, aber die automatische Erkennung braucht OPENAI_API_KEY im Backend (Coolify).");
  }

  // `art` ist hier der HINWEIS des Aufrufers (die Erkennung kann ihn später überstimmen) — die App
  // stellt danach ihre Liste um und müsste ihn sonst selbst nachhalten.
  return ok({ id, art: artHinweis ?? "wein", ki_status: "offen", ...(hinweise.length ? { hinweise } : {}) });
}
