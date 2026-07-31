import { hasOpenAI, openaiChat, parseJsonLoose } from "@/server/elisbooks/openai";
import { hasPerplexity, perplexityAsk, type PerplexityAnswer } from "@/server/wein/perplexity";

// Dreistufige KI-Anreicherung für den Wein-Bereich (Erfassung per Etikettenfoto, EAN oder Freitext):
//   1. IDENTIFIKATION — was steht wirklich auf der Flasche? (OpenAI gpt-4o Vision bzw. Open Food Facts)
//   2. RECHERCHE      — was weiß das Web? (Perplexity „sonar-pro": Händlerpreise + Hintergrund)
//   3. NORMALISIERUNG — daraus ein sauberer Datensatz in exakt den `weine`-Spalten (OpenAI, JSON-Modus)
// Jede Stufe ist einzeln abgesichert: fällt eine aus (Key fehlt, Anbieter down, Antwort unlesbar),
// wird das als Klartext in `hinweise` vermerkt und die Kette läuft mit dem Teilergebnis weiter.
// Dieses Modul SPEICHERT NICHTS — es liefert nur einen Vorschlag, den der Nutzer bestätigt.

export interface WeinPreis { preis: number; haendler: string; url?: string }

export interface WeinVorschlag {
  felder: Record<string, unknown>;
  preise: WeinPreis[];
  quellen: string[];
  confidence: string;
  hinweise: string[];
}

// ── Erlaubte Werte (müssen zu den CHECK-Constraints aus 0021_wein.sql passen) ────────────────

const TYPEN = new Set(["rot", "weiss", "rose", "sekt", "champagner", "schaumwein", "dessert", "port", "sonstiges"]);
const GESCHMACK = new Set([
  "trocken", "halbtrocken", "feinherb", "lieblich", "suess",
  "brut nature", "extra brut", "brut", "extra dry", "sec", "demi-sec", "unbekannt",
]);
const QUELLEN = new Set(["manuell", "foto", "ean", "ki"]);
const CONFIDENCE = new Set(["hoch", "mittel", "niedrig"]);

/** Schreibweisen, die die KI oder Open Food Facts liefern, auf die erlaubten Werte abbilden. */
const TYP_ALIAS: Record<string, string> = {
  rotwein: "rot", red: "rot", "red wine": "rot", rouge: "rot", tinto: "rot", rosso: "rot",
  weisswein: "weiss", "weißwein": "weiss", "weiß": "weiss", white: "weiss", "white wine": "weiss", blanc: "weiss", bianco: "weiss",
  "rosé": "rose", "roséwein": "rose", rosewein: "rose", rosato: "rose", rosado: "rose",
  winzersekt: "sekt", champagne: "champagner",
  prosecco: "schaumwein", cava: "schaumwein", spumante: "schaumwein", cremant: "schaumwein", "crémant": "schaumwein",
  sparkling: "schaumwein", "sparkling wine": "schaumwein", perlwein: "schaumwein",
  dessertwein: "dessert", suesswein: "dessert", "süßwein": "dessert", sweet: "dessert",
  portwein: "port", porto: "port",
};

const GESCHMACK_ALIAS: Record<string, string> = {
  dry: "trocken", "süß": "suess", "suess ": "suess", "süss": "suess", sweet: "suess",
  "medium dry": "halbtrocken", "off-dry": "feinherb", "brut-nature": "brut nature",
  "extra-brut": "extra brut", "extra-dry": "extra dry", "demi sec": "demi-sec",
};

// ── Spaltenlisten der Tabelle `weine` (alles andere wird verworfen) ──────────────────────────

const TEXT_SPALTEN = new Set([
  "name", "weingut", "land", "region", "lage", "serviertemperatur", "ean",
  "beschreibung", "speiseempfehlung", "notizen", "bester_preis_haendler", "bester_preis_url",
]);
const JSON_SPALTEN = new Set(["rebsorten", "aromen", "auszeichnungen"]);
const BOOL_SPALTEN = new Set(["bio", "vegan"]);

interface NumSpec { min: number; max: number; clamp?: boolean; dez?: number }

