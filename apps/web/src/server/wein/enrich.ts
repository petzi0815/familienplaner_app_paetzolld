import { hasOpenAI, openaiChat, parseJsonLoose } from "@/server/elisbooks/openai";
import { hasPerplexity, perplexityAsk, type PerplexityAnswer } from "@/server/wein/perplexity";

// Dreistufige KI-Anreicherung für den Bereich „Wein & Spirituosen" (Erfassung per Etikettenfoto,
// EAN oder Freitext):
//   1. IDENTIFIKATION — was steht wirklich auf der Flasche? (OpenAI gpt-4o Vision bzw. Open Food Facts)
//   2. RECHERCHE      — was weiß das Web? (Perplexity „sonar-pro": Händlerpreise + Hintergrund)
//   3. NORMALISIERUNG — daraus ein sauberer Datensatz in exakt den `weine`-Spalten (OpenAI, JSON-Modus)
// Jede Stufe ist einzeln abgesichert: fällt eine aus (Key fehlt, Anbieter down, Antwort unlesbar),
// wird das als Klartext in `hinweise` vermerkt und die Kette läuft mit dem Teilergebnis weiter.
// Dieses Modul SPEICHERT NICHTS — es liefert nur einen Vorschlag, den der Nutzer bestätigt.
//
// EINE Kette, ZWEI Profile: Wein und Spirituose durchlaufen dieselben drei Stufen; art-abhängig sind
// nur die Prompts, die erlaubten Spalten und die Plausibilitätsgrenzen. Insbesondere liest die
// Vision-Stufe die Getränkeart GLEICH MIT — ein eigener Klassifikations-Aufruf wäre ein zweiter
// bezahlter Vision-Call für eine Information, die ohnehin auf demselben Etikett steht.

/** Getränkeart. Steuert Prompts, erlaubte Spalten und Plausibilitätsgrenzen der gesamten Kette. */
export type GetraenkeArt = "wein" | "spirituose";

export interface WeinPreis { preis: number; haendler: string; url?: string }

export interface WeinVorschlag {
  /** Geprüfte `weine`-Spalten. `art` ist IMMER gesetzt (Standard: wein). */
  felder: Record<string, unknown>;
  preise: WeinPreis[];
  quellen: string[];
  confidence: string;
  hinweise: string[];
}

// ── Erlaubte Werte (müssen zu den CHECK-Constraints aus 0021_wein.sql / 0022_spirituosen.sql passen) ──

const ARTEN = new Set(["wein", "spirituose"]);
const TYPEN = new Set(["rot", "weiss", "rose", "sekt", "champagner", "schaumwein", "dessert", "port", "sonstiges"]);
/** Reihenfolge wie in der Migration — nur Spirituosen haben eine Kategorie. */
const KATEGORIEN = new Set([
  "whisky", "gin", "rum", "wodka", "tequila", "mezcal", "cognac", "brandy",
  "grappa", "obstbrand", "likoer", "aperitif", "wermut", "absinth", "sonstiges",
]);
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

/** Wie die KI die Art benennt (englisch, Mehrzahl) → die beiden erlaubten Werte. */
const ART_ALIAS: Record<string, string> = {
  wine: "wein", weine: "wein",
  spirits: "spirituose", spirit: "spirituose", spirituosen: "spirituose",
  schnaps: "spirituose", liquor: "spirituose", "hard liquor": "spirituose",
};

/** Einzahl für Nutzertexte („Als Spirituose erkannt …"). */
const ART_EINZAHL: Record<GetraenkeArt, string> = { wein: "Wein", spirituose: "Spirituose" };

/**
 * Schreibweisen der Spirituosen-Kategorie auf die erlaubten Werte abbilden. Die KI antwortet je nach
 * Etikett englisch, französisch oder deutsch — „Bourbon", „Vodka" und „Weinbrand" sind dieselben
 * Kategorien wie whisky, wodka und brandy und dürfen nicht an der CHECK-Liste scheitern.
 */
