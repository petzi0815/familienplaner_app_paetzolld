import type BetterSqlite3 from "better-sqlite3";
import { log } from "@/server/observability/logger";
import { hasOpenAI, openaiChat, parseJsonLoose } from "@/server/elisbooks/openai";
import { hasPerplexity, perplexityAsk } from "@/server/wein/perplexity";
import { getWeinSettings } from "@/server/wein/settings";

// Preisrecherche für die Weine im Keller — gemeinsame Grundlage von Route
// (`POST /api/v1/wein-preischeck`) und Job (`wein-preischeck`, nachts um 6).
//
// Zweistufig, weil beide Stufen etwas können, was die andere nicht kann:
//   1. Perplexity ('sonar-pro') sucht LIVE im Netz nach aktuellen Händlerangeboten. Die Antwort ist
//      Prosa mit Quellenliste — brauchbar zum Lesen, nicht zum Rechnen.
//   2. OpenAI (gpt-4o, JSON-Modus) normalisiert diese Prosa in saubere Zahlen. Reine Regex-Extraktion
//      wäre zu fehleranfällig: „ab 12,90 € (6er-Karton 71,40 €)" oder „statt 19,90 € jetzt 14,90 €"
//      liefern sonst regelmäßig den falschen Wert — und ein falscher Preis löst einen falschen
//      Schnäppchen-Push aus.
//
// Fehlt einer der beiden Schlüssel, wird sauber degradiert (Ergebnis mit `fehler`-Text, kein Throw)
// — der Aufrufer zeigt den Klartext an, statt dass die ganze Liste in einen 500er läuft.

export interface PreisTreffer {
  /** Preis für EINE Flasche in Euro (ohne Versand). */
  preis: number;
  haendler: string;
  url?: string;
}

export interface PreisErgebnis {
  weinId: number;
  titel: string;
  treffer: PreisTreffer[];
  /** Günstigstes gefundenes Angebot (fehlt, wenn nichts gefunden wurde). */
  bester?: PreisTreffer;
  /** Hinterlegter Referenzpreis (regulärer Preis) = Basis der Rabattrechnung. */
  referenzpreis?: number;
  /** Ersparnis von `bester` gegenüber `referenzpreis` in Prozent (negativ = teurer als üblich). */
  rabattProzent?: number;
  /** Klartext-Grund, wenn nichts (oder nichts Verwertbares) ermittelt werden konnte. */
  fehler?: string;
}

/** Ergebnis eines Laufs (ein Wein, alle oder die fälligen). */
export interface PreischeckLauf {
  geprueft: number;
  ergebnisse: PreisErgebnis[];
  rabatte: PreisErgebnis[];
  /**
   * Klartext-Grund, wenn der Lauf gar nicht erst stattgefunden hat (fehlender Schlüssel, bereits
   * laufender Sammellauf). `geprueft: 0` ohne `hinweis` heißt schlicht: es war nichts fällig.
   */
  hinweis?: string;
}

/**
 * Kostendeckel pro Lauf: jeder Wein kostet eine Perplexity- UND eine OpenAI-Anfrage. Bei 25 Weinen
 * pro Nacht und dem Standardintervall von 7 Tagen bleiben 175 beobachtete Weine dauerhaft aktuell —
 * mehr als der Keller je haben wird. Der Deckel verhindert, dass ein Massenimport (oder ein auf 1 Tag
 * gestelltes Intervall) über Nacht hunderte API-Aufrufe auslöst.
 */
const MAX_PRO_LAUF = 25;

/** Obergrenze für den ausdrücklichen „alle prüfen"-Lauf (ignoriert das Intervall, nicht die Kosten). */
const MAX_ALLE = 100;

/** Kurze Pause zwischen zwei Weinen — sanft gegenüber beiden Anbietern (Rate-Limits). */
const PAUSE_MS = 400;

/** Mehr als so viele Angebote braucht niemand; der Rest ist ohnehin teurer. */
const MAX_TREFFER = 8;