/** Jahresgrenzen zur Laufzeit bestimmen (ein lang laufender Server soll über den Jahreswechsel mitziehen). */
function intSpecs(): Record<string, NumSpec> {
  const jahrMax = new Date().getFullYear() + 2;
  return {
    jahrgang: { min: 1900, max: jahrMax },
    // Geschmacksprofil: die KI schätzt hier bewusst — außerhalb 1..5 wird geklemmt statt verworfen.
    suesse: { min: 1, max: 5, clamp: true },
    saeure: { min: 1, max: 5, clamp: true },
    tannin: { min: 1, max: 5, clamp: true },
    koerper: { min: 1, max: 5, clamp: true },
    trinkfenster_von: { min: 1900, max: jahrMax + 30 },
    trinkfenster_bis: { min: 1900, max: jahrMax + 60 },
    flaschengroesse_ml: { min: 50, max: 27000 }, // 0,05 l Probe bis 27 l Großflasche
  };
}

const REAL_SPECS: Record<string, NumSpec> = {
  alkohol: { min: 0, max: 25, dez: 1 },
  referenzpreis: { min: 0.5, max: 100000, dez: 2 },
  bester_preis: { min: 0.5, max: 100000, dez: 2 },
};

// ── Kleine Helfer ────────────────────────────────────────────────────────────────────────────

const kurz = (e: unknown): string => String((e as Error)?.message ?? e).slice(0, 120);

/**
 * Hartes Zeitbudget je OpenAI-Aufruf (`openaiChat({ timeoutMs })` bricht die Verbindung wirklich ab).
 * Ohne Deckel hängt ein stockender Aufruf bis zum undici-Standard von rund 300 s; da Stufe 1 und
 * Stufe 3 nacheinander laufen, wäre eine einzelne Erfassung sonst über zehn Minuten unterwegs,
 * obwohl längst niemand mehr wartet. 90 s lassen auch einem langsamen Vision-Aufruf mit großem
 * Bild Luft. Die übrigen Außenkontakte deckeln sich selbst: `perplexityAsk` 45 s, Open Food Facts 10 s.
 */
const OPENAI_TIMEOUT_MS = 90000;

function str(v: unknown): string | null {
  if (v == null) return null;
  const s = String(v).trim();
  return s ? s : null;
}

/**
 * Zahl aus beliebigem Freitext: „ca. 12,5 % vol" → 12.5, „ab 18,90 €" → 18.9, „1.234,56" → 1234.56.
 * Deutsche Komma-Dezimaltrennung und Tausenderpunkte werden mitgelesen.
 */
function parseNumber(v: unknown): number | null {
  if (typeof v === "number") return Number.isFinite(v) ? v : null;
  if (typeof v === "boolean" || v == null) return null;
  const m = String(v).replace(/\s/g, "").match(/-?\d{1,3}(?:\.\d{3})+(?:,\d+)?|-?\d+(?:[.,]\d+)?/);
  if (!m) return null;
  let s = m[0];
  if (s.includes(",") && /\.\d{3}/.test(s)) s = s.replace(/\./g, "").replace(",", ".");  // 1.234,56
  else if (/^-?\d{1,3}(\.\d{3})+$/.test(s)) s = s.replace(/\./g, "");                    // 1.234
  else s = s.replace(",", ".");
  const n = parseFloat(s);
  return Number.isFinite(n) ? n : null;
}

function bool01(v: unknown): number | null {
  if (typeof v === "boolean") return v ? 1 : 0;
  const s = String(v ?? "").trim().toLowerCase();
  if (["1", "true", "ja", "yes", "bio", "vegan"].includes(s)) return 1;
  if (["0", "false", "nein", "no", "keine", "nicht"].includes(s)) return 0;
  return null;
}

/** Array, JSON-Array-String oder Aufzählung („Merlot, Cabernet") → saubere String-Liste. */
function toStringArray(v: unknown): string[] {
  let items: unknown[] = [];
  if (Array.isArray(v)) items = v;
  else if (typeof v === "string") {
    const trimmed = v.trim();
    const parsed = trimmed.startsWith("[") ? parseJsonLoose<unknown[]>(trimmed) : null;
    items = Array.isArray(parsed) ? parsed : trimmed.split(/[,;/|]/);
  } else return [];
  const out: string[] = [];
  for (const item of items) {
    const s = str(item)?.slice(0, 60);
    if (!s || s.toLowerCase() === "unbekannt") continue;
    if (!out.some((x) => x.toLowerCase() === s.toLowerCase())) out.push(s);
    if (out.length >= 12) break;
  }
  return out;
}

function normalisiere(v: unknown, alias: Record<string, string>, erlaubt: Set<string>): string | null {
  const s = str(v)?.toLowerCase().replace(/\s+/g, " ");
  if (!s) return null;
  const mapped = alias[s] ?? s;
  return erlaubt.has(mapped) ? mapped : null;
}