const KATEGORIE_ALIAS: Record<string, string> = {
  whiskey: "whisky", bourbon: "whisky", scotch: "whisky", rye: "whisky",
  "single malt": "whisky", "blended whisky": "whisky",
  vodka: "wodka",
  liqueur: "likoer", "likör": "likoer", "liqueur de fruits": "likoer",
  armagnac: "brandy", weinbrand: "brandy",
  calvados: "obstbrand", williams: "obstbrand", williamsbirne: "obstbrand",
  kirsch: "obstbrand", kirschwasser: "obstbrand", obstler: "obstbrand",
  "eau de vie": "obstbrand", "eaux-de-vie": "obstbrand",
  vermouth: "wermut",
  agave: "tequila", mescal: "mezcal",
  aperitivo: "aperitif",
  rhum: "rum", "cachaça": "rum", cachaca: "rum",
  genever: "gin", "london dry": "gin",
  marc: "grappa", tresterbrand: "grappa",
  spirituose: "sonstiges", spirits: "sonstiges", schnaps: "sonstiges",
};

// ── Spaltenlisten der Tabelle `weine` (alles andere wird verworfen) ──────────────────────────

const TEXT_SPALTEN = new Set([
  "name", "weingut", "land", "region", "lage", "serviertemperatur", "ean",
  "beschreibung", "speiseempfehlung", "notizen", "bester_preis_haendler", "bester_preis_url",
  "stil", "fass", "trinkempfehlung",
]);
const JSON_SPALTEN = new Set(["rebsorten", "aromen", "auszeichnungen", "cocktails"]);
const BOOL_SPALTEN = new Set(["bio", "vegan"]);

/**
 * Spalten, die es nur bei EINER Art gibt. Sie werden bei der Gegenart verworfen, statt sie der KI
 * bloß zu verbieten: fragt man ein Sprachmodell nach dem Geschmacksprofil eines Whiskys, liefert es
 * bereitwillig Süße 2 / Tannin 3 — erfundene Werte, die in der Zeile wie gemessene aussähen.
 */
const NUR_WEIN = new Set([
  "rebsorten", "lage", "geschmacksrichtung", "suesse", "saeure", "tannin", "koerper",
  "trinkfenster_von", "trinkfenster_bis",
]);
const NUR_SPIRITUOSE = new Set([
  "kategorie", "stil", "alter_jahre", "fass", "abgefuellt_jahr", "trinkempfehlung", "cocktails",
]);

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
    flaschengroesse_ml: { min: 20, max: 27000 }, // 20-ml-Miniatur bis 27-l-Großflasche
    // Altersangabe der Spirituose („12 Years Old"). Ohne Angabe (NAS) bleibt die Spalte leer —
    // 0 wäre eine Aussage, die auf keinem Etikett steht.
    alter_jahre: { min: 1, max: 100 },
    abgefuellt_jahr: { min: 1900, max: jahrMax },
    // Füllstand ist ein grober Schätzwert vom Balken in der App, kein Messwert → klemmen statt verwerfen.
    fuellstand_prozent: { min: 0, max: 100, clamp: true },
  };
}

const REAL_SPECS: Record<string, NumSpec> = {
  // Achtung: `max` ist hier der WEIN-Wert. Für Spirituosen hebt `sanitizeFelder` die Obergrenze auf
  // ALKOHOL_MAX_SPIRITUOSE an — mit 25 % fiele sonst jeder Rum, Gin und Whisky durch die Prüfung.
  alkohol: { min: 0, max: 25, dez: 1 },
  referenzpreis: { min: 0.5, max: 100000, dez: 2 },
  bester_preis: { min: 0.5, max: 100000, dez: 2 },
};

/** Fassstärke-Abfüllungen erreichen über 60 %; darüber hinaus ist reiner Alkohol die harte Grenze. */
const ALKOHOL_MAX_SPIRITUOSE = 96;

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
 *
 * `art` entscheidet mit, was gültig ist: Spalten der jeweils anderen Art fallen raus, die
 * Alkohol-Obergrenze und die vorgeschlagene Flaschengröße hängen daran.
 */
function sanitizeFelder(raw: Record<string, unknown>, art: GetraenkeArt): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  const ints = intSpecs();

  for (const [k, v] of Object.entries(raw)) {
    if (v == null) continue;
    // Spalten der Gegenart gar nicht erst anfassen — so kann keine Halluzination in die Zeile.
    if (art === "spirituose" ? NUR_WEIN.has(k) : NUR_SPIRITUOSE.has(k)) continue;

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
      const spec = k === "alkohol" && art === "spirituose"
        ? { ...REAL_SPECS.alkohol, max: ALKOHOL_MAX_SPIRITUOSE }
        : REAL_SPECS[k];
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
    } else if (k === "kategorie") {
      const kat = normalisiere(v, KATEGORIE_ALIAS, KATEGORIEN);
      if (kat) out.kategorie = kat;
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

  // Die Spalte ist NOT NULL mit Default 750 — das stimmt für Wein, nicht für Spirituosen (0,7 l ist
  // dort die Standardflasche). Fehlt die Angabe, wird die art-übliche Größe vorgeschlagen, damit
  // eine Ginflasche nicht stillschweigend als 0,75-l-Flasche in der Zeile landet.
  if (out.flaschengroesse_ml == null) out.flaschengroesse_ml = art === "spirituose" ? 700 : 750;

  // Die Art gehört IMMER in den Vorschlag: sie steuert in der App die Erfassungsmaske und hier die
  // Spaltenauswahl. Ohne sie würde eine erkannte Spirituose stillschweigend als Wein gespeichert.
  out.art = art;
  return out;
}