/** Preis-Plausibilität in Euro je Flasche — filtert Literpreise, Kistenpreise und Tippfehler. */
const PREIS_MIN = 0.5;
const PREIS_MAX = 5000;

/**
 * Hartes Zeitbudget für die OpenAI-Auswertung (`openaiChat({ timeoutMs })` bricht die Verbindung
 * wirklich ab). Ohne Deckel hängt ein stockender Aufruf bis zum undici-Standard von rund 300 s —
 * bei 25 Weinen je Nacht wäre das ein Lauf über Stunden, der über den In-Flight-Guard zugleich
 * jede manuelle Prüfung aussperrt. `perplexityAsk` deckelt sich mit 45 s selbst.
 */
const OPENAI_TIMEOUT_MS = 90000;

interface WeinRow {
  id: number;
  name: string;
  weingut: string | null;
  jahrgang: number | null;
  flaschengroesse_ml: number | null;
  ean: string | null;
  referenzpreis: number | null;
}

const WEIN_COLS = "id, name, weingut, jahrgang, flaschengroesse_ml, ean, referenzpreis";

/** Anzeigename „Weingut Name Jahrgang" — auch der Suchbegriff für die Recherche. */
function weinTitel(w: { name: string; weingut?: string | null; jahrgang?: number | null }): string {
  return [w.weingut?.trim(), w.name?.trim(), w.jahrgang ? String(w.jahrgang) : null].filter(Boolean).join(" ").trim();
}

// ── Normalisierung der Perplexity-Prosa ──────────────────────────────────────

interface RohAngebot { preis?: unknown; haendler?: unknown; url?: unknown }

/** Preis aus Zahl oder Text („12,90 €", "EUR 12.90", „1.299,00 €") — sonst null. */
function zuPreis(v: unknown): number | null {
  if (typeof v === "number") return Number.isFinite(v) ? v : null;
  if (typeof v !== "string") return null;
  // Zahl-Token der ORIGINAL-Zeichenkette zählen, statt alles außer Ziffern wegzuwerfen: sonst
  // klebt „18-22 EUR" zu 1822 und „6 Flaschen 71,40 EUR" zu 671,40 zusammen — beides passiert die
  // Plausibilitätsprüfung und landet als erfundener Bestpreis in der Historie.
  // Mehr als eine Zahl heißt Preisspanne, Gebinde oder Vorher/Nachher: daraus lässt sich kein
  // Flaschenpreis ableiten, also verwerfen statt raten. Keine Zahl („auf Anfrage") ebenso.
  const tokens = v.match(/\d+(?:[.,]\d+)*/g);
  if (!tokens || tokens.length !== 1) return null;
  // Tausenderpunkt raus („1.299,00" → „1299,00"), dann deutsches Dezimalkomma auf Punkt.
  const s = tokens[0].replace(/\.(?=\d{3}(\D|$))/g, "").replace(",", ".");
  const n = Number(s);
  return Number.isFinite(n) ? n : null;
}

/** Gültige http(s)-URL, sonst null. Reine Fußnoten („[2]") werden über die Quellenliste aufgelöst. */
function zuUrl(v: unknown, quellen: string[]): string | undefined {
  if (typeof v !== "string") return undefined;
  const raw = v.trim();
  if (!raw) return undefined;
  const fussnote = raw.match(/^\[?(\d{1,2})\]?$/);
  const kandidat = fussnote ? quellen[Number(fussnote[1]) - 1] ?? "" : raw;
  try {
    const u = new URL(kandidat);
    return u.protocol === "http:" || u.protocol === "https:" ? u.toString() : undefined;
  } catch {
    return undefined;
  }
}

/** Händlername; leer → aus der URL abgeleitet (besser „weinfreunde.de" als gar nichts). */
function zuHaendler(v: unknown, url?: string): string {
  const name = typeof v === "string" ? v.trim().slice(0, 80) : "";
  if (name) return name;
  if (!url) return "";
  try { return new URL(url).hostname.replace(/^www\./, ""); } catch { return ""; }
}