/** Leere Werte entfernen, damit sie beim Zusammenführen nichts Gutes überschreiben. */
function pruneEmpty(obj: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(obj)) {
    if (v == null) continue;
    if (typeof v === "string" && (!v.trim() || v.trim().toLowerCase() === "unbekannt")) continue;
    if (Array.isArray(v) && v.length === 0) continue;
    out[k] = v;
  }
  return out;
}

/**
 * Behält AUSSCHLIESSLICH gültige `weine`-Spalten, bringt jeden Wert in den Spaltentyp und wirft
 * Werte weg, die außerhalb der CHECK-Listen bzw. plausibler Bereiche liegen. Damit kann das
 * Ergebnis ohne weitere Prüfung ins generische CRUD.
 */
function sanitizeFelder(raw: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  const ints = intSpecs();

  for (const [k, v] of Object.entries(raw)) {
    if (v == null) continue;

    if (TEXT_SPALTEN.has(k)) {
      const s = str(v)?.slice(0, k === "beschreibung" ? 4000 : 400);
      if (!s || s.toLowerCase() === "unbekannt") continue;
      if (k.endsWith("_url") && !/^https?:\/\//i.test(s)) continue;
      if (k === "ean") { const digits = s.replace(/[^0-9]/g, ""); if (digits) out.ean = digits; continue; }
      out[k] = s;
    } else if (k in ints) {
      const spec = ints[k];
      // Flaschengröße kommt oft mit Einheit („0,75 l", „75 cl") statt als Milliliter-Zahl.
      const n = k === "flaschengroesse_ml" && typeof v === "string" ? (volumenMl(v) ?? parseNumber(v)) : parseNumber(v);
      if (n == null) continue;
      const i = Math.round(n);
      if (spec.clamp) out[k] = Math.min(spec.max, Math.max(spec.min, i));
      else if (i >= spec.min && i <= spec.max) out[k] = i;
    } else if (k in REAL_SPECS) {
      const spec = REAL_SPECS[k];
      const n = parseNumber(v);
      if (n == null || n < spec.min || n > spec.max) continue;
      const f = 10 ** (spec.dez ?? 2);
      out[k] = Math.round(n * f) / f;
    } else if (BOOL_SPALTEN.has(k)) {
      const b = bool01(v);
      if (b != null) out[k] = b;
    } else if (JSON_SPALTEN.has(k)) {
      const arr = toStringArray(v);
      if (arr.length) out[k] = JSON.stringify(arr); // Spalten sind TEXT mit JSON-Inhalt
    } else if (k === "typ") {
      const t = normalisiere(v, TYP_ALIAS, TYPEN);
      if (t) out.typ = t;
    } else if (k === "geschmacksrichtung") {
      const g = normalisiere(v, GESCHMACK_ALIAS, GESCHMACK);
      if (g) out.geschmacksrichtung = g;
    } else if (k === "quelle") {
      const q = str(v)?.toLowerCase();
      if (q && QUELLEN.has(q)) out.quelle = q;
    } else if (k === "ki_confidence") {
      const c = str(v)?.toLowerCase();
      if (c && CONFIDENCE.has(c)) out.ki_confidence = c;
    }
    // Alles andere (freitext, etikett_text, erfundene Spalten …) fällt bewusst raus.
  }

  if (typeof out.trinkfenster_von === "number" && typeof out.trinkfenster_bis === "number"
    && (out.trinkfenster_bis as number) < (out.trinkfenster_von as number)) {
    delete out.trinkfenster_bis;
  }
  return out;
}

// ── Stufe 1: Identifikation ──────────────────────────────────────────────────────────────────

const IDENT_SYSTEM = `Du bist Sommelier und liest Weinetiketten.

HARTE REGELN:
- Lies AUSSCHLIESSLICH, was auf dem Etikett wirklich zu sehen ist. Nichts erfinden, nichts ergänzen, nicht raten.
- Felder, die du nicht sicher lesen kannst, LÄSST DU WEG (Schlüssel gar nicht ausgeben).
- Antworte als reines JSON-Objekt, ohne Fließtext und ohne Code-Block.

Mögliche Schlüssel:
{"weingut":"","name":"","jahrgang":2019,"rebsorten":[],"alkohol":13.5,"land":"","region":"","lage":"","typ":"","geschmacksrichtung":"","flaschengroesse_ml":750,"bio":0,"vegan":0,"auszeichnungen":[],"etikett_text":""}

- "name" ist der Weinname OHNE das Weingut, z. B. "Barolo Riserva".
- "typ" ist genau einer von: rot, weiss, rose, sekt, champagner, schaumwein, dessert, port, sonstiges.
- "jahrgang" als Zahl; steht kein Jahrgang auf dem Etikett (üblich bei Sekt/Champagner), Schlüssel weglassen.
- "etikett_text" enthält alles, was du wörtlich lesen kannst (auch Rückenetikett).`;

const IDENT_USER = "Analysiere dieses Weinetikett und gib die gelesenen Angaben als JSON zurück:";

/** Stufe 1a — Etikettenfoto (data-URL) über OpenAI gpt-4o Vision lesen. */
export async function identifyFromLabel(imageDataUrl: string): Promise<Record<string, unknown>> {
  const text = await openaiChat(IDENT_USER, {
    imageDataUrl,
    system: IDENT_SYSTEM,
    model: "gpt-4o",
    maxTokens: 900,
    temperature: 0,
    json: true,
    timeoutMs: OPENAI_TIMEOUT_MS,
  });
  return parseJsonLoose<Record<string, unknown>>(text) ?? {};
}

const OFF_FIELDS = "product_name,product_name_de,generic_name,brands,quantity,labels_tags,categories_tags,countries";

/**
 * Typ aus Open-Food-Facts-Kategorien bzw. Produktnamen ableiten. Nur eindeutige Treffer, sonst nichts —
 * die Etikett-Erkennung und die Normalisierung sind hier ohnehin die besseren Quellen.
 */
function typAusText(s: string): string | null {
  if (/champagne|champagner/.test(s)) return "champagner";
  if (/\bsekt|winzersekt/.test(s)) return "sekt";
  if (/sparkling|prosecco|cava|spumante|cr[eé]mant|perlwein|schaumwein/.test(s)) return "schaumwein";
  if (/\bport(wein|o)?\b/.test(s)) return "port";
  if (/ros[eé]|rosato|rosado/.test(s)) return "rose";
  if (/red[-_ ]?wine|rotwein|vin[-_ ]?rouge|vino[-_ ]?tinto|vino[-_ ]?rosso/.test(s)) return "rot";
  if (/white[-_ ]?wine|wei[sß]{1,2}wein|vin[-_ ]?blanc|vino[-_ ]?blanco|vino[-_ ]?bianco/.test(s)) return "weiss";
  return null;
}

/** „750 ml" / „0,75 l" / „75 cl" → Milliliter. */
function volumenMl(q: string | null): number | null {
  if (!q) return null;
  const m = q.toLowerCase().replace(/\s/g, "").match(/(\d+(?:[.,]\d+)?)(ml|cl|liter|l)/);
  if (!m) return null;
  const n = parseNumber(m[1]);
  if (n == null) return null;
  const faktor = m[2] === "ml" ? 1 : m[2] === "cl" ? 10 : 1000;
  const ml = Math.round(n * faktor);
  return ml >= 50 && ml <= 27000 ? ml : null;
}

/**
 * Stufe 1b — EAN über Open Food Facts vor-identifizieren (freie Produktdatenbank, kein Key nötig).
 * Liefert `{}`, wenn die EAN dort unbekannt ist; wirft nur bei Netz-/HTTP-Fehler.
 */
export async function identifyFromEan(ean: string): Promise<Record<string, unknown>> {
  const clean = ean.replace(/[^0-9]/g, "");
  if (!clean) return {};

  const r = await fetch(`https://world.openfoodfacts.org/api/v2/product/${clean}.json?fields=${OFF_FIELDS}`, {
    headers: { accept: "application/json", "user-agent": "Familienplaner/1.0 (wein-scan)" },
    signal: AbortSignal.timeout(10000),
  });
  if (r.status === 404) return {}; // unbekannte EAN — kein Fehler, nur kein Treffer
  if (!r.ok) throw new Error(`Open Food Facts ${r.status}`);
  const j = (await r.json()) as { status?: number; product?: Record<string, unknown> };
  const p = j.product;
  if (j.status !== 1 || !p) return {};

  const out: Record<string, unknown> = { ean: clean };
  const name = str(p.product_name_de) ?? str(p.product_name) ?? str(p.generic_name);
  if (name) out.name = name;
  const marke = str(p.brands)?.split(",")[0]?.trim();
  if (marke) out.weingut = marke;
  const land = str(p.countries)?.split(",")[0]?.trim();
  if (land) out.land = land;
  const ml = volumenMl(str(p.quantity));
  if (ml) out.flaschengroesse_ml = ml;

  const labels = (Array.isArray(p.labels_tags) ? p.labels_tags.map(String) : []).join(" ").toLowerCase();
  if (/organic|\bbio\b|biologique/.test(labels)) out.bio = 1;
  if (/vegan/.test(labels)) out.vegan = 1;

  // Erst die Kategorien fragen; den Produktnamen nur, wenn es laut Kategorien überhaupt ein Wein ist
  // (sonst wird aus „Vinaigre de Vin Blanc" ein Weißwein).
  const kategorien = (Array.isArray(p.categories_tags) ? p.categories_tags.map(String) : []).join(" ").toLowerCase();
  const istWein = /wine|\bvin\b|wein|vino/.test(kategorien);
  const typ = typAusText(kategorien) ?? (istWein ? typAusText((name ?? "").toLowerCase()) : null);
  if (typ) out.typ = typ;

  const jahr = (name ?? "").match(/\b(19\d{2}|20\d{2})\b/);
  if (jahr) out.jahrgang = Number(jahr[1]);
  return out;
}

// ── Stufe 2: Recherche ───────────────────────────────────────────────────────────────────────

const RESEARCH_SYSTEM = `Du bist ein präziser Wein-Rechercheur für den deutschen Markt.
Du recherchierst im Web und antwortest knapp, sachlich und auf Deutsch.
Was du nicht wirklich gefunden hast, kennzeichnest du als "unbekannt" — du erfindest nichts.`;

/** Suchbezeichnung aus der Identifikation bauen (leer = nicht genug für eine sinnvolle Suche). */
function bezeichnung(ident: Record<string, unknown>): string {
  const teile = [
    str(ident.weingut), str(ident.name), str(ident.jahrgang),
    str(ident.region) ?? str(ident.land),
    toStringArray(ident.rebsorten).join(", ") || null,
  ].filter(Boolean) as string[];
  const basis = teile.join(" ").trim();
  const extra = [str(ident.freitext), str(ident.etikett_text)?.slice(0, 300)].filter(Boolean).join(" ");
  const ean = str(ident.ean);
  if (basis) return [basis, ean ? `EAN ${ean}` : null].filter(Boolean).join(" ");
  if (extra) return extra;
  return ean ? `Wein mit EAN ${ean}` : "";
}

/** Stufe 2 — Live-Recherche über Perplexity. `null`, wenn kein Key oder nichts Suchbares vorliegt. */
export async function researchWine(ident: Record<string, unknown>): Promise<PerplexityAnswer | null> {
  if (!hasPerplexity()) return null;
  const wein = bezeichnung(ident);
  if (!wein) return null;

  const prompt = `Recherchiere diesen Wein: ${wein}

Antworte in genau drei Blöcken:

1) AKTUELLE PREISE
Konkrete Angebote deutscher Online-Händler für die 0,75-l-Flasche, je Zeile im Format
"Händler | Preis in EUR | URL". Nur Angebote, die du tatsächlich gefunden hast, keine Schätzungen.
Hänge "(Aktion)" an, wenn ein Angebot erkennbar ein Sonder-/Aktionspreis ist.

2) REGULÄRER PREIS
Der übliche Preis AUSSERHALB von Aktionen: UVP bzw. Listenpreis des Weinguts oder Importeurs, sonst
der typische Ladenpreis. Format "REGULÄR | Preis in EUR | Beleg". Das ist ausdrücklich NICHT der
Durchschnitt der Angebote aus Block 1 — findest du keinen belegten regulären Preis, schreibe
"REGULÄR | unbekannt".

3) HINTERGRUND
Weingut, Region/Lage, Rebsorten, Ausbau (Stahl/Holzfass, Reifedauer), Geschmacksprofil
(Süße, Säure, Tannin, Körper), typische Aromen, Alkoholgehalt, Geschmacksrichtung (trocken/halbtrocken/…),
Trinkfenster (Jahreszahlen), Auszeichnungen mit Punktzahl, Speiseempfehlung, Serviertemperatur.

Wenn du eine Angabe nicht belegen kannst, schreibe "unbekannt".`;

  return perplexityAsk(prompt, { system: RESEARCH_SYSTEM, maxTokens: 1400 });
}

// ── Stufe 3: Normalisierung ──────────────────────────────────────────────────────────────────

const NORMALIZE_SYSTEM = `Du bist Redakteur einer Wein-Datenbank. Du bekommst eine gesicherte Identifikation
(vom Etikett bzw. aus einer Produktdatenbank) und einen Recherchetext und formst daraus EINEN sauberen
Datensatz. Antworte ausschließlich als reines JSON-Objekt, ohne Fließtext und ohne Code-Block.

HARTE REGELN:
- NICHTS ERFINDEN. Was weder in der Identifikation noch in der Recherche steht, lässt du weg (Schlüssel nicht ausgeben).
- Die Identifikation ist gesichert und wird nicht überschrieben; die Recherche ergänzt sie nur.
- Alle Texte auf Deutsch, sachlich, ohne Werbesprache.
- Zahlen als Zahl mit Punkt als Dezimaltrenner, ohne Einheiten und ohne Währungszeichen.

Struktur:
{
  "felder": {
    "name": "Weinname ohne Weingut",
    "weingut": "",
    "jahrgang": 2019,
    "typ": "rot",
    "rebsorten": ["Nebbiolo"],
    "land": "Italien",
    "region": "Piemont",
    "lage": "",
    "alkohol": 14.5,
    "geschmacksrichtung": "trocken",
    "suesse": 1,
    "saeure": 4,
    "tannin": 4,
    "koerper": 4,
    "aromen": ["Kirsche", "Vanille", "Leder"],
    "serviertemperatur": "16-18 °C",
    "trinkfenster_von": 2024,
    "trinkfenster_bis": 2035,
    "bio": 0,
    "vegan": 0,
    "flaschengroesse_ml": 750,
    "beschreibung": "2 bis 4 Sätze zu Weingut, Lage und Ausbau.",
    "auszeichnungen": ["Falstaff 93"],
    "speiseempfehlung": "",
    "referenzpreis": 24.90
  },
  "preise": [{ "preis": 22.90, "haendler": "Händlername", "url": "https://..." }],
  "confidence": "hoch"
}

WERTEBEREICHE (nur diese Werte, sonst Schlüssel weglassen):
- "typ": rot, weiss, rose, sekt, champagner, schaumwein, dessert, port, sonstiges
- "geschmacksrichtung": trocken, halbtrocken, feinherb, lieblich, suess, brut nature, extra brut, brut, extra dry, sec, demi-sec, unbekannt
- "suesse", "saeure", "tannin", "koerper": ganze Zahl 1 bis 5 (1 = sehr wenig, 5 = sehr viel). Bei Weißwein/Sekt ist "tannin" meist 1.
- "confidence": hoch, mittel, niedrig — "hoch" nur, wenn Weingut, Name und Jahrgang gesichert sind.

PREISE:
- "referenzpreis" ist der REGULÄRE Preis für 0,75 l in Euro: UVP bzw. Listenpreis oder der typische
  Ladenpreis AUSSERHALB von Aktionen — also genau das, was der Recherchetext unter "REGULÄRER PREIS"
  belegt. Er darf NICHT aus den Angeboten berechnet werden (kein Durchschnitt, kein mittleres Angebot):
  der Referenzpreis ist die Basis der späteren Rabattrechnung, und aus denselben Angeboten abgeleitet
  würde er nur die Händlerspreizung messen. Ist kein regulärer Preis belegt, lässt du den Schlüssel weg.
- "preise" enthält nur die aktuellen Händlerangebote, die im Recherchetext wirklich genannt sind.`;

interface NormalizeResult { felder?: unknown; preise?: unknown; confidence?: unknown }

async function normalize(ident: Record<string, unknown>, research: PerplexityAnswer | null): Promise<NormalizeResult> {
  const prompt = [
    "IDENTIFIKATION (gesichert):",
    JSON.stringify(ident),
    "",
    research ? "RECHERCHE (Live-Websuche, Prosa):" : "RECHERCHE: keine verfügbar — nur die Identifikation nutzen.",
    research?.text ?? "",
    research?.citations.length ? `QUELLEN: ${research.citations.slice(0, 15).join(" ")}` : "",
  ].join("\n");

  const text = await openaiChat(prompt, {
    system: NORMALIZE_SYSTEM,
    model: "gpt-4o",
    maxTokens: 2000,
    temperature: 0.1,
    json: true,
    timeoutMs: OPENAI_TIMEOUT_MS,
  });
  return parseJsonLoose<NormalizeResult>(text) ?? {};
}

/** Preisliste der KI in geprüfte Einträge überführen (nur plausible Beträge, Händler Pflicht). */
function sanitizePreise(raw: unknown): WeinPreis[] {
  if (!Array.isArray(raw)) return [];
  const out: WeinPreis[] = [];
  for (const entry of raw) {
    if (!entry || typeof entry !== "object") continue;
    const e = entry as Record<string, unknown>;
    const preis = parseNumber(e.preis ?? e.price);
    if (preis == null || preis < 0.5 || preis > 100000) continue;
    const haendler = (str(e.haendler ?? e.händler ?? e.shop) ?? "").slice(0, 120);
    const url = str(e.url);
    const item: WeinPreis = { preis: Math.round(preis * 100) / 100, haendler };
    if (url && /^https?:\/\//i.test(url)) item.url = url.slice(0, 500);
    if (!item.haendler && !item.url) continue; // ein Preis ohne jede Herkunft ist wertlos
    out.push(item);
    if (out.length >= 15) break;
  }
  return out;
}

/**
 * Näherung an den regulären Preis, wenn die Recherche keinen belegten nennt: die robuste Lage der
 * OBEREN Hälfte der Angebote (Median der teureren Hälfte).
 *
 * Bewusst nicht der Mittelwert oder Median über ALLE Angebote: der Referenzpreis ist die Basis der
 * Rabattrechnung, und läuft gerade eine Aktion, zieht sie den Schnitt mit nach unten — die Basis
 * wäre dauerhaft zu niedrig verankert und ein echter Preisrutsch nie mehr erkennbar. Bewusst auch
 * nicht das Maximum: ein einzelner Ausreißer-Shop soll die Basis nicht bestimmen.
 *
 * Bleibt eine Schätzung — sie wird deshalb als Hinweis ausgewiesen, und der Nutzer kann den
 * Referenzpreis in der Erfassungsmaske korrigieren.
 */
function regulaerNaeherung(preise: WeinPreis[]): number | null {
  if (!preise.length) return null;
  const werte = preise.map((p) => p.preis).sort((a, b) => a - b);
  const obere = werte.slice(Math.floor(werte.length / 2)); // ab dem Median aufwärts
  const mitte = Math.floor(obere.length / 2);
  const m = obere.length % 2 ? obere[mitte] : (obere[mitte - 1] + obere[mitte]) / 2;
  return Math.round(m * 100) / 100;
}

/**
 * Ohne Normalisierung (Stufe 3 aus) bleiben Freitext und abgelesener Etikett-Text sonst liegen —
 * sie landen dann als Notiz im Vorschlag, damit die Eingabe des Nutzers nicht verloren geht.
 */
function uebernehmeRohtextAlsNotiz(felder: Record<string, unknown>, ident: Record<string, unknown>): void {
  if (felder.notizen) return;
  const roh = str(ident.freitext) ?? str(ident.etikett_text);
  if (roh) felder.notizen = roh.slice(0, 400);
}

const RANG: Record<string, number> = { niedrig: 0, mittel: 1, hoch: 2 };
const NAMEN = ["niedrig", "mittel", "hoch"];
const deckeln = (a: string, b: string): string => NAMEN[Math.min(RANG[a] ?? 0, RANG[b] ?? 0)];

// ── Orchestrierung ───────────────────────────────────────────────────────────────────────────

/**
 * Führt die drei Stufen zusammen und liefert den Vorschlag für die Erfassungsmaske.
 * Scheitert NIE hart: jeder Ausfall landet als Klartext in `hinweise`, das Teilergebnis bleibt nutzbar.
 */
export async function enrichWine(input: { image?: string; ean?: string; text?: string }): Promise<WeinVorschlag> {
  const hinweise: string[] = [];
  let ident: Record<string, unknown> = {};

  // ── Stufe 1: Identifikation ──
  if (input.ean) {
    try {
      const off = await identifyFromEan(input.ean);
      if (Object.keys(off).length) ident = off;
      else hinweise.push("Zur EAN ist in der Produktdatenbank (Open Food Facts) nichts hinterlegt — es zählt, was Foto und Recherche hergeben.");
    } catch (e) {
      hinweise.push(`Produktdatenbank (Open Food Facts) nicht erreichbar (${kurz(e)}) — Erfassung läuft ohne EAN-Daten weiter.`);
    }
  }

  if (input.image) {
    if (!hasOpenAI()) {
      hinweise.push("Etikett-Erkennung übersprungen: OPENAI_API_KEY fehlt im Backend (Coolify).");
    } else {
      try {
        // Das Etikett ist die verlässlichste Quelle → seine Werte gewinnen gegen die Produktdatenbank.
        ident = { ...ident, ...pruneEmpty(await identifyFromLabel(input.image)) };
      } catch (e) {
        hinweise.push(`Etikett-Erkennung fehlgeschlagen (${kurz(e)}) — bitte Angaben von Hand prüfen.`);
      }
    }
  }

  const freitext = str(input.text);
  if (freitext) ident.freitext = freitext.slice(0, 1000);
  const ean = input.ean?.replace(/[^0-9]/g, "");
  if (ean) ident.ean = ean;

  const identifiziert = !!bezeichnung(ident);
  if (!identifiziert) hinweise.push("Der Wein konnte nicht identifiziert werden — bitte Weingut und Name von Hand eintragen.");

  // ── Stufe 2: Recherche ──
  let research: PerplexityAnswer | null = null;
  if (!hasPerplexity()) {
    hinweise.push("Live-Recherche übersprungen: PERPLEXITY_API_KEY fehlt im Backend (Coolify) — keine aktuellen Händlerpreise.");
  } else if (identifiziert) {
    try {
      research = await researchWine(ident);
    } catch (e) {
      hinweise.push(`Live-Recherche fehlgeschlagen (${kurz(e)}) — Vorschlag ohne aktuelle Preise.`);
    }
  }

  // ── Stufe 3: Normalisierung ──
  let felder: Record<string, unknown> = {};
  let preise: WeinPreis[] = [];
  let confidence = "niedrig";

  if (!hasOpenAI()) {
    hinweise.push("Normalisierung übersprungen: OPENAI_API_KEY fehlt im Backend (Coolify) — es werden nur direkt gelesene Werte vorgeschlagen.");
    felder = sanitizeFelder(pruneEmpty(ident));
    uebernehmeRohtextAlsNotiz(felder, ident);
  } else {
    try {
      const res = await normalize(ident, research);
      const roh = (res.felder ?? {}) as Record<string, unknown>;
      felder = sanitizeFelder({ ...pruneEmpty(ident), ...pruneEmpty(roh) });
      preise = sanitizePreise(res.preise);
      const c = str(res.confidence)?.toLowerCase();
      confidence = c && CONFIDENCE.has(c) ? c : "niedrig";
    } catch (e) {
      hinweise.push(`Normalisierung fehlgeschlagen (${kurz(e)}) — es werden nur direkt gelesene Werte vorgeschlagen.`);
      felder = sanitizeFelder(pruneEmpty(ident));
      uebernehmeRohtextAlsNotiz(felder, ident);
    }
  }

  // Bester Preis kommt IMMER aus den geprüften Angeboten, nicht aus der Erzählung der KI.
  const guenstigstes = preise.length ? preise.reduce((a, b) => (b.preis < a.preis ? b : a)) : null;
  if (guenstigstes) {
    felder.bester_preis = guenstigstes.preis;
    felder.bester_preis_haendler = guenstigstes.haendler;
    if (guenstigstes.url) felder.bester_preis_url = guenstigstes.url;
    else delete felder.bester_preis_url;
  } else {
    delete felder.bester_preis;
    delete felder.bester_preis_haendler;
    delete felder.bester_preis_url;
  }
  // Referenzpreis = REGULÄRER Preis (UVP/Ladenpreis außerhalb von Aktionen), den die Recherche
  // getrennt von den Angeboten belegen soll. Fehlt er, wird er aus dem oberen Bereich der Angebote
  // genähert — und das wird ausgewiesen, damit niemand eine geratene Zahl für einen Beleg hält.
  if (felder.referenzpreis == null) {
    const genaehert = regulaerNaeherung(preise);
    if (genaehert != null) {
      felder.referenzpreis = genaehert;
      hinweise.push(
        `Kein regulärer Preis (UVP) belegt — als Referenzpreis ist ${genaehert.toFixed(2).replace(".", ",")} € ` +
        "aus dem oberen Bereich der gefundenen Angebote eingetragen. Bitte prüfen und bei Bedarf korrigieren.",
      );
    }
  }

  // Confidence ehrlich halten: ohne Recherche höchstens „mittel", ohne Namen immer „niedrig".
  if (!research) confidence = deckeln(confidence, "mittel");
  if (!str(felder.name) && !str(felder.weingut)) confidence = "niedrig";

  felder.quelle = input.image ? "foto" : ean ? "ean" : "ki";
  felder.ki_confidence = confidence;
  if (ean) felder.ean = ean;

  const quellen = research?.citations.length
    ? research.citations
    : preise.map((p) => p.url).filter((u): u is string => !!u);

  return { felder, preise, quellen, confidence, hinweise };
}