// ── Stufe 1: Identifikation ──────────────────────────────────────────────────────────────────

// EIN Prompt für beide Getränkearten: das Modell entscheidet die Art am selben Etikett, das es
// ohnehin schon vor Augen hat. Ein vorgeschalteter Klassifikations-Aufruf würde dasselbe Bild ein
// zweites Mal bezahlen, ohne mehr zu wissen.
const IDENT_SYSTEM = `Du bist Sommelier und Barkeeper und liest Etiketten von Wein- und Spirituosenflaschen.

HARTE REGELN:
- Lies AUSSCHLIESSLICH, was auf dem Etikett wirklich zu sehen ist. Nichts erfinden, nichts ergänzen, nicht raten.
- Felder, die du nicht sicher lesen kannst, LÄSST DU WEG (Schlüssel gar nicht ausgeben).
- Antworte als reines JSON-Objekt, ohne Fließtext und ohne Code-Block.

Bestimme zuerst die Getränkeart:
- "art" ist genau einer von: wein, spirituose. Bist du dir nicht sicher, lässt du den Schlüssel weg.

Schlüssel für beide Arten:
{"art":"","weingut":"","name":"","alkohol":13.5,"land":"","region":"","flaschengroesse_ml":750,"bio":0,"vegan":0,"auszeichnungen":[],"etikett_text":""}

Nur bei art = "wein" zusätzlich:
{"jahrgang":2019,"rebsorten":[],"lage":"","typ":"","geschmacksrichtung":""}

Nur bei art = "spirituose" zusätzlich:
{"kategorie":"","stil":"","alter_jahre":16,"fass":"","abgefuellt_jahr":2021}

- "weingut" ist der Erzeuger: bei Wein das Weingut, bei Spirituosen die Destillerie bzw. die Marke.
- "name" ist der Produktname OHNE den Erzeuger, z. B. "Barolo Riserva" oder "Distiller's Cut".
- "typ" ist genau einer von: rot, weiss, rose, sekt, champagner, schaumwein, dessert, port, sonstiges.
- "kategorie" ist genau einer von: whisky, gin, rum, wodka, tequila, mezcal, cognac, brandy, grappa, obstbrand, likoer, aperitif, wermut, absinth, sonstiges.
- "stil" ist die Unterart, z. B. "Single Malt Islay", "London Dry", "Añejo".
- "alter_jahre" nur bei einer Altersangabe auf dem Etikett ("12 Years Old"); "No Age Statement" heißt: Schlüssel weglassen.
- "fass" ist die Fassreifung, z. B. "Ex-Bourbon, Oloroso-Finish". "abgefuellt_jahr" ist das Jahr der Abfüllung (Batch/Single Cask).
- "jahrgang" als Zahl; steht kein Jahrgang auf dem Etikett (üblich bei Sekt/Champagner), Schlüssel weglassen.
- "etikett_text" enthält alles, was du wörtlich lesen kannst (auch Rückenetikett).`;

const IDENT_USER = "Analysiere dieses Flaschenetikett und gib die gelesenen Angaben als JSON zurück:";

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

/**
 * Eindeutige Spirituosen-Marker im Kategoriebaum. Die kurzen Wörter bewusst mit Wortgrenzen:
 * „gin" steckt sonst in „ginger ale", „rum" in „Rumänien" — und aus einer Limonade würde ein Gin.
 *
 * Die Oberbegriffe und die PLURALFORMEN sind nicht optional, sondern der Normalfall: Open Food Facts
 * führt eine Ginflasche als `en:distilled-beverages, en:hard-liquors, en:gins` — das Wort „spirits"
 * kommt darin gar nicht vor, und `\bgin\b` scheitert am Plural-s. Ohne diese Alternativen fiele die
 * EAN-Erkennung für Gin und Rum still aus und beide landeten als Wein in der Zeile (live gegen die
 * OFF-API nachgemessen, siehe `scripts/`-Prüfstand in der Session).
 */