/** Rohe KI-Angebote in geprüfte Treffer überführen (plausibel, entdoppelt, günstigste zuerst). */
function zuTreffern(roh: RohAngebot[], quellen: string[]): PreisTreffer[] {
  const out: PreisTreffer[] = [];
  const gesehen = new Set<string>();
  for (const a of roh) {
    const preis = zuPreis(a?.preis);
    if (preis === null || preis < PREIS_MIN || preis > PREIS_MAX) continue;
    const url = zuUrl(a?.url, quellen);
    const haendler = zuHaendler(a?.haendler, url);
    const key = `${haendler.toLowerCase()}|${preis.toFixed(2)}`;
    if (gesehen.has(key)) continue;
    gesehen.add(key);
    out.push({ preis: Math.round(preis * 100) / 100, haendler, ...(url ? { url } : {}) });
  }
  return out.sort((a, b) => a.preis - b.preis).slice(0, MAX_TREFFER);
}

// ── Ein Wein ─────────────────────────────────────────────────────────────────

/** Nur die Prüfmarke setzen (ohne `updated_at` — eine erfolglose Suche ist keine Datenänderung). */
function stempeln(db: BetterSqlite3.Database, weinId: number): void {
  db.prepare("UPDATE weine SET preis_geprueft_at=datetime('now') WHERE id=?").run(weinId);
}

/**
 * Einen Wein recherchieren: Angebote suchen, normalisieren, Historie schreiben, besten Preis
 * am Wein festhalten.
 *
 * `preis_geprueft_at` wird IMMER gesetzt, sobald eine Recherche stattgefunden hat — auch wenn nichts
 * gefunden wurde, ein Anbieter gerade streikt oder das Speichern der Treffer scheitert. Sonst wäre
 * derselbe Wein sofort wieder fällig und liefe Nacht für Nacht erneut (auf Kosten der Weine dahinter,
 * die nie an die Reihe kämen).
 * NICHT gestempelt wird, wenn ein API-Schlüssel fehlt: dann gab es gar keinen Versuch, und nach dem
 * Nachtragen des Schlüssels soll sofort wieder gesucht werden.
 *
 * `preis_beobachten` wird hier bewusst NICHT geprüft — der direkte Aufruf ist immer eine bewusste
 * Nutzeraktion („Preis jetzt prüfen"). Die Auswahl fürs Automatische macht `faelligeWeine`.
 *
 * `dryRun` unterdrückt nur die DB-Schreibvorgänge; die (kostenpflichtigen) Abfragen laufen trotzdem.
 * Wer einen echten Trockenlauf ohne API-Kosten will, ruft stattdessen nur `faelligeWeine` auf.
 */
export async function checkPreisFuerWein(
  db: BetterSqlite3.Database,
  weinId: number,
  opts: { dryRun?: boolean } = {},
): Promise<PreisErgebnis> {
  const w = db.prepare(`SELECT ${WEIN_COLS} FROM weine WHERE id=?`).get(weinId) as WeinRow | undefined;
  if (!w) return { weinId, titel: `Wein ${weinId}`, treffer: [], fehler: "Wein nicht gefunden." };

  const titel = weinTitel(w) || `Wein ${weinId}`;
  const basis: PreisErgebnis = {
    weinId,
    titel,
    treffer: [],
    ...(w.referenzpreis != null ? { referenzpreis: w.referenzpreis } : {}),
  };

  // Beide Schlüssel vorab prüfen: ohne OpenAI wäre die (kostenpflichtige) Perplexity-Antwort
  // nicht auswertbar — also gar nicht erst suchen.
  if (!hasPerplexity()) {
    return { ...basis, fehler: "Preisrecherche benötigt PERPLEXITY_API_KEY im Backend (Coolify)." };
  }
  if (!hasOpenAI()) {
    return { ...basis, fehler: "Auswertung der Angebote benötigt OPENAI_API_KEY im Backend (Coolify)." };
  }

  const ml = w.flaschengroesse_ml && w.flaschengroesse_ml > 0 ? w.flaschengroesse_ml : 750;
  const frage =
    `Was kostet der Wein „${titel}" aktuell bei deutschen Online-Weinhändlern? ` +
    `Suche konkrete, derzeit lieferbare Angebote für die ${ml}-ml-Flasche` +
    `${w.ean ? ` (EAN ${w.ean})` : ""}. ` +
    "Nenne zu jedem Angebot den Händler, den Preis für eine einzelne Flasche in Euro und den Link zum Produkt. " +
    `Nur genau diesen Wein${w.jahrgang ? ` und genau den Jahrgang ${w.jahrgang}` : ""} — keine anderen Jahrgänge, ` +
    "keine Kisten-, Gebinde- oder Literpreise. Wenn du nichts Passendes findest, sage das ausdrücklich.";

  let recherche: { text: string; citations: string[] };
  try {
    recherche = await perplexityAsk(frage, {
      system:
        "Du bist ein nüchterner Preis-Rechercheur für Wein in Deutschland. Nenne nur Angebote, die du " +
        "wirklich gefunden hast, jeweils mit Händler, Flaschenpreis in Euro und Link. Keine Schätzungen, " +
        "keine Vermutungen, keine Preisspannen ohne Quelle.",
    });
  } catch (e) {
    log.warn("Wein-Preisrecherche fehlgeschlagen", { weinId, error: e instanceof Error ? e.message : String(e) });
    if (!opts.dryRun) stempeln(db, weinId);
    return { ...basis, fehler: "Preissuche nicht erreichbar — beim nächsten Lauf erneut." };
  }

  const quellen = (recherche.citations ?? []).filter((c) => typeof c === "string" && c.trim()).slice(0, 20);
  const quellenListe = quellen.map((q, i) => `${i + 1}. ${q}`).join("\n") || "(keine)";

  const system =
    "Du extrahierst Preisangebote aus einem Rechercheergebnis. Du erfindest nichts und übernimmst nur, " +
    "was im Text wirklich steht. Antworte AUSSCHLIESSLICH als JSON, kein weiterer Text.";
  const user =
    `Wein: ${titel}${w.jahrgang ? "" : " (Jahrgang unbekannt)"}, Flaschengröße ${ml} ml.\n\n` +
    `Rechercheergebnis:\n"""\n${(recherche.text ?? "").slice(0, 8000)}\n"""\n\n` +
    `Quellen (nummeriert):\n${quellenListe}\n\n` +
    "Gib die konkreten Angebote in genau diesem JSON-Schema zurück:\n" +
    '{ "angebote": [ { "preis": number, "haendler": string, "url": string|null } ] }\n' +
    "Regeln:\n" +
    `- Nur Angebote für genau diesen Wein${w.jahrgang ? ` und den Jahrgang ${w.jahrgang}` : ""}.\n` +
    "- preis = Preis für EINE Flasche in Euro, ohne Versand, Punkt als Dezimaltrennzeichen. " +
    "Kisten-/Gebinde-/Literpreise nicht umrechnen, sondern weglassen.\n" +
    "- haendler = Name des Shops (z. B. \"Weinfreunde\"), nicht die URL.\n" +
    "- url = passender Link aus der Quellenliste (sonst null). Statt einer Nummer immer die volle URL.\n" +
    "- Unklares, Widersprüchliches oder Undatiertes weglassen. Kein Angebot gefunden: { \"angebote\": [] }.";

  let roh: RohAngebot[] = [];
  try {
    const antwort = await openaiChat(user, {
      system, json: true, temperature: 0, maxTokens: 900, model: "gpt-4o",
      timeoutMs: OPENAI_TIMEOUT_MS,
    });
    const parsed = parseJsonLoose<{ angebote?: RohAngebot[] } | RohAngebot[]>(antwort);
    roh = Array.isArray(parsed) ? parsed : Array.isArray(parsed?.angebote) ? parsed.angebote : [];
  } catch (e) {
    log.warn("Wein-Preisauswertung fehlgeschlagen", { weinId, error: e instanceof Error ? e.message : String(e) });
    if (!opts.dryRun) stempeln(db, weinId);
    return { ...basis, fehler: "Die gefundenen Angebote konnten nicht ausgewertet werden." };
  }

  const treffer = zuTreffern(roh, quellen);
  const bester = treffer[0];
  const ergebnis: PreisErgebnis = {
    ...basis,
    treffer,
    ...(bester ? { bester } : {}),
    ...(bester && w.referenzpreis != null && w.referenzpreis > 0
      ? { rabattProzent: Math.round((1 - bester.preis / w.referenzpreis) * 100) }
      : {}),
    ...(treffer.length ? {} : { fehler: "Keine passenden Angebote gefunden." }),
  };

  if (opts.dryRun) return ergebnis;

  const insPreis = db.prepare(
    "INSERT INTO wein_preise (wein_id, preis, haendler, url, quelle) VALUES (?,?,?,?,'perplexity')",
  );
  const updWein = db.prepare(
    "UPDATE weine SET bester_preis=?, bester_preis_haendler=?, bester_preis_url=?, " +
    "preis_geprueft_at=datetime('now'), updated_at=datetime('now') WHERE id=?",
  );
  const schreiben = db.transaction(() => {
    for (const t of treffer) insPreis.run(weinId, t.preis, t.haendler, t.url ?? null);
    if (bester) updWein.run(bester.preis, bester.haendler, bester.url ?? null, weinId);
    else stempeln(db, weinId); // nichts gefunden: nur die Prüfmarke, alter Bestpreis bleibt stehen
  });
  try {
    schreiben();
  } catch (e) {
    log.error("Wein-Preise konnten nicht gespeichert werden", { weinId, error: e instanceof Error ? e.message : String(e) });
    // Die (bezahlte) Recherche hat stattgefunden → Prüfmarke trotzdem setzen, sonst steht der Wein
    // in der Folgenacht wieder ganz vorn (ORDER BY COALESCE(julianday(preis_geprueft_at),0)) und
    // belegt dauerhaft einen der Plätze. Eigener try/catch: ein zweiter Fehlschlag (Platte voll,
    // Volume read-only) darf den sauberen Fehler-Rückgabewert nicht in einen Throw verwandeln und
    // damit im Job die restlichen Weine mitreißen.
    try { stempeln(db, weinId); } catch { /* DB gerade generell nicht schreibbar — nichts zu retten */ }
    return { ...ergebnis, fehler: "Die gefundenen Preise konnten nicht gespeichert werden." };
  }
  return ergebnis;
}