const SPIRITUOSEN_MARKER = /spirits?|spirituose|distilled[-_ ]?beverages?|hard[-_ ]?liquors?|\bliquors?\b|whisk|\bgins?\b|\brums?\b|vodkas?|wodka|liqueurs?(?![-_ ]?wein|[-_ ]?wines?)|lik[oö]r(?!wein)|tequilas?|mezcal|brandy|brandies|cognac|armagnac|grappa|eaux?[-_ ]de[-_ ]vie|aperitif|vermouth|wermut|absinth|schnaps/;

/**
 * Spirituosen-Kategorie aus Open-Food-Facts-Kategorien bzw. Produktnamen ableiten — das Gegenstück
 * zu `typAusText`. Von speziell nach allgemein geprüft (Mezcal vor Tequila, Cognac vor Brandy),
 * weil die Kategoriebäume beides nebeneinander führen und der erste Treffer gewinnt. Nur eindeutige
 * Treffer; Etikett und Normalisierung sind hier ohnehin die besseren Quellen.
 */
function kategorieAusText(s: string): string | null {
  if (/whisk|bourbon|scotch|\brye\b/.test(s)) return "whisky";
  if (/mezcal|mescal/.test(s)) return "mezcal";
  if (/tequila|agave/.test(s)) return "tequila";
  if (/cognac/.test(s)) return "cognac";
  // Obstbrand VOR Brandy: Open Food Facts führt Williamsbirne & Co. als `en:fruit-brandies` — ohne
  // diese Reihenfolge zöge die Brandy-Zeile sie an sich und aus dem Obstbrand würde ein Weinbrand.
  if (/calvados|obstbrand|obstler|kirschwasser|williams|zwetschg|fruit[-_ ]?brand/.test(s)) return "obstbrand";
  if (/armagnac|brandy|brandies|weinbrand/.test(s)) return "brandy";
  if (/grappa|tresterbrand/.test(s)) return "grappa";
  if (/\bgins?\b|genever|london[-_ ]dry/.test(s)) return "gin";
  if (/\brums?\b|\brhums?\b|cacha[cç]a/.test(s)) return "rum";
  if (/vodkas?|wodka/.test(s)) return "wodka";
  if (/absinth/.test(s)) return "absinth";
  if (/vermouth|wermut/.test(s)) return "wermut";
  if (/aperitif|aperitivo/.test(s)) return "aperitif";
  // „liqueur-wines"/„Likörwein" ist ein VERSTÄRKTER WEIN (Port, Sherry), kein Likör — die
  // Ausschlüsse verhindern, dass ein Portwein über diese Zeile zur Spirituose wird.
  if (/liqueurs?(?![-_ ]?wein|[-_ ]?wines?)|lik[oö]r(?!wein)/.test(s)) return "likoer";
  // Ganz zuletzt die Oberbegriffe: Open Food Facts hängt `en:eaux-de-vie` als ALLGEMEINEN Knoten
  // über die Rums (Captain Morgan trägt `en:eaux-de-vie, en:rums`). Stünde er wie ursprünglich in
  // der Obstbrand-Zeile, würde jeder so eingeordnete Rum zum Obstbrand — und weil die
  // Identifikation als „gesichert" in die Normalisierung geht, korrigiert das später niemand mehr.
  if (/spirits?|spirituose|schnaps|eaux?[-_ ]de[-_ ]vie|distilled[-_ ]?beverages?|hard[-_ ]?liquors?/.test(s)) return "sonstiges";
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
  // Untergrenze wie in `intSpecs`: 20 ml, damit Spirituosen-Miniaturen (2-cl-Probe) nicht verworfen werden.
  return ml >= 20 && ml <= 27000 ? ml : null;
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
  // `weingut` ist die Erzeuger-Spalte für beide Arten: bei Spirituosen steht hier die Destillerie
  // bzw. die Marke (die Spalte heißt nur so, weil die Tabelle aus dem Weinbereich stammt).
  const marke = str(p.brands)?.split(",")[0]?.trim();
  if (marke) out.weingut = marke;
  const land = str(p.countries)?.split(",")[0]?.trim();
  if (land) out.land = land;
  const ml = volumenMl(str(p.quantity));
  if (ml) out.flaschengroesse_ml = ml;

  const labels = (Array.isArray(p.labels_tags) ? p.labels_tags.map(String) : []).join(" ").toLowerCase();
  if (/organic|\bbio\b|biologique/.test(labels)) out.bio = 1;
  if (/vegan/.test(labels)) out.vegan = 1;

  // Erst die Kategorien fragen; den Produktnamen nur, wenn die Kategorien überhaupt in diese Richtung
  // zeigen (sonst wird aus „Vinaigre de Vin Blanc" ein Weißwein und aus „Ginger Beer" ein Gin).
  const kategorien = (Array.isArray(p.categories_tags) ? p.categories_tags.map(String) : []).join(" ").toLowerCase();
  const produkt = (name ?? "").toLowerCase();
  const istSpirituose = SPIRITUOSEN_MARKER.test(kategorien);
  const istWein = /wine|\bvin\b|wein|vino/.test(kategorien);

  const typ = typAusText(kategorien) ?? (istWein ? typAusText(produkt) : null);
  if (typ) out.typ = typ;
  const kategorie = kategorieAusText(kategorien) ?? (istSpirituose ? kategorieAusText(produkt) : null);
  if (kategorie) out.kategorie = kategorie;

  // Getränkeart nur bei eindeutiger Lage. Bei Doppeltreffern gewinnt die Spirituose: im Kategoriebaum
  // von Weinbrand oder Wermut läuft ein Weinmarker regelmäßig mit („en:wines, en:brandies"),
  // umgekehrt taucht in einem reinen Weinbaum nie ein Spirituosenmarker auf.
  if (istSpirituose || kategorie) out.art = "spirituose";
  else if (istWein || typ) out.art = "wein";

  // Die Jahreszahl im Produktnamen ist nur beim Wein ein Jahrgang; bei Spirituosen wäre „Batch 2019"
  // eher das Abfülljahr — im Zweifel gar nichts vorschlagen statt die falsche Spalte zu füllen.
  const jahr = produkt.match(/\b(19\d{2}|20\d{2})\b/);
  if (jahr && out.art !== "spirituose") out.jahrgang = Number(jahr[1]);
  return out;
}

// ── Stufe 2: Recherche ───────────────────────────────────────────────────────────────────────

const RESEARCH_SYSTEM: Record<GetraenkeArt, string> = {
  wein: `Du bist ein präziser Wein-Rechercheur für den deutschen Markt.
Du recherchierst im Web und antwortest knapp, sachlich und auf Deutsch.
Was du nicht wirklich gefunden hast, kennzeichnest du als "unbekannt" — du erfindest nichts.`,
  spirituose: `Du bist ein präziser Spirituosen-Rechercheur für den deutschen Markt.
Du recherchierst im Web und antwortest knapp, sachlich und auf Deutsch.
Was du nicht wirklich gefunden hast, kennzeichnest du als "unbekannt" — du erfindest nichts.`,
};

/** „16 Jahre" aus einer Altersangabe — Teil des Suchbegriffs, damit die richtige Abfüllung gefunden wird. */
function alterText(v: unknown): string | null {
  const n = parseNumber(v);
  if (n == null) return null;
  const i = Math.round(n);
  return i >= 1 && i <= 100 ? `${i} Jahre` : null;
}

/** Suchbezeichnung aus der Identifikation bauen (leer = nicht genug für eine sinnvolle Suche). */
function bezeichnung(ident: Record<string, unknown>, art: GetraenkeArt): string {
  // Spirituosen haben weder Jahrgang noch Rebsorten — dort unterscheiden Stil und Altersangabe die
  // Abfüllungen („Lagavulin 16 Jahre" statt bloß „Lagavulin"), sonst recherchiert Stufe 2 Preise
  // für die falsche Flasche.
  const teile = (art === "spirituose"
    ? [
      str(ident.weingut), str(ident.name), str(ident.stil), alterText(ident.alter_jahre),
      str(ident.region) ?? str(ident.land),
    ]
    : [
      str(ident.weingut), str(ident.name), str(ident.jahrgang),
      str(ident.region) ?? str(ident.land),
      toStringArray(ident.rebsorten).join(", ") || null,
    ]).filter(Boolean) as string[];
  const basis = teile.join(" ").trim();
  const extra = [str(ident.freitext), str(ident.etikett_text)?.slice(0, 300)].filter(Boolean).join(" ");
  const ean = str(ident.ean);
  if (basis) return [basis, ean ? `EAN ${ean}` : null].filter(Boolean).join(" ");
  if (extra) return extra;
  return ean ? `${ART_EINZAHL[art]} mit EAN ${ean}` : "";
}