// ── Auswahl + Sammellauf ─────────────────────────────────────────────────────

/**
 * Weine, die eine Preisprüfung brauchen: beobachtet, mit Referenzpreis (ohne ihn gibt es nichts zu
 * vergleichen) und länger als `intervallTage` nicht geprüft. Ältester zuerst, damit über mehrere
 * Läufe jeder drankommt.
 *
 * `julianday(...)` statt eines Textvergleichs, weil `preis_geprueft_at` je nach Schreibweg
 * 'YYYY-MM-DD HH:MM:SS' (SQLite) oder ISO mit 'T'/'Z' (JS) enthalten kann — als Text verglichen
 * sortieren sich die beiden Formen falsch. Unlesbare Werte ergeben NULL und gelten als fällig.
 * `intervallTage = 0` liefert damit alle beobachteten Weine (für den „alle prüfen"-Lauf).
 */
export function faelligeWeine(
  db: BetterSqlite3.Database,
  intervallTage: number,
  limit: number = MAX_PRO_LAUF,
): { id: number; titel: string }[] {
  const tage = Number.isFinite(intervallTage) ? Math.max(0, intervallTage) : 7;
  const rows = db.prepare(
    "SELECT id, name, weingut, jahrgang FROM weine " +
    "WHERE preis_beobachten=1 AND referenzpreis IS NOT NULL AND referenzpreis > 0 " +
    "AND (preis_geprueft_at IS NULL OR preis_geprueft_at='' OR julianday(preis_geprueft_at) IS NULL " +
    "     OR julianday(preis_geprueft_at) <= julianday('now') - ?) " +
    "ORDER BY COALESCE(julianday(preis_geprueft_at), 0) ASC, id ASC LIMIT ?",
  ).all(tage, Math.max(1, limit)) as { id: number; name: string; weingut: string | null; jahrgang: number | null }[];
  return rows.map((r) => ({ id: r.id, titel: weinTitel(r) || `Wein ${r.id}` }));
}