/**
 * Stufe 2 — Live-Recherche über Perplexity. `null`, wenn kein Key oder nichts Suchbares vorliegt.
 *
 * Der dreiteilige Blockaufbau mit dem festen Zeilenformat ist teuer erkauft (siehe Memory
 * `reference-perplexity-recherche`): frei formuliert lieferte dieselbe Frage bei demselben Getränk
 * mal drei Angebote, mal keines. Art-abhängig sind deshalb NUR Block 3, die Flaschengröße und die
 * Bezeichnung des Erzeugers — Aufbau und Zeilenformat bleiben wörtlich gleich.
 */
export async function researchWine(
  ident: Record<string, unknown>,
  art: GetraenkeArt = "wein",
): Promise<PerplexityAnswer | null> {
  if (!hasPerplexity()) return null;
  const wein = bezeichnung(ident, art);
  if (!wein) return null;

  const spirituose = art === "spirituose";
  const flasche = spirituose ? "0,7-l-Flasche" : "0,75-l-Flasche";
  const erzeuger = spirituose ? "der Destillerie" : "des Weinguts";
  const hintergrund = spirituose
    ? `Destillerie/Hersteller, Herkunft (Land, Region), Kategorie und Stil (z. B. Single Malt, London Dry),
Altersangabe, Fassreifung und Finish, Alkoholgehalt (auch Fassstärke), typische Aromen,
Trinkempfehlung (pur, on the rocks, im Longdrink), passende Cocktails, Auszeichnungen mit Punktzahl.`
    : `Weingut, Region/Lage, Rebsorten, Ausbau (Stahl/Holzfass, Reifedauer), Geschmacksprofil
(Süße, Säure, Tannin, Körper), typische Aromen, Alkoholgehalt, Geschmacksrichtung (trocken/halbtrocken/…),
Trinkfenster (Jahreszahlen), Auszeichnungen mit Punktzahl, Speiseempfehlung, Serviertemperatur.`;

  const prompt = `Recherchiere ${spirituose ? "diese Spirituose" : "diesen Wein"}: ${wein}

Antworte in genau drei Blöcken:

1) AKTUELLE PREISE
Konkrete Angebote deutscher Online-Händler für die ${flasche}, je Zeile im Format
"Händler | Preis in EUR | URL". Nur Angebote, die du tatsächlich gefunden hast, keine Schätzungen.
Hänge "(Aktion)" an, wenn ein Angebot erkennbar ein Sonder-/Aktionspreis ist.

2) REGULÄRER PREIS
Der übliche Preis AUSSERHALB von Aktionen: UVP bzw. Listenpreis ${erzeuger} oder Importeurs, sonst
der typische Ladenpreis. Format "REGULÄR | Preis in EUR | Beleg". Das ist ausdrücklich NICHT der
Durchschnitt der Angebote aus Block 1 — findest du keinen belegten regulären Preis, schreibe
"REGULÄR | unbekannt".

3) HINTERGRUND
${hintergrund}

Wenn du eine Angabe nicht belegen kannst, schreibe "unbekannt".`;

  return perplexityAsk(prompt, { system: RESEARCH_SYSTEM[art], maxTokens: 1400 });
}

// ── Stufe 3: Normalisierung ──────────────────────────────────────────────────────────────────

/**
 * Preis-Regeln der Normalisierung — bewusst EIN Text für beide Arten, nur die Flaschengröße
 * unterscheidet sich. Dass der Referenzpreis der belegte REGULÄRE Preis ist und NICHT aus den
 * Angeboten gemittelt werden darf, ist teuer erkauft: er ist die Basis der späteren Rabattrechnung,
 * und aus denselben Angeboten abgeleitet misst er nur noch die Händlerspreizung — ein echter
 * Preisrutsch wäre nie mehr erkennbar. Deshalb steht der Absatz genau einmal hier und nicht zweimal
 * nebeneinander, wo die beiden Fassungen auseinanderlaufen könnten.
 */