/**
 * In-Flight-Guard für die Sammelläufe: der nächtliche Job und ein manueller „alle prüfen"-Klick
 * dürfen sich nicht überlappen (sonst doppelte Kosten und doppelte Historien-Zeilen). Einzelne
 * Weine (`weinId`) laufen absichtlich immer — das ist eine bewusste Nutzeraktion.
 */
let laufend = false;

const pause = (ms: number) => new Promise((res) => setTimeout(res, ms));

function zusammenfassen(ergebnisse: PreisErgebnis[], schwelle: number): PreischeckLauf {
  return {
    geprueft: ergebnisse.length,
    ergebnisse,
    rabatte: ergebnisse.filter((e) => e.bester && (e.rabattProzent ?? 0) >= schwelle),
  };
}

/**
 * Preischeck ausführen — für einen Wein (`weinId`), für alle beobachteten (`alle`) oder für die
 * fälligen (Standard, nach `intervallTage` aus den Einstellungen).
 *
 * `rabatte` = alle Ergebnisse, die die eingestellte Rabattschwelle erreichen. Der Push passiert
 * bewusst NICHT hier, sondern im Job — die Route soll beim manuellen Prüfen nicht die ganze
 * Familie anpiepen.
 */
export async function runPreischeck(
  db: BetterSqlite3.Database,
  opts: { alle?: boolean; weinId?: number; dryRun?: boolean } = {},
): Promise<PreischeckLauf> {
  const settings = getWeinSettings(db);

  if (opts.weinId) {
    const e = await checkPreisFuerWein(db, opts.weinId, { dryRun: opts.dryRun });
    return zusammenfassen([e], settings.rabattProzent);
  }

  // Schlüssel EINMAL vorab prüfen — sonst steigt `checkPreisFuerWein` erst je Wein aus, und der
  // Sammellauf dreht bis zu 100 × 400 ms Leerlauf, um am Ende `geprueft: 100` zu melden, obwohl
  // nichts geprüft wurde. Die Prüfung steht bewusst VOR `laufend = true` (kein Aufruf, kein Guard)
  // und spiegelt den No-Op des nächtlichen Jobs.
  const keyFehler = !hasPerplexity()
    ? "Preisrecherche benötigt PERPLEXITY_API_KEY im Backend (Coolify)."
    : !hasOpenAI()
      ? "Auswertung der Angebote benötigt OPENAI_API_KEY im Backend (Coolify)."
      : null;
  if (keyFehler) return { geprueft: 0, ergebnisse: [], rabatte: [], hinweis: keyFehler };

  if (laufend) return { geprueft: 0, ergebnisse: [], rabatte: [], hinweis: "Es läuft bereits eine Sammelprüfung." };
  laufend = true;
  try {
    // `alle` ignoriert das Intervall (Tage = 0), aber nicht den Kostendeckel.
    const liste = opts.alle ? faelligeWeine(db, 0, MAX_ALLE) : faelligeWeine(db, settings.intervallTage, MAX_PRO_LAUF);
    const ergebnisse: PreisErgebnis[] = [];
    for (let i = 0; i < liste.length; i++) {
      ergebnisse.push(await checkPreisFuerWein(db, liste[i].id, { dryRun: opts.dryRun }));
      if (i < liste.length - 1) await pause(PAUSE_MS); // nur ZWISCHEN zwei Anbieter-Aufrufen
    }
    return zusammenfassen(ergebnisse, settings.rabattProzent);
  } finally {
    laufend = false;
  }
}