const PREIS_REGELN = (menge: string): string => `PREISE:
- "referenzpreis" ist der REGULÄRE Preis für ${menge} in Euro: UVP bzw. Listenpreis oder der typische
  Ladenpreis AUSSERHALB von Aktionen — also genau das, was der Recherchetext unter "REGULÄRER PREIS"
  belegt. Er darf NICHT aus den Angeboten berechnet werden (kein Durchschnitt, kein mittleres Angebot):
  der Referenzpreis ist die Basis der späteren Rabattrechnung, und aus denselben Angeboten abgeleitet
  würde er nur die Händlerspreizung messen. Ist kein regulärer Preis belegt, lässt du den Schlüssel weg.
- "preise" enthält nur die aktuellen Händlerangebote, die im Recherchetext wirklich genannt sind.`;

const NORMALIZE_SYSTEM_WEIN = `Du bist Redakteur einer Wein-Datenbank. Du bekommst eine gesicherte Identifikation
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

${PREIS_REGELN("0,75 l")}`;

const NORMALIZE_SYSTEM_SPIRITUOSE = `Du bist Redakteur einer Spirituosen-Datenbank. Du bekommst eine gesicherte Identifikation
(vom Etikett bzw. aus einer Produktdatenbank) und einen Recherchetext und formst daraus EINEN sauberen
Datensatz. Antworte ausschließlich als reines JSON-Objekt, ohne Fließtext und ohne Code-Block.

HARTE REGELN:
- NICHTS ERFINDEN. Was weder in der Identifikation noch in der Recherche steht, lässt du weg (Schlüssel nicht ausgeben).
- Die Identifikation ist gesichert und wird nicht überschrieben; die Recherche ergänzt sie nur.
- Alle Texte auf Deutsch, sachlich, ohne Werbesprache.
- Zahlen als Zahl mit Punkt als Dezimaltrenner, ohne Einheiten und ohne Währungszeichen.
- Das hier ist KEIN Wein: Rebsorten, Jahrgang, Trinkfenster, Geschmacksrichtung und die Weinwerte
  Süße/Säure/Tannin/Körper gibt es nicht — diese Schlüssel gibst du niemals aus.

Struktur:
{
  "felder": {
    "name": "Produktname ohne Destillerie/Marke",
    "weingut": "Destillerie oder Marke",
    "kategorie": "whisky",
    "stil": "Single Malt, Islay",
    "alter_jahre": 16,
    "abgefuellt_jahr": 2021,
    "fass": "Ex-Bourbon, Oloroso-Finish",
    "land": "Schottland",
    "region": "Islay",
    "alkohol": 43.0,
    "aromen": ["Torfrauch", "Vanille", "Meersalz"],
    "trinkempfehlung": "pur oder mit wenigen Tropfen Wasser",
    "cocktails": ["Penicillin", "Rob Roy"],
    "serviertemperatur": "18-20 °C",
    "bio": 0,
    "vegan": 0,
    "flaschengroesse_ml": 700,
    "beschreibung": "2 bis 4 Sätze zu Destillerie, Herkunft und Reifung.",
    "auszeichnungen": ["IWSC Gold 2023"],
    "speiseempfehlung": "",
    "referenzpreis": 64.90
  },
  "preise": [{ "preis": 58.90, "haendler": "Händlername", "url": "https://..." }],
  "confidence": "hoch"
}

WERTEBEREICHE (nur diese Werte, sonst Schlüssel weglassen):
- "kategorie": whisky, gin, rum, wodka, tequila, mezcal, cognac, brandy, grappa, obstbrand, likoer, aperitif, wermut, absinth, sonstiges
- "stil" ist die Unterart in eigenen Worten, z. B. "Single Malt, Islay", "London Dry", "Añejo".
- "alter_jahre": ganze Zahl von 1 bis 100, NUR bei belegter Altersangabe. Ohne Altersangabe (No Age Statement) Schlüssel weglassen.
- "abgefuellt_jahr": vierstelliges Jahr der Abfüllung (Batch, Single Cask), sonst Schlüssel weglassen.
- "alkohol": Volumenprozent, auch Fassstärke (bis 96).
- "trinkempfehlung": kurz, z. B. "pur", "on the rocks", "im Gin Tonic mit Zitronenzeste".
- "cocktails": bekannte Drinks, in denen genau diese Spirituose üblich ist.
- "confidence": hoch, mittel, niedrig — "hoch" nur, wenn Destillerie/Marke, Name und Kategorie gesichert sind.

${PREIS_REGELN("0,7 l")}`;

/** Ein Profil je Art — dieselbe Stufe, nur mit den Spalten und Wertebereichen der jeweiligen Art. */
const NORMALIZE_SYSTEM: Record<GetraenkeArt, string> = {
  wein: NORMALIZE_SYSTEM_WEIN,
  spirituose: NORMALIZE_SYSTEM_SPIRITUOSE,
};

interface NormalizeResult { felder?: unknown; preise?: unknown; confidence?: unknown }

async function normalize(
  ident: Record<string, unknown>,
  research: PerplexityAnswer | null,
  art: GetraenkeArt,
): Promise<NormalizeResult> {
  const prompt = [
    `GETRÄNKEART: ${art}`,
    "IDENTIFIKATION (gesichert):",
    JSON.stringify(ident),
    "",
    research ? "RECHERCHE (Live-Websuche, Prosa):" : "RECHERCHE: keine verfügbar — nur die Identifikation nutzen.",
    research?.text ?? "",
    research?.citations.length ? `QUELLEN: ${research.citations.slice(0, 15).join(" ")}` : "",
  ].join("\n");

  const text = await openaiChat(prompt, {
    system: NORMALIZE_SYSTEM[art],
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

/** Getränkeart aus einem beliebigen Wert lesen (KI-Antwort, Body-Feld, Query) — sonst `null`. */
function leseArt(v: unknown): GetraenkeArt | null {
  return normalisiere(v, ART_ALIAS, ARTEN) as GetraenkeArt | null;
}

/**
 * Führt die drei Stufen zusammen und liefert den Vorschlag für die Erfassungsmaske.
 * Scheitert NIE hart: jeder Ausfall landet als Klartext in `hinweise`, das Teilergebnis bleibt nutzbar.
 *
 * `input.art` ist nur ein HINWEIS des Aufrufers (der Umschalter in der App). Erkennt die Kette am
 * Etikett oder in der Produktdatenbank etwas anderes, gewinnt die Erkennung — im Laden schaltet
 * niemand erst den Umschalter um, bevor er den Barcode scannt.
 */
export async function enrichWine(
  input: { image?: string; ean?: string; text?: string; art?: GetraenkeArt },
): Promise<WeinVorschlag> {
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

  // ── Getränkeart festlegen: Etikett > Produktdatenbank > Hinweis des Aufrufers > Wein ──
  // Die ersten beiden stecken bereits in `ident.art` (das Etikett hat die Produktdatenbank oben
  // überschrieben), sind also schon in der richtigen Rangfolge zusammengeführt.
  const hinweisArt = leseArt(input.art);
  const erkannteArt = leseArt(ident.art);
  const art: GetraenkeArt = erkannteArt ?? hinweisArt ?? "wein";
  if (erkannteArt && hinweisArt && erkannteArt !== hinweisArt) {
    hinweise.push(
      `Als ${ART_EINZAHL[erkannteArt]} erkannt (gewählt war ${ART_EINZAHL[hinweisArt]}) — im Formular umschaltbar.`,
    );
  }
  ident.art = art; // damit die Art auch in den Prompt der Normalisierung geht

  const identifiziert = !!bezeichnung(ident, art);
  if (!identifiziert) {
    hinweise.push(art === "spirituose"
      ? "Die Spirituose konnte nicht identifiziert werden — bitte Destillerie und Name von Hand eintragen."
      : "Der Wein konnte nicht identifiziert werden — bitte Weingut und Name von Hand eintragen.");
  }

  // ── Stufe 2: Recherche ──
  let research: PerplexityAnswer | null = null;
  if (!hasPerplexity()) {
    hinweise.push("Live-Recherche übersprungen: PERPLEXITY_API_KEY fehlt im Backend (Coolify) — keine aktuellen Händlerpreise.");
  } else if (identifiziert) {
    try {
      research = await researchWine(ident, art);
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
    felder = sanitizeFelder(pruneEmpty(ident), art);
    uebernehmeRohtextAlsNotiz(felder, ident);
  } else {
    try {
      const res = await normalize(ident, research, art);
      const roh = (res.felder ?? {}) as Record<string, unknown>;
      felder = sanitizeFelder({ ...pruneEmpty(ident), ...pruneEmpty(roh) }, art);
      preise = sanitizePreise(res.preise);
      const c = str(res.confidence)?.toLowerCase();
      confidence = c && CONFIDENCE.has(c) ? c : "niedrig";
    } catch (e) {
      hinweise.push(`Normalisierung fehlgeschlagen (${kurz(e)}) — es werden nur direkt gelesene Werte vorgeschlagen.`);
      felder = sanitizeFelder(pruneEmpty(ident), art);
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
